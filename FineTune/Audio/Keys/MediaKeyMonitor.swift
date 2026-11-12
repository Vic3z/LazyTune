// FineTune/Audio/Keys/MediaKeyMonitor.swift
import AppKit
import AudioToolbox
import CoreGraphics
import MediaPlayer
import os

/// View-layer collaborators MediaKeyMonitor drives. Abstracting them keeps the audio
/// layer free of concrete view types (HUDWindowController, MenuBarIconCoordinator);
/// the view layer supplies the conformances.
@MainActor
protocol MediaKeyHUDPresenting: AnyObject {
    func show(sliderFraction: Double, mute: Bool, deviceName: String)
    func swallowObserved()
}

@MainActor
protocol MediaKeyIconFlashing: AnyObject {
    func flashDevice()
}

/// Intercepts F10/F11/F12 via a `CGEventTap`, swallows them so the native HUD
/// does not double-fire, and drives the default output device.
@MainActor
final class MediaKeyMonitor {
    // MARK: - Collaborators

    private let decoder: any MediaKeyEventDecoding
    private let audioEngine: AudioEngine
    private let settingsManager: SettingsManager
    private let accessibility: any AccessibilityTrustProviding
    private let hudController: MediaKeyHUDPresenting
    private let popupVisibility: PopupVisibilityService
    private let mediaKeyStatus: MediaKeyStatus
    private let logger = Logger(subsystem: "com.finetuneapp.FineTune", category: "MediaKeyMonitor")

    // MARK: - Tap state

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isSwallowingTap: Bool = false
    private var globalNSEventMonitor: Any?
    private var localNSEventMonitor: Any?
    private var remoteCommandsRegistered = false
    private var lastPlaybackDispatchTime: DispatchTime?

    /// Second `.tapDisabledBy*` inside the watchdog window marks the feature offline.
    private var disableWatchdogTask: Task<Void, Never>?
    private(set) var watchdogOpen: Bool = false

    /// 80 ms floor between DDC-tier repeats — DDC write queues saturate at key-repeat rate.
    var lastDDCRepeatTime: DispatchTime?

    private var ghostTapProbeTask: Task<Void, Never>?

    /// CGEventTaps are per-session; wake leaves them enabled-but-inert.
    private var workspaceObservers: [NSObjectProtocol] = []

    var onRunLoopSourceRemoved: (() -> Void)?

    /// Optional coordinator notified on every volume/mute key event so the menu bar icon
    /// can flash the current device's transport symbol. Wired by FineTuneApp after init.
    var iconCoordinator: MediaKeyIconFlashing?

    /// Plays the system volume-feedback pop on volume key steps. Wired by FineTuneApp after init.
    var feedbackPlayer: VolumeFeedbackPlayer?

    /// Universal Universal Media media player controller for F7/F8/F9 playback keys. Wired by FineTuneApp after init.
    var mediaPlayerController: MediaPlayerController?

    private var isAnyTapFeatureEnabled: Bool {
        settingsManager.appSettings.mediaKeyControlEnabled
            || settingsManager.appSettings.mediaPlayerControlEnabled
    }

    init(
        decoder: any MediaKeyEventDecoding,
        audioEngine: AudioEngine,
        settingsManager: SettingsManager,
        accessibility: any AccessibilityTrustProviding,
        hudController: MediaKeyHUDPresenting,
        popupVisibility: PopupVisibilityService,
        mediaKeyStatus: MediaKeyStatus
    ) {
        self.decoder = decoder
        self.audioEngine = audioEngine
        self.settingsManager = settingsManager
        self.accessibility = accessibility
        self.hudController = hudController
        self.popupVisibility = popupVisibility
        self.mediaKeyStatus = mediaKeyStatus
        subscribeToWorkspaceLifecycle()
    }

    isolated deinit {
        // C callback holds an unretained pointer to self; runloop source must not outlive us.
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let globalNSEventMonitor {
            NSEvent.removeMonitor(globalNSEventMonitor)
        }
        if let localNSEventMonitor {
            NSEvent.removeMonitor(localNSEventMonitor)
        }
        let nc = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { nc.removeObserver(observer) }
    }

    // MARK: - Lifecycle

