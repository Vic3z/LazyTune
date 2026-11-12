// FineTune/Shortcuts/ShortcutAction.swift
import Foundation

/// Actions that can be bound to a user-recordable global keyboard shortcut.
///
/// Adding a new action here is a single enum case + a corresponding arm
/// in `ShortcutsRegistry.dispatch(_:)`. The `rawValue` is the persistence key
/// in `AppSettings.customShortcuts` and must be stable across releases.
enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case togglePopup
    case targetAppVolumeUp = "frontmostAppVolumeUp"
    case targetAppVolumeDown = "frontmostAppVolumeDown"
    case targetAppMuteToggle = "frontmostAppMuteToggle"
    case mediaPlayPause = "mediaPlayPause"
    case mediaNextTrack = "mediaNextTrack"
    case mediaPreviousTrack = "mediaPreviousTrack"
    case mediaSetActiveTab = "mediaSetActiveTab"
    case mediaFavorite = "mediaFavorite"
    case mediaShowTrackInfo = "mediaShowTrackInfo"
    case mediaActivatePlayingTab = "mediaActivatePlayingTab"
    case mediaSwitchPlayerNext = "mediaSwitchPlayerNext"
    case mediaSwitchPlayerPrevious = "mediaSwitchPlayerPrevious"

    var displayName: String {
        switch self {
        case .togglePopup: "Toggle FineTune Popup"
        case .targetAppVolumeUp: "App Volume Up"
        case .targetAppVolumeDown: "App Volume Down"
        case .targetAppMuteToggle: "App Mute"
        case .mediaPlayPause: "Media Play / Pause"
        case .mediaNextTrack: "Media Next Track"
        case .mediaPreviousTrack: "Media Previous Track"
        case .mediaSetActiveTab: "Pin Active Browser Tab / Player"
        case .mediaFavorite: "Favorite / Like Current Track"
        case .mediaShowTrackInfo: "Show Track Info HUD"
        case .mediaActivatePlayingTab: "Bring Active Player to Front"
        case .mediaSwitchPlayerNext: "Switch to Next Media Player"
        case .mediaSwitchPlayerPrevious: "Switch to Previous Media Player"
        }
    }

    /// Whether holding the chord should keep firing the action while held,
    /// matching macOS media-key auto-repeat. Toggles must not repeat
    /// (would flip-flop state every interval).
    var supportsRepeat: Bool {
        switch self {
        case .targetAppVolumeUp, .targetAppVolumeDown: true
        case .togglePopup, .targetAppMuteToggle,
             .mediaPlayPause, .mediaNextTrack, .mediaPreviousTrack,
             .mediaSetActiveTab, .mediaFavorite, .mediaShowTrackInfo,
             .mediaActivatePlayingTab, .mediaSwitchPlayerNext, .mediaSwitchPlayerPrevious:
            false
        }
    }
}
