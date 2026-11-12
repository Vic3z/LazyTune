// FineTune/MediaControl/Adapters/NativePlayerAdapter.swift
import AppKit
import Foundation
import os

/// Definition of native macOS media players supported out of the box (modeled after universal
/// `NativeAppTabAdapter` subclasses: `SpotifyTabAdapter`, `iTunesTabAdapter`, `VLCTabAdapter`,
/// `VOXTabAdapter`, `TidalTabAdapter`, plus modern macOS players like IINA, Swinsian, Doppler, etc.).
nonisolated struct NativePlayerDefinition: Sendable, Identifiable {
    enum ControlDialect: Sendable {
        case spotify
        case appleMusic
        case vlc
        case vox
        case swinsian
        case systemMediaRemote
    }

    var id: String { bundleID }
    let bundleID: String
    let displayName: String
    let dialect: ControlDialect

    static let all: [NativePlayerDefinition] = [
        NativePlayerDefinition(bundleID: "com.spotify.client", displayName: "Spotify", dialect: .spotify),
        NativePlayerDefinition(bundleID: "org.videolan.vlc", displayName: "VLC", dialect: .vlc),
        NativePlayerDefinition(bundleID: "com.coppertino.Vox", displayName: "VOX", dialect: .vox),
        NativePlayerDefinition(bundleID: "com.swinsian.Swinsian", displayName: "Swinsian", dialect: .swinsian),
        NativePlayerDefinition(bundleID: "com.colliderli.iina", displayName: "IINA", dialect: .systemMediaRemote),
        NativePlayerDefinition(bundleID: "com.tidal.desktop", displayName: "TIDAL", dialect: .systemMediaRemote),
        NativePlayerDefinition(bundleID: "com.amazon.music", displayName: "Amazon Music", dialect: .systemMediaRemote),
        NativePlayerDefinition(bundleID: "com.deezer.deezer-desktop", displayName: "Deezer", dialect: .systemMediaRemote),
        NativePlayerDefinition(bundleID: "com.qobuz.QobuzDesktop", displayName: "Qobuz", dialect: .systemMediaRemote),
        NativePlayerDefinition(bundleID: "com.apple.Music", displayName: "Apple Music", dialect: .appleMusic),
        NativePlayerDefinition(bundleID: "com.apple.podcasts", displayName: "Apple Podcasts", dialect: .systemMediaRemote)
    ]
}

@MainActor
final class NativePlayerAdapter: MediaTargetAdapting {
    let definition: NativePlayerDefinition
    private let isAudibleProvider: @MainActor (String) -> Bool
    private var cachedTitle: String?

    var id: String {
        "native:\(definition.bundleID)"
    }

    var displayName: String {
        definition.displayName
    }

    var title: String {
        cachedTitle ?? definition.displayName
    }

    var subtitle: String {
        definition.displayName
    }

    var bundleID: String {
        definition.bundleID
    }

    var isNativeApp: Bool {
        true
    }

    var supportsFavorite: Bool {
        definition.dialect == .appleMusic
    }

