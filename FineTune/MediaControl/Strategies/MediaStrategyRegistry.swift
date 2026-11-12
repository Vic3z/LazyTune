// FineTune/MediaControl/Strategies/MediaStrategyRegistry.swift
import Foundation
import os

@MainActor
@Observable
final class MediaStrategyRegistry {
    private let logger = Logger(subsystem: "com.finetuneapp.FineTune", category: "MediaStrategyRegistry")

    private(set) var strategies: [BSMediaStrategy] = []
    private let customStrategiesDir: URL

    init(customDirectory: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FineTune", isDirectory: true)
            .appendingPathComponent("CustomStrategies", isDirectory: true)
        self.customStrategiesDir = customDirectory ?? appSupport
        reloadStrategies()
    }

    func reloadStrategies() {
        var loadedByID: [String: BSMediaStrategy] = [:]

        // 1. Load pre-compiled MediaStrategies.json (zero JavaScriptCore memory overhead)
        if let jsonURL = Self.bundledStrategiesJSONURL(),
           let data = try? Data(contentsOf: jsonURL),
           let items = try? JSONDecoder().decode([SerializedBSMediaStrategy].self, from: data) {
            for item in items {
                if let strategy = BSMediaStrategy(serialized: item, isCustom: false) {
                    loadedByID[strategy.id] = strategy
                }
            }
        }

        // 2. Load user custom strategies (override bundled if same ID)
        try? FileManager.default.createDirectory(at: customStrategiesDir, withIntermediateDirectories: true)
        if let customFiles = try? FileManager.default.contentsOfDirectory(
            at: customStrategiesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in customFiles {
                let ext = fileURL.pathExtension.lowercased()
                guard ext == "json" || ext == "bsstrategy" else { continue }
                if let strategy = BSMediaStrategy(fileURL: fileURL, isCustom: true) {
                    loadedByID[strategy.id] = strategy
                }
            }
        }

        self.strategies = loadedByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        logger.info("Loaded \(self.strategies.count) BeardedSpice media strategies")
    }

    /// Finds the best matching strategy for a browser tab.
    func matchingStrategy(
        url: String,
        title: String,
        disabledIDs: Set<String>,
        universalFallbackEnabled: Bool,
        evaluateJS: ((String) -> String?)? = nil
    ) -> BSMediaStrategy? {
        guard !url.isEmpty,
              !url.hasPrefix("chrome://"),
              !url.hasPrefix("about:"),
              !url.hasPrefix("safari-resource:"),
              !url.hasPrefix("favorites://")
        else { return nil }

        // 1. Fast pass: predicateOnTab strategies (no JS execution in browser needed)
        for strategy in strategies where !disabledIDs.contains(strategy.id) {
            if case .predicateOnTab = strategy.acceptMethod {
                if strategy.accepts(url: url, title: title) {
                    return strategy
                }
            }
        }

        // 2. Script-based strategies
        if let evaluateJS {
            for strategy in strategies where !disabledIDs.contains(strategy.id) {
                if case .script = strategy.acceptMethod {
                    if strategy.accepts(url: url, title: title, evaluateJS: evaluateJS) {
                        return strategy
                    }
                }
            }
        }

        // 3. Universal HTML5 <video>/<audio> fallback
        if universalFallbackEnabled, let evaluateJS {
            if BSMediaStrategy.universalHTML5.accepts(url: url, title: title, evaluateJS: evaluateJS) {
                return BSMediaStrategy.universalHTML5
            }
        }

        return nil
    }

    /// Imports a custom `.js` or `.bsstrategy` file into CustomStrategies.
    @discardableResult
    func importCustomStrategy(from sourceURL: URL) -> BSMediaStrategy? {
        guard let strategy = BSMediaStrategy(fileURL: sourceURL, isCustom: true) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: customStrategiesDir, withIntermediateDirectories: true)
        let destURL = customStrategiesDir.appendingPathComponent(strategy.fileName)
        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            reloadStrategies()
            return strategy
        } catch {
            logger.error("Failed to copy custom strategy: \(error.localizedDescription)")
            return nil
        }
    }

    private static func bundledStrategiesJSONURL() -> URL? {
        if let resURL = Bundle.main.resourceURL {
            let bundled = resURL.appendingPathComponent("MediaStrategies.json")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        let repoRelative = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("MediaStrategies.json")
        if FileManager.default.fileExists(atPath: repoRelative.path) {
            return repoRelative
        }
        return nil
    }
}