    /// Idempotent. Installs CGEventTap + NSEvent systemDefined monitors + MPRemoteCommandCenter
    /// for NX_SYSDEFINED media keys (F7/F8/F9 playback + F10/F11/F12 volume).
    func start() {
        guard isAnyTapFeatureEnabled else {
            logger.debug("Media key control disabled in settings; tap not installed")
            return
        }

        installNSEventMonitorsIfNeeded()
        configureRemoteCommandCenterIfNeeded()

        guard tap == nil else { return }

        // NX_SYSDEFINED = 14 (from <IOLLEvent.h>); CGEventType has no Swift case.
        let mask = CGEventMask(1 << 14)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        // Try HID-level tap first; fall back to Session-level tap (Universal Media SPMediaKeyTap style),
        // then listenOnly tap if active swallowing tap is disallowed when AXTrusted is false.
        let candidates: [(CGEventTapLocation, CGEventTapOptions, String)] = [
            (.cghidEventTap, .defaultTap, "hid-default"),
            (.cgSessionEventTap, .defaultTap, "session-default"),
            (.cgAnnotatedSessionEventTap, .defaultTap, "annotated-default"),
            (.cghidEventTap, .listenOnly, "hid-listenOnly"),
            (.cgSessionEventTap, .listenOnly, "session-listenOnly")
        ]

        var selectedTap: CFMachPort?
        var selectedSwallowing = false
        var selectedLabel = "none"

        for (loc, opt, label) in candidates {
            if let candidate = CGEvent.tapCreate(
                tap: loc,
                place: .headInsertEventTap,
                options: opt,
                eventsOfInterest: mask,
                callback: mediaKeyTapCallback,
                userInfo: userInfo
            ) {
                CGEvent.tapEnable(tap: candidate, enable: true)
                if CGEvent.tapIsEnabled(tap: candidate) {
                    selectedTap = candidate
                    selectedSwallowing = (opt == .defaultTap)
                    selectedLabel = label
                    break
                } else {
                    CFMachPortInvalidate(candidate)
                }
            }
        }

        guard let newTap = selectedTap else {
            self.isSwallowingTap = false
            self.mediaKeyStatus.isOffline = false
            logger.notice("No enabled CGEventTap available (AXTrusted=\(self.accessibility.isTrusted)); using NSEvent global monitor + MPRemoteCommandCenter")
            return
        }

        let source = CFMachPortCreateRunLoopSource(nil, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        self.tap = newTap
        self.runLoopSource = source
        self.isSwallowingTap = selectedSwallowing
        self.mediaKeyStatus.isOffline = false
        let isEnabledNow = CGEvent.tapIsEnabled(tap: newTap)
        logger.notice("Media key tap installed (mode=\(selectedLabel, privacy: .public), enabled=\(isEnabledNow), swallowing=\(selectedSwallowing), AXTrusted=\(self.accessibility.isTrusted))")
    }

    private func installNSEventMonitorsIfNeeded() {
        if globalNSEventMonitor == nil {
            globalNSEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] nsEvent in
                MainActor.assumeIsolated {
                    self?.handleNSEventSystemDefined(nsEvent)
                }
            }
        }
        if localNSEventMonitor == nil {
            localNSEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] nsEvent in
                MainActor.assumeIsolated {
                    self?.handleNSEventSystemDefined(nsEvent)
                }
                return nsEvent
            }
        }
    }

    private func handleNSEventSystemDefined(_ nsEvent: NSEvent) {
        guard isAnyTapFeatureEnabled else { return }
        guard nsEvent.subtype.rawValue == 8 else { return }
        let data1 = nsEvent.data1
        let keyType = Int32((data1 & 0xFFFF0000) >> 16)
        if keyType == 16 || keyType == 17 || keyType == 18 || keyType == 19 || keyType == 20 {
            guard settingsManager.appSettings.mediaPlayerControlEnabled else { return }
            if let mediaEvent = decoder.decode(data1: data1), mediaEvent.isPlaybackEvent {
                logger.notice("NSEvent monitor observed media playback key: keyType=\(keyType)")
                handlePlayback(mediaEvent)
            }
        }
    }

    private func configureRemoteCommandCenterIfNeeded() {
        let center = MPRemoteCommandCenter.shared()
        let enabled = settingsManager.appSettings.mediaPlayerControlEnabled
        center.togglePlayPauseCommand.isEnabled = enabled
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.nextTrackCommand.isEnabled = enabled
        center.previousTrackCommand.isEnabled = enabled

        if !remoteCommandsRegistered {
            remoteCommandsRegistered = true
            center.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.settingsManager.appSettings.mediaPlayerControlEnabled else { return }
                    self.logger.notice("MPRemoteCommandCenter received togglePlayPauseCommand")
                    self.handlePlayback(.playPause)
                }
                return .success
            }
            center.playCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.settingsManager.appSettings.mediaPlayerControlEnabled else { return }
                    self.logger.notice("MPRemoteCommandCenter received playCommand")
                    self.handlePlayback(.playPause)
                }
                return .success
            }
            center.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.settingsManager.appSettings.mediaPlayerControlEnabled else { return }
                    self.logger.notice("MPRemoteCommandCenter received pauseCommand")
                    self.handlePlayback(.playPause)
                }
                return .success
            }
            center.nextTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.settingsManager.appSettings.mediaPlayerControlEnabled else { return }
                    self.logger.notice("MPRemoteCommandCenter received nextTrackCommand")
                    self.handlePlayback(.nextTrack)
                }
                return .success
            }
            center.previousTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.settingsManager.appSettings.mediaPlayerControlEnabled else { return }
                    self.logger.notice("MPRemoteCommandCenter received previousTrackCommand")
                    self.handlePlayback(.previousTrack)
                }
                return .success
            }
        }
        mediaPlayerController?.syncSystemNowPlayingSession()
    }

    /// Reconciles tap state against settings. Idempotent.
    func reconcile() {
        if isAnyTapFeatureEnabled {
            let wasOffline = (tap == nil)
            start()
            if wasOffline && tap != nil {
                armGhostTapProbe()
            }
        } else {
            cancelGhostTapProbe()
            stop()
        }
    }

    // MARK: - Workspace lifecycle (sleep/wake, session)

    /// Re-enable on wake/session-activate; disable on sleep/deactivate.
    private func subscribeToWorkspaceLifecycle() {
        let nc = NSWorkspace.shared.notificationCenter
        func add(_ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
            workspaceObservers.append(token)
        }
        add(NSWorkspace.didWakeNotification) { [weak self] in self?.handleWake() }
        add(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.handleWake() }
        add(NSWorkspace.willSleepNotification) { [weak self] in self?.handleSuspend() }
        add(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.handleSuspend() }
    }

    private func handleWake() {
        guard let tap else {
            reconcile()
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Media key tap re-enabled after wake / session activation")
        armGhostTapProbe()
    }

    private func handleSuspend() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        logger.info("Media key tap disabled for sleep / session resign")
    }

    // MARK: - Ghost-tap probe

    /// Checks `tapIsEnabled` ~1.5s after install; marks offline if the kernel dropped it.
    private func armGhostTapProbe() {
        cancelGhostTapProbe()
        ghostTapProbeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, let tap = self.tap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                self.logger.error("Ghost-tap probe: tap reports disabled after regrant/wake — marking offline")
                self.mediaKeyStatus.isOffline = true
            }
            self.ghostTapProbeTask = nil
        }
    }

    private func cancelGhostTapProbe() {
        ghostTapProbeTask?.cancel()
        ghostTapProbeTask = nil
    }

    /// Tears down the tap + runloop source. Must be called before dealloc.
    func stop() {
        disableWatchdogTask?.cancel()
        disableWatchdogTask = nil
        watchdogOpen = false
        cancelGhostTapProbe()

        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            onRunLoopSourceRemoved?()
        }
        if let globalNSEventMonitor {
            NSEvent.removeMonitor(globalNSEventMonitor)
            self.globalNSEventMonitor = nil
        }
        if let localNSEventMonitor {
            NSEvent.removeMonitor(localNSEventMonitor)
            self.localNSEventMonitor = nil
        }
        tap = nil
        runLoopSource = nil
        logger.info("Media key tap removed")
    }

    // MARK: - Event handling

    /// Applies a decoded `MediaKeyEvent` to the default output device or active media player.
    func handle(_ event: MediaKeyEvent, shiftHeld: Bool = false, optionHeld: Bool = false) {
        if event.isPlaybackEvent {
            handlePlayback(event)
            return
        }

        let volumeMonitor = audioEngine.deviceVolumeMonitor
        let deviceID = volumeMonitor.defaultDeviceID
        guard deviceID.isValid else {
            logger.debug("Ignoring media key: no valid default output device")
            return
        }
        let tier = volumeMonitor.outputVolumeBackend(for: deviceID)
        let deviceName = audioEngine.deviceMonitor.outputDevices.first { $0.id == deviceID }?.name ?? ""
        handleCore(
            event: event,
            deviceID: deviceID,
            tier: tier,
            deviceName: deviceName,
            currentVolume: volumeMonitor.volumes[deviceID] ?? 0,
            currentMute: volumeMonitor.muteStates[deviceID] ?? false,
            setVolume: { id, vol in volumeMonitor.setVolume(for: id, to: vol) },
            setMute:   { id, mute in volumeMonitor.setMute(for: id, to: mute) },
            playFeedback: { gain in
                self.feedbackPlayer?.requestFeedback(
                    gain: gain,
                    shiftHeld: shiftHeld,
                    optionHeld: optionHeld
                )
            }
        )
    }

    func handlePlayback(_ event: MediaKeyEvent, fromSwallowingTap: Bool = false) {
        // Deduplicate within 250ms in case CGEventTap, NSEvent monitor, and MPRemoteCommandCenter
        // all observe the same physical or synthesized media key press.
        let now = DispatchTime.now()
        if let last = lastPlaybackDispatchTime {
            let deltaMs = (now.uptimeNanoseconds &- last.uptimeNanoseconds) / 1_000_000
            if deltaMs < 250 {
                logger.debug("Deduplicated playback event (\(deltaMs)ms since last)")
                return
            }
        }
        lastPlaybackDispatchTime = now

        switch event {
        case .playPause:
            mediaPlayerController?.playPauseToggle(fromSwallowingTap: fromSwallowingTap)
        case .nextTrack:
            mediaPlayerController?.nextTrack(fromSwallowingTap: fromSwallowingTap)
        case .previousTrack:
            mediaPlayerController?.previousTrack(fromSwallowingTap: fromSwallowingTap)
        case .volumeUp, .volumeDown, .muteToggle:
            break
        }
    }

    /// `.ddc` tier coalesces repeats to an 80 ms floor; hardware/software pass them through.
    /// Mute repeats are dropped upstream. Stepping operates on slider-position; HUD receives
    /// the slider fraction so it always matches the popup device row.
    func handleCore(
        event: MediaKeyEvent,
        deviceID: AudioDeviceID,
        tier: VolumeControlTier,
        deviceName: String,
        currentVolume: Float,
        currentMute: Bool,
        setVolume: (AudioDeviceID, Float) -> Void,
        setMute: (AudioDeviceID, Bool) -> Void,
        playFeedback: (Float) -> Void = { _ in }
    ) {
        let shouldShowHUD = !popupVisibility.isVisible
        let sliderDelta = settingsManager.appSettings.volumeHotkeyStep.sliderDelta
        let currentSlider = VolumeMapping.sliderFraction(forSystemGain: currentVolume, tier: tier)

        switch event {
        case .volumeUp(let isRepeat):
            if isRepeat && tier == .ddc && isDDCRepeatCoalesced() {
                logger.debug("DDC repeat coalesced")
                return
            }
            let nextSlider = min(1.0, currentSlider + sliderDelta)
            let newVolume = VolumeMapping.systemGain(forSliderFraction: nextSlider, tier: tier)
            // Volume-up from muted unmutes (system HUD parity).
            if currentMute {
                setMute(deviceID, false)
            }
            setVolume(deviceID, newVolume)
            playFeedback(VolumeFeedback.gain(tier: tier, sliderFraction: nextSlider))
            if shouldShowHUD {
                hudController.show(sliderFraction: nextSlider, mute: false, deviceName: deviceName)
            }
            iconCoordinator?.flashDevice()

        case .volumeDown(let isRepeat):
            if isRepeat && tier == .ddc && isDDCRepeatCoalesced() {
                logger.debug("DDC repeat coalesced")
                return
            }
            let nextSlider = max(0, currentSlider - sliderDelta)
            let newVolume = VolumeMapping.systemGain(forSliderFraction: nextSlider, tier: tier)
            let willBeSilent = nextSlider <= 0.001
            // muted+audible → unmute; unmuted+silent → auto-mute (system HUD parity).
            if currentMute && !willBeSilent {
                setMute(deviceID, false)
            } else if !currentMute && willBeSilent {
                setMute(deviceID, true)
            }
            setVolume(deviceID, newVolume)
            playFeedback(VolumeFeedback.gain(tier: tier, sliderFraction: nextSlider))
            if shouldShowHUD {
                hudController.show(sliderFraction: nextSlider, mute: willBeSilent, deviceName: deviceName)
            }
            iconCoordinator?.flashDevice()

        case .muteToggle:
            let newMute = !currentMute
            setMute(deviceID, newMute)
            if shouldShowHUD {
                hudController.show(sliderFraction: currentSlider, mute: newMute, deviceName: deviceName)
            }
            iconCoordinator?.flashDevice()

        case .playPause, .nextTrack, .previousTrack:
            handlePlayback(event)
        }
    }

    /// `true` if this repeat falls inside the 80 ms floor and should be dropped.
    private func isDDCRepeatCoalesced() -> Bool {
        let now = DispatchTime.now()
        if let last = lastDDCRepeatTime {
            let deltaNs = now.uptimeNanoseconds &- last.uptimeNanoseconds
            if deltaNs < 80 * 1_000_000 { return true }
        }
        lastDDCRepeatTime = now
        return false
    }

    // MARK: - Tap-disabled watchdog

    /// Kernel disabled the tap. One-shot re-enable; second disable inside 5s marks offline.
    func handleTapDisabled() {
        logger.notice("Tap disabled by kernel — attempting re-enable")

        if watchdogOpen {
            // Second disable inside the 5s window — feature is offline.
            logger.error("Second tap-disable inside watchdog window; marking media keys offline")
            mediaKeyStatus.isOffline = true
            disableWatchdogTask?.cancel()
            disableWatchdogTask = nil
            watchdogOpen = false
            return
        }

        watchdogOpen = true
        disableWatchdogTask?.cancel()
        disableWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.watchdogOpen = false
            self?.disableWatchdogTask = nil
        }

        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    // MARK: - Callback bridge

    /// Returns `true` if the caller should swallow the event.
    fileprivate func processSystemDefined(_ cgEvent: CGEvent) -> Bool {
        guard isAnyTapFeatureEnabled else { return false }
        guard let nsEvent = NSEvent(cgEvent: cgEvent) else { return false }
        // Subtype 8 is the media-key channel; aux-button / brightness are pass-through.
        guard nsEvent.subtype.rawValue == 8 else { return false }
        let data1 = nsEvent.data1
        let keyType = Int32((data1 & 0xFFFF0000) >> 16)

        // Universal Media F7/F8/F9 playback keys (16=Play, 17=Next, 18=Previous, 19=Fast, 20=Rewind):
        // Swallow BOTH key-down and key-up so macOS `rcd` never receives key-up to launch Apple Music.
        // Dispatch playback action asynchronously so the CGEventTap callback returns immediately (<1us)
        // and never triggers kCGEventTapDisabledByTimeout during AppleScript IPC.
        if keyType == 16 || keyType == 17 || keyType == 18 || keyType == 19 || keyType == 20 {
            guard settingsManager.appSettings.mediaPlayerControlEnabled else { return false }
            let swallowed = self.isSwallowingTap
            if let mediaEvent = decoder.decode(data1: data1), mediaEvent.isPlaybackEvent {
                logger.notice("Intercepted media playback key: keyType=\(keyType) (swallowed=\(swallowed))")
                Task { @MainActor [weak self] in
                    self?.handlePlayback(mediaEvent, fromSwallowingTap: swallowed)
                }
            }
            return swallowed
        }

        // Volume keys (0=Up, 1=Down, 7=Mute):
        guard settingsManager.appSettings.mediaKeyControlEnabled else { return false }
        guard let mediaEvent = decoder.decode(data1: data1), mediaEvent.isVolumeEvent else { return false }

        hudController.swallowObserved()
        handle(
            mediaEvent,
            shiftHeld: cgEvent.flags.contains(.maskShift),
            optionHeld: cgEvent.flags.contains(.maskAlternate)
        )
        return true
    }
}

// MARK: - CGEventTap C callback

// Tap installs on `CFRunLoopGetMain()` so this runs on main; `assumeIsolated`
// preserves ordering against the next event (a Task-hop would reorder).
private let mediaKeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            monitor.handleTapDisabled()
        }
        return nil
    }

    // NX_SYSDEFINED = 14; no Swift case in CGEventType.
    guard type.rawValue == 14 else {
        return Unmanaged.passUnretained(event)
    }

    // CGEvent is a CF type without Swift's Sendable conformance, so wrap it for
    // the synchronous hop into MainActor — assumeIsolated runs inline on the
    // current (main) thread, no real cross-actor send happens.
    struct EventBox: @unchecked Sendable { let event: CGEvent }
    let box = EventBox(event: event)
    let shouldSwallow = MainActor.assumeIsolated {
        monitor.processSystemDefined(box.event)
    }
    return shouldSwallow ? nil : Unmanaged.passUnretained(event)
}
