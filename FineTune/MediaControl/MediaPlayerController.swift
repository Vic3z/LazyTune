// FineTune/MediaControl/MediaPlayerController.swift
import AppKit
import Foundation
import MediaPlayer
import os

/// Central coordinator for universal universal media key & web/native player control,
/// supercharged with FineTune's CoreAudio real-time process audibility detection.
@MainActor
@Observable
final class MediaPlayerController {
    private let logger = Logger(subsystem: "com.finetuneapp.FineTune", category: "MediaPlayerController")

    let strategyRegistry: MediaStrategyRegistry
    private let audioEngine: AudioEngine
    private let settingsManager: SettingsManager
    private let hudController: HUDWindowController

    private(set) var availableTargets: [any MediaTargetAdapting] = []
    private(set) var activeTarget: (any MediaTargetAdapting)?
    private(set) var currentTrackInfo: MediaTrackInfo?
    private(set) var isPlayingState: Bool = false
    private(set) var isPinnedTarget: Bool = false

    /// Pre-keypress playback state (debounced by 400ms on external notifications so a simultaneous
    /// `mediaremoted` notification at t+1ms never flips `wasPlaying` before `NSEvent` monitor runs at t+2ms).
    private var stablePlayingState: Bool = false
    private var stableStateUpdateTask: Task<Void, Never>?

    private var pinnedTargetID: String?
    private var lastActiveTargetID: String?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var metadataRefreshTask: Task<Void, Never>?
    private var statePollTask: Task<Void, Never>?

    init(
        strategyRegistry: MediaStrategyRegistry,
        audioEngine: AudioEngine,
        settingsManager: SettingsManager,
        hudController: HUDWindowController
    ) {
        self.strategyRegistry = strategyRegistry
        self.audioEngine = audioEngine
        self.settingsManager = settingsManager
        self.hudController = hudController
        subscribeToWorkspaceNotifications()
        subscribeToDistributedPlayerNotifications()
        startBackgroundStatePoll()
    }

