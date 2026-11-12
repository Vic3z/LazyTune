// FineTune/MediaControl/Adapters/MediaTargetAdapter.swift
import AppKit
import Foundation

/// Unified interface representing any controllable media target:
/// either a specific browser tab (controlled via Universal Media JS strategy + Universal HTML5 fallback)
/// or a native desktop media application (Spotify, VLC, IINA, VOX, Tidal, Apple Music, etc.).
@MainActor
protocol MediaTargetAdapting: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var title: String { get }
    var subtitle: String { get }
    var bundleID: String { get }
    var isNativeApp: Bool { get }
    var supportsFavorite: Bool { get }
    var icon: NSImage? { get }

    func isPlaying() -> Bool
    func setPlaying(_ shouldPlay: Bool)
    func toggle()
    func pause()
    func next()
    func previous()
    func favorite()
    func fetchTrackInfo() -> MediaTrackInfo?
    func activate()
    func isFrontmost() -> Bool
}
