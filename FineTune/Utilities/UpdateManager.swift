// FineTune/Utilities/UpdateManager.swift
import Foundation
import Combine

/// Lightweight stub replacing Sparkle automatic update checks in LazyTune.
/// Automatic background update checks are disabled to save memory and network overhead.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    @Published var canCheckForUpdates = false
    var automaticallyChecksForUpdates: Bool = false
    var automaticallyDownloadsUpdates: Bool = false
    var lastUpdateCheckDate: Date? { nil }

    override init() {
        super.init()
    }

    func checkForUpdates() {}
}