    isolated deinit {
        metadataRefreshTask?.cancel()
        statePollTask?.cancel()
        let nc = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            nc.removeObserver(observer)
        }
        let dnc = DistributedNotificationCenter.default()
        for observer in distributedObservers {
            dnc.removeObserver(observer)
        }
    }

    /// Zero-CPU background check using FineTune's in-memory CoreAudio peak levels (no AppleScript polling).
    private func startBackgroundStatePoll() {
        statePollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2500))
                guard !Task.isCancelled, let self else { break }
                if let target = self.activeTarget {
                    if self.audioEngine.isAudibleNow(bundleID: target.bundleID) && !self.isPlayingState {
                        self.isPlayingState = true
                        self.stablePlayingState = true
                    }
                }
            }
        }
    }

    private func scheduleStablePlayingStateUpdate(_ playing: Bool) {
        stableStateUpdateTask?.cancel()
        stableStateUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.stablePlayingState = playing
        }
    }

    /// Subscribes to native push notifications from Spotify and Apple Music (zero polling overhead).
    private func subscribeToDistributedPlayerNotifications() {
        let dnc = DistributedNotificationCenter.default()
        let spotifyToken = dnc.addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let stateStr = (note.userInfo?["Player State"] as? String)?.lowercased() ?? ""
            let titleStr = note.userInfo?["Name"] as? String
            let artistStr = note.userInfo?["Artist"] as? String
            let albumStr = note.userInfo?["Album"] as? String
            MainActor.assumeIsolated {
                guard let self else { return }
                let playing = stateStr == "playing"
                if self.activeTarget?.bundleID == "com.spotify.client" || self.activeTarget == nil {
                    self.isPlayingState = playing
                    self.scheduleStablePlayingStateUpdate(playing)
                    if let titleStr, !titleStr.isEmpty {
                        self.currentTrackInfo = MediaTrackInfo(
                            title: titleStr,
                            artist: artistStr,
                            album: albumStr,
                            isPlaying: playing,
                            playerName: "Spotify",
                            bundleID: "com.spotify.client"
                        )
                    }
                    self.syncSystemNowPlayingSession()
                }
            }
        }
        distributedObservers.append(spotifyToken)

        let musicToken = dnc.addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let stateStr = (note.userInfo?["Player State"] as? String)?.lowercased() ?? ""
            let titleStr = note.userInfo?["Name"] as? String
            let artistStr = note.userInfo?["Artist"] as? String
            let albumStr = note.userInfo?["Album"] as? String
            MainActor.assumeIsolated {
                guard let self else { return }
                let playing = stateStr == "playing"
                if self.activeTarget?.bundleID == "com.apple.Music" {
                    self.isPlayingState = playing
                    self.scheduleStablePlayingStateUpdate(playing)
                    if let titleStr, !titleStr.isEmpty {
                        self.currentTrackInfo = MediaTrackInfo(
                            title: titleStr,
                            artist: artistStr,
                            album: albumStr,
                            isPlaying: playing,
                            playerName: "Apple Music",
                            bundleID: "com.apple.Music"
                        )
                    }
                    self.syncSystemNowPlayingSession()
                }
            }
        }
        distributedObservers.append(musicToken)
    }

    // MARK: - Target Discovery & Resolution

    /// Scans running native media apps and open browser tabs matching Universal Media strategies
    /// or Universal HTML5 media, then selects the best active target.
    func refreshAvailableTargets() {
        let appSettings = settingsManager.appSettings
        let disabledIDs = appSettings.disabledMediaStrategies
        let universalFallback = appSettings.universalHTML5FallbackEnabled

        let audibleBundleIDs = Set(
            audioEngine.apps
                .compactMap(\.bundleID)
                .filter { audioEngine.isAudibleNow(bundleID: $0) }
        )

        var discovered: [any MediaTargetAdapting] = []

        // 1. Running native players (never launches closed apps; Apple Music only if already running)
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleID)
        )
        for def in NativePlayerDefinition.all where runningBundleIDs.contains(def.bundleID) {
            let adapter = NativePlayerAdapter(
                definition: def,
                isAudibleProvider: { [weak self] bundleID in
                    self?.audioEngine.isAudibleNow(bundleID: bundleID) ?? false
                }
            )
            discovered.append(adapter)
        }

        // 2. Open browser tabs matching Universal Media strategies or Universal HTML5 fallback
        let browserTabs = BrowserTabAdapter.discoverMediaTabs(
            registry: strategyRegistry,
            disabledStrategyIDs: disabledIDs,
            universalFallbackEnabled: universalFallback,
            audibleBundleIDs: audibleBundleIDs,
            isAudibleProvider: { [weak self] bundleID in
                self?.audioEngine.isAudibleNow(bundleID: bundleID) ?? false
            }
        )
        discovered.append(contentsOf: browserTabs)

        self.availableTargets = discovered
        resolveBestTarget(audibleBundleIDs: audibleBundleIDs)
        updateCurrentTrackSnapshot()
        syncSystemNowPlayingSession()
    }

    private func resolveBestTarget(audibleBundleIDs: Set<String>) {
        guard !availableTargets.isEmpty else {
            activeTarget = nil
            isPinnedTarget = false
            return
        }

        // 1. Honor user-pinned target if it still exists
        if let pinnedID = pinnedTargetID,
           let pinned = availableTargets.first(where: { $0.id == pinnedID }) {
            activeTarget = pinned
            isPinnedTarget = true
            return
        } else {
            pinnedTargetID = nil
            isPinnedTarget = false
        }

        // 2. Target whose app is currently outputting audio in CoreAudio AND playing
        let audibleTargets = availableTargets.filter { audibleBundleIDs.contains($0.bundleID) }
        if !audibleTargets.isEmpty {
            if audibleTargets.count == 1, let single = audibleTargets.first {
                activeTarget = single
                lastActiveTargetID = single.id
                return
            }
            if let playingAudible = audibleTargets.first(where: { $0.isPlaying() }) {
                activeTarget = playingAudible
                lastActiveTargetID = playingAudible.id
                return
            }
            if let firstAudible = audibleTargets.first {
                activeTarget = firstAudible
                lastActiveTargetID = firstAudible.id
                return
            }
        }

        // 3. Target that is currently frontmost (if user is actively looking at it)
        if let frontmost = availableTargets.first(where: { $0.isFrontmost() }) {
            if frontmost.isPlaying() || lastActiveTargetID == nil {
                activeTarget = frontmost
                lastActiveTargetID = frontmost.id
                return
            }
        }

        // 4. Any target reporting isPlaying() == true
        if let playingTarget = availableTargets.first(where: { $0.isPlaying() }) {
            activeTarget = playingTarget
            lastActiveTargetID = playingTarget.id
            return
        }

        // 5. Last active target (so pressing Play after Pause resumes the same tab/app!)
        if let lastID = lastActiveTargetID,
           let last = availableTargets.first(where: { $0.id == lastID }) {
            activeTarget = last
            return
        }

        // 6. Frontmost target or first available target
        if let frontmost = availableTargets.first(where: { $0.isFrontmost() }) {
            activeTarget = frontmost
            lastActiveTargetID = frontmost.id
            return
        }

        activeTarget = availableTargets.first
        lastActiveTargetID = activeTarget?.id
    }

    func updateCurrentTrackSnapshot() {
        guard let target = activeTarget else {
            currentTrackInfo = nil
            isPlayingState = false
            stablePlayingState = false
            return
        }
        let playing = target.isPlaying()
        isPlayingState = playing
        stablePlayingState = playing
        if var info = target.fetchTrackInfo() {
            info.isPlaying = playing
            currentTrackInfo = info
        } else {
            currentTrackInfo = MediaTrackInfo(
                title: target.title,
                artist: target.subtitle,
                isPlaying: playing,
                playerName: target.displayName,
                bundleID: target.bundleID
            )
        }
    }

    // MARK: - Media Key & Shortcut Commands

    func playPauseToggle(fromSwallowingTap: Bool = true) {
        stableStateUpdateTask?.cancel()
        let preKeyPlayingState = self.stablePlayingState
        if activeTarget == nil {
            refreshAvailableTargets()
        }
        guard let target = activeTarget else {
            logger.notice("playPauseToggle: no activeTarget found; using fallback MediaRemote")
            handleFallbackMediaRemote(command: .togglePlayPause, symbol: "playpause.fill", label: "Play / Pause")
            return
        }

        let wasPlaying: Bool
        if fromSwallowingTap {
            wasPlaying = target.isPlaying()
        } else {
            wasPlaying = preKeyPlayingState
        }
        let nowPlaying = !wasPlaying
        logger.notice("playPauseToggle: target=\(target.id, privacy: .public) (\(target.displayName, privacy: .public)) wasPlaying=\(wasPlaying) -> shouldPlay=\(nowPlaying) (swallowed=\(fromSwallowingTap))")
        target.setPlaying(nowPlaying)
        lastActiveTargetID = target.id
        isPlayingState = nowPlaying
        stablePlayingState = nowPlaying

        var info = target.fetchTrackInfo() ?? MediaTrackInfo(
            title: target.title,
            artist: target.subtitle,
            isPlaying: nowPlaying,
            playerName: target.displayName,
            bundleID: target.bundleID
        )
        info.isPlaying = nowPlaying
        currentTrackInfo = info
        syncSystemNowPlayingSession()

        if settingsManager.appSettings.showMediaHUD {
            hudController.showMediaHUD(
                track: info,
                icon: target.icon,
                actionSymbol: nowPlaying ? "play.fill" : "pause.fill",
                statusText: nowPlaying ? "Playing" : "Paused"
            )
        }
        scheduleDelayedTrackRefresh()
    }

    func nextTrack(fromSwallowingTap: Bool = true) {
        if activeTarget == nil {
            refreshAvailableTargets()
        }
        guard let target = activeTarget else {
            logger.notice("nextTrack: no activeTarget found; using fallback MediaRemote")
            handleFallbackMediaRemote(command: .nextTrack, symbol: "forward.fill", label: "Next Track")
            return
        }

        let beforeTitle = currentTrackInfo?.title
        lastActiveTargetID = target.id
        if fromSwallowingTap {
            logger.notice("nextTrack (swallowed): target=\(target.id, privacy: .public)")
            target.next()
            presentActionHUD(for: target, actionSymbol: "forward.fill", statusText: "Next Track", delayMs: 220)
        } else {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                guard let self else { return }
                let afterTitle = target.fetchTrackInfo()?.title
                if beforeTitle == nil || afterTitle == beforeTitle {
                    self.logger.notice("nextTrack (unswallowed, applying): target=\(target.id, privacy: .public)")
                    target.next()
                } else {
                    self.logger.notice("nextTrack (unswallowed, already advanced to \(afterTitle ?? "", privacy: .public))")
                }
                self.presentActionHUD(for: target, actionSymbol: "forward.fill", statusText: "Next Track", delayMs: 180)
            }
        }
    }

    func previousTrack(fromSwallowingTap: Bool = true) {
        if activeTarget == nil {
            refreshAvailableTargets()
        }
        guard let target = activeTarget else {
            logger.notice("previousTrack: no activeTarget found; using fallback MediaRemote")
            handleFallbackMediaRemote(command: .previousTrack, symbol: "backward.fill", label: "Previous Track")
            return
        }

        let beforeTitle = currentTrackInfo?.title
        lastActiveTargetID = target.id
        if fromSwallowingTap {
            logger.notice("previousTrack (swallowed): target=\(target.id, privacy: .public)")
            target.previous()
            presentActionHUD(for: target, actionSymbol: "backward.fill", statusText: "Previous Track", delayMs: 220)
        } else {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                guard let self else { return }
                let afterTitle = target.fetchTrackInfo()?.title
                if beforeTitle == nil || afterTitle == beforeTitle {
                    self.logger.notice("previousTrack (unswallowed, applying): target=\(target.id, privacy: .public)")
                    target.previous()
                } else {
                    self.logger.notice("previousTrack (unswallowed, already changed to \(afterTitle ?? "", privacy: .public))")
                }
                self.presentActionHUD(for: target, actionSymbol: "backward.fill", statusText: "Previous Track", delayMs: 180)
            }
        }
    }

    func favoriteTrack() {
        if activeTarget == nil {
            refreshAvailableTargets()
        }
        guard let target = activeTarget else { return }
        target.favorite()
        presentActionHUD(for: target, actionSymbol: "heart.fill", statusText: "Favorited", delayMs: 200)
    }

    /// Universal Media "Set Active Tab" — pins the frontmost browser tab or media app as the active target.
    func setActiveTargetFromFrontmost() {
        refreshAvailableTargets()
        if let frontmost = availableTargets.first(where: { $0.isFrontmost() }) {
            selectTarget(frontmost)
            if settingsManager.appSettings.showMediaHUD {
                let info = currentTrackInfo ?? MediaTrackInfo(
                    title: frontmost.title,
                    artist: frontmost.subtitle,
                    playerName: frontmost.displayName,
                    bundleID: frontmost.bundleID
                )
                hudController.showMediaHUD(
                    track: info,
                    icon: frontmost.icon,
                    actionSymbol: "pin.fill",
                    statusText: "Pinned Active Player"
                )
            }
        } else if let current = activeTarget {
            if settingsManager.appSettings.showMediaHUD {
                let info = currentTrackInfo ?? MediaTrackInfo(
                    title: current.title,
                    artist: current.subtitle,
                    playerName: current.displayName,
                    bundleID: current.bundleID
                )
                hudController.showMediaHUD(
                    track: info,
                    icon: current.icon,
                    actionSymbol: "music.note",
                    statusText: current.displayName
                )
            }
        }
    }

    /// Universal Media "Bring Player to Front" — activates the browser window/tab or native player.
    func activatePlayingTarget() {
        if activeTarget == nil {
            refreshAvailableTargets()
        }
        activeTarget?.activate()
    }

    /// Cycles through detected media players (direction: +1 for next, -1 for previous).
    func switchPlayer(direction: Int) {
        refreshAvailableTargets()
        guard !availableTargets.isEmpty else { return }

        let currentIndex = availableTargets.firstIndex(where: { $0.id == activeTarget?.id }) ?? 0
        let count = availableTargets.count
        let nextIndex = ((currentIndex + direction) % count + count) % count
        let nextTarget = availableTargets[nextIndex]
        selectTarget(nextTarget)

        if settingsManager.appSettings.showMediaHUD {
            let info = currentTrackInfo ?? MediaTrackInfo(
                title: nextTarget.title,
                artist: nextTarget.subtitle,
                playerName: nextTarget.displayName,
                bundleID: nextTarget.bundleID
            )
            hudController.showMediaHUD(
                track: info,
                icon: nextTarget.icon,
                actionSymbol: "arrow.left.arrow.right",
                statusText: "Switched to \(nextTarget.displayName)"
            )
        }
    }

    /// Manually selects and pins a target from the popup menu.
    func selectTarget(_ target: any MediaTargetAdapting) {
        if settingsManager.appSettings.pausePreviousOnPlayerSwitch,
           let previous = activeTarget,
           previous.id != target.id,
           previous.isPlaying() {
            previous.pause()
        }
        pinnedTargetID = target.id
        lastActiveTargetID = target.id
        activeTarget = target
        isPinnedTarget = true
        updateCurrentTrackSnapshot()
    }

    /// Unpins manual selection and returns to automatic CoreAudio-aware target resolution.
    func clearPinnedTarget() {
        pinnedTargetID = nil
        isPinnedTarget = false
        refreshAvailableTargets()
    }

    /// Displays the on-screen Tahoe HUD with the current track metadata.
    func showTrackInfoHUD() {
        refreshAvailableTargets()
        guard let target = activeTarget else {
            hudController.showMediaHUD(
                track: MediaTrackInfo(title: "No Active Media Player", artist: "Open a media tab or player"),
                icon: nil,
                actionSymbol: "music.note.list",
                statusText: nil
            )
            return
        }
        updateCurrentTrackSnapshot()
        if let info = currentTrackInfo {
            hudController.showMediaHUD(
                track: info,
                icon: target.icon,
                actionSymbol: isPlayingState ? "speaker.wave.2.fill" : "pause.fill",
                statusText: info.subtitleLine
            )
        }
    }

    /// Pauses any currently playing target (invoked on headphone unplug or system sleep).
    func pauseAllPlayingTargets(reason: String) {
        refreshAvailableTargets()
        var pausedAny = false
        if let active = activeTarget, active.isPlaying() {
            active.pause()
            pausedAny = true
        }
        for target in availableTargets where target.isPlaying() {
            target.pause()
            pausedAny = true
        }
        if pausedAny {
            isPlayingState = false
            logger.info("Auto-paused active media player (\(reason))")
        }
    }

    // MARK: - Auto-Pause Hooks (Headphone Unplug & Sleep)

    func handleOutputDeviceDisconnected() {
        guard settingsManager.appSettings.autoPauseOnHeadphoneDisconnect else { return }
        pauseAllPlayingTargets(reason: "output device disconnected")
    }

    private func subscribeToWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        let sleepToken = nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settingsManager.appSettings.autoPauseOnSleep else { return }
                self.pauseAllPlayingTargets(reason: "system will sleep")
            }
        }
        workspaceObservers.append(sleepToken)

        let resignToken = nc.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settingsManager.appSettings.autoPauseOnSleep else { return }
                self.pauseAllPlayingTargets(reason: "user session resigned")
            }
        }
        workspaceObservers.append(resignToken)

        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshAvailableTargets()
                }
            }
            workspaceObservers.append(token)
        }
    }

    // MARK: - Helpers

    private func presentActionHUD(
        for target: any MediaTargetAdapting,
        actionSymbol: String,
        statusText: String,
        delayMs: Int
    ) {
        metadataRefreshTask?.cancel()
        metadataRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled, let self else { return }
            self.updateCurrentTrackSnapshot()
            guard self.settingsManager.appSettings.showMediaHUD else { return }
            let info = self.currentTrackInfo ?? MediaTrackInfo(
                title: target.title,
                artist: target.subtitle,
                playerName: target.displayName,
                bundleID: target.bundleID
            )
            self.hudController.showMediaHUD(
                track: info,
                icon: target.icon,
                actionSymbol: actionSymbol,
                statusText: statusText
            )
        }
    }

    private func scheduleDelayedTrackRefresh() {
        metadataRefreshTask?.cancel()
        metadataRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.updateCurrentTrackSnapshot()
            self.syncSystemNowPlayingSession()
        }
    }

    /// Keeps macOS `MPNowPlayingInfoCenter` synchronized so `mediaremoted` routes hardware/AirPods
    /// F7/F8/F9 remote commands to FineTune even if CGEventTap is not swallowing events.
    func syncSystemNowPlayingSession() {
        let center = MPNowPlayingInfoCenter.default()
        guard settingsManager.appSettings.mediaPlayerControlEnabled else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var dict: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrackInfo?.title ?? activeTarget?.displayName ?? "FineTune Media Control",
            MPMediaItemPropertyArtist: currentTrackInfo?.artist ?? activeTarget?.subtitle ?? "LazyTune Universal Player",
            MPNowPlayingInfoPropertyPlaybackRate: isPlayingState ? 1.0 : 0.0
        ]
        if let album = currentTrackInfo?.album, !album.isEmpty {
            dict[MPMediaItemPropertyAlbumTitle] = album
        }
        center.nowPlayingInfo = dict
        // Keep `.playing` or `.paused` so macOS `rcd`/`mediaremoted` treats FineTune as an active Now Playing client
        center.playbackState = isPlayingState ? .playing : .paused
    }

    private func handleFallbackMediaRemote(
        command: SystemMediaRemoteBridge.Command,
        symbol: String,
        label: String
    ) {
        // Only send generic MediaRemote command if there is an audible non-Music app in CoreAudio
        // so we never accidentally wake Apple Music when nothing is playing.
        let audibleApp = audioEngine.apps.first { app in
            guard let bid = app.bundleID else { return false }
            return audioEngine.isAudibleNow(bundleID: bid)
        }

        if let app = audibleApp {
            _ = SystemMediaRemoteBridge.shared.sendCommand(command)
            if settingsManager.appSettings.showMediaHUD {
                hudController.showMediaHUD(
                    track: MediaTrackInfo(
                        title: app.name,
                        artist: label,
                        playerName: app.name,
                        bundleID: app.bundleID
                    ),
                    icon: app.icon,
                    actionSymbol: symbol,
                    statusText: label
                )
            }
        } else if settingsManager.appSettings.showMediaHUD {
            hudController.showMediaHUD(
                track: MediaTrackInfo(
                    title: "No Active Media Player",
                    artist: "Open a media tab or app to control playback"
                ),
                icon: nil,
                actionSymbol: symbol,
                statusText: nil
            )
        }
    }
}

private extension NSRunningApplication {
    var bundleID: String? { bundleIdentifier }
}