    var icon: NSImage? {
        NSRunningApplication.runningApplications(withBundleIdentifier: definition.bundleID).first?.icon
            ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: definition.displayName)
    }

    init(
        definition: NativePlayerDefinition,
        isAudibleProvider: @escaping @MainActor (String) -> Bool
    ) {
        self.definition = definition
        self.isAudibleProvider = isAudibleProvider
    }

    func isPlaying() -> Bool {
        // 1. Check FineTune's real-time CoreAudio process tap first!
        if isAudibleProvider(definition.bundleID) {
            return true
        }

        // 2. Check AppleScript playerState for scriptable native apps
        switch definition.dialect {
        case .spotify, .appleMusic, .swinsian:
            let state = Self.runAppleScript("""
                tell application id "\(definition.bundleID)"
                    if it is running then
                        return (player state as string)
                    end if
                end tell
                return "stopped"
                """)?.lowercased() ?? ""
            return state.contains("playing")
        case .vlc:
            let playing = Self.runAppleScript("""
                tell application id "org.videolan.vlc"
                    if it is running then
                        return (playing as string)
                    end if
                end tell
                return "false"
                """)?.lowercased() ?? ""
            return playing == "true" || playing == "1"
        case .vox:
            let state = Self.runAppleScript("""
                tell application id "com.coppertino.Vox"
                    if it is running then
                        return (player state as string)
                    end if
                end tell
                return "0"
                """)?.lowercased() ?? ""
            return state == "1" || state.contains("playing")
        case .systemMediaRemote:
            return SystemMediaRemoteBridge.shared.isPlaying(bundleID: definition.bundleID)
        }
    }

    func setPlaying(_ shouldPlay: Bool) {
        if !shouldPlay {
            pause()
            return
        }
        switch definition.dialect {
        case .spotify, .appleMusic, .vox, .swinsian:
            _ = Self.runAppleScript("""
                tell application id "\(definition.bundleID)"
                    if it is running then play
                end tell
                """)
        case .vlc:
            _ = Self.runAppleScript("""
                tell application id "org.videolan.vlc"
                    if it is running and (not playing) then play
                end tell
                """)
        case .systemMediaRemote:
            _ = SystemMediaRemoteBridge.shared.sendCommand(.play)
        }
    }

    func toggle() {
        switch definition.dialect {
        case .spotify, .appleMusic, .vox, .swinsian:
            _ = Self.runAppleScript("""
                tell application id "\(definition.bundleID)"
                    if it is running then playpause
                end tell
                """)
        case .vlc:
            _ = Self.runAppleScript("""
                tell application id "org.videolan.vlc"
                    if it is running then play
                end tell
                """)
        case .systemMediaRemote:
            _ = SystemMediaRemoteBridge.shared.sendCommand(.togglePlayPause)
        }
    }

    func pause() {
        switch definition.dialect {
        case .spotify, .appleMusic, .vox, .swinsian:
            _ = Self.runAppleScript("""
                tell application id "\(definition.bundleID)"
                    if it is running then pause
                end tell
                """)
        case .vlc:
            _ = Self.runAppleScript("""
                tell application id "org.videolan.vlc"
                    if it is running and playing then play
                end tell
                """)
        case .systemMediaRemote:
            _ = SystemMediaRemoteBridge.shared.sendCommand(.pause)
        }
    }

    func next() {
        switch definition.dialect {
        case .spotify, .appleMusic, .vox, .swinsian:
            _ = Self.runAppleScript("""
                tell application id "\(definition.bundleID)"
                    if it is running then next track
                end tell
                """)
        case .vlc:
            _ = Self.runAppleScript("""
                tell application id "org.videolan.vlc"
                    if it is running then next
                end tell
                """)
        case .systemMediaRemote:
            _ = SystemMediaRemoteBridge.shared.sendCommand(.nextTrack)
        }
    }

    func previous() {
        switch definition.dialect {
        case .spotify, .appleMusic, .vox, .swinsian:
            _ = Self.runAppleScript("""
                tell application id "\(definition.bundleID)"
                    if it is running then previous track
                end tell
                """)
        case .vlc:
            _ = Self.runAppleScript("""
                tell application id "org.videolan.vlc"
                    if it is running then previous
                end tell
                """)
        case .systemMediaRemote:
            _ = SystemMediaRemoteBridge.shared.sendCommand(.previousTrack)
        }
    }

    func favorite() {
        if definition.dialect == .appleMusic {
            _ = Self.runAppleScript("""
                tell application id "com.apple.Music"
                    if it is running then
                        try
                            set favorited of current track to (not (favorited of current track))
                        end try
                    end if
                end tell
                """)
        }
    }

    func fetchTrackInfo() -> MediaTrackInfo? {
        let info = fetchTrackInfoCore()
        if let info, !info.title.isEmpty {
            if let artist = info.artist, !artist.isEmpty {
                cachedTitle = "\(info.title) - \(artist)"
            } else {
                cachedTitle = info.title
            }
        }
        return info
    }

    private func fetchTrackInfoCore() -> MediaTrackInfo? {
        switch definition.dialect {
        case .spotify:
            let raw = Self.runAppleScript("""
                tell application id "com.spotify.client"
                    if it is running and player state is not stopped then
                        set tName to name of current track
                        set tArtist to artist of current track
                        set tAlbum to album of current track
                        set tArt to artwork url of current track
                        set pState to (player state as string)
                        return tName & "\\t" & tArtist & "\\t" & tAlbum & "\\t" & tArt & "\\t" & pState
                    end if
                end tell
                return ""
                """) ?? ""
            let parts = raw.components(separatedBy: "\t")
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            let artURL = (parts.count >= 4 && !parts[3].isEmpty) ? URL(string: parts[3]) : nil
            let playing = (parts.count >= 5) ? parts[4].lowercased().contains("playing") : isPlaying()
            return MediaTrackInfo(
                title: parts[0],
                artist: parts[1],
                album: parts[2],
                artworkURL: artURL,
                isPlaying: playing,
                playerName: definition.displayName,
                bundleID: definition.bundleID
            )

        case .appleMusic, .swinsian:
            let raw = Self.runAppleScript("""
                tell application id "\(definition.bundleID)"
                    if it is running and player state is not stopped then
                        try
                            set tName to name of current track
                            set tArtist to artist of current track
                            set tAlbum to album of current track
                            set pState to (player state as string)
                            return tName & "\\t" & tArtist & "\\t" & tAlbum & "\\t" & pState
                        end try
                    end if
                end tell
                return ""
                """) ?? ""
            let parts = raw.components(separatedBy: "\t")
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            let playing = (parts.count >= 4) ? parts[3].lowercased().contains("playing") : isPlaying()
            return MediaTrackInfo(
                title: parts[0],
                artist: parts[1],
                album: parts[2],
                isPlaying: playing,
                playerName: definition.displayName,
                bundleID: definition.bundleID
            )

        case .vlc:
            let raw = Self.runAppleScript("""
                tell application id "org.videolan.vlc"
                    if it is running then
                        try
                            return (name of current item) & "\\t" & (playing as string)
                        end try
                    end if
                end tell
                return ""
                """) ?? ""
            let parts = raw.components(separatedBy: "\t")
            guard let first = parts.first, !first.isEmpty else { return nil }
            let playing = parts.count >= 2 ? (parts[1].lowercased() == "true") : isPlaying()
            return MediaTrackInfo(
                title: first,
                artist: "VLC",
                isPlaying: playing,
                playerName: definition.displayName,
                bundleID: definition.bundleID
            )

        case .vox:
            let raw = Self.runAppleScript("""
                tell application id "com.coppertino.Vox"
                    if it is running then
                        try
                            return (track) & "\\t" & (artist) & "\\t" & (album)
                        end try
                    end if
                end tell
                return ""
                """) ?? ""
            let parts = raw.components(separatedBy: "\t")
            guard let first = parts.first, !first.isEmpty else { return nil }
            return MediaTrackInfo(
                title: first,
                artist: parts.count > 1 ? parts[1] : nil,
                album: parts.count > 2 ? parts[2] : nil,
                isPlaying: isPlaying(),
                playerName: definition.displayName,
                bundleID: definition.bundleID
            )

        case .systemMediaRemote:
            return MediaTrackInfo(
                title: definition.displayName,
                artist: isPlaying() ? "Playing" : "Paused",
                isPlaying: isPlaying(),
                playerName: definition.displayName,
                bundleID: definition.bundleID
            )
        }
    }

    func activate() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: definition.bundleID).first {
            app.activate()
        }
        _ = Self.runAppleScript("""
            tell application id "\(definition.bundleID)"
                reopen
                activate
            end tell
            """)
    }

    func isFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == definition.bundleID
    }

    private static var scriptCache: [String: NSAppleScript] = [:]

    private static func runAppleScript(_ source: String) -> String? {
        let script: NSAppleScript
        if let cached = scriptCache[source] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: source) else { return nil }
            scriptCache[source] = compiled
            script = compiled
        }
        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        if errorDict != nil { return nil }
        if let str = descriptor.stringValue { return str }
        if descriptor.descriptorType == typeTrue { return "true" }
        if descriptor.descriptorType == typeFalse { return "false" }
        return nil
    }
}

// MARK: - macOS System MediaRemote Private Framework Dynamic Bridge

/// Dynamically loads `MediaRemote.framework` (`MRMediaRemoteSendCommand`) as a universal fallback
/// for non-AppleScriptable native apps (e.g., IINA, TIDAL, Electron players, Firefox, Telegram)
/// without ever invoking `rcd` to launch Apple Music when Apple Music is not running.
@MainActor
final class SystemMediaRemoteBridge {
    static let shared = SystemMediaRemoteBridge()

    enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias SendCommandFunc = @convention(c) (UInt32, UnsafeRawPointer?) -> Bool
    private let sendCommandPtr: SendCommandFunc?

    private init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
           let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            self.sendCommandPtr = unsafeBitCast(sym, to: SendCommandFunc.self)
        } else {
            self.sendCommandPtr = nil
        }
    }

    @discardableResult
    func sendCommand(_ command: Command) -> Bool {
        guard let fn = sendCommandPtr else { return false }
        return fn(command.rawValue, nil)
    }

    func isPlaying(bundleID: String) -> Bool {
        false
    }
}
