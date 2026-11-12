// FineTune/MediaControl/Adapters/BrowserTabAdapter.swift
import AppKit
import Foundation
import os

nonisolated enum BrowserKind: String, Sendable {
    case chromium
    case safari
    case arc
}

nonisolated struct SupportedBrowser: Sendable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let displayName: String
    let kind: BrowserKind

    static let all: [SupportedBrowser] = [
        SupportedBrowser(bundleID: "com.apple.Safari", displayName: "Safari", kind: .safari),
        SupportedBrowser(bundleID: "com.apple.SafariTechnologyPreview", displayName: "Safari Technology Preview", kind: .safari),
        SupportedBrowser(bundleID: "com.kagi.kagimacOS", displayName: "Orion", kind: .safari),
        SupportedBrowser(bundleID: "com.google.Chrome", displayName: "Google Chrome", kind: .chromium),
        SupportedBrowser(bundleID: "com.google.Chrome.canary", displayName: "Chrome Canary", kind: .chromium),
        SupportedBrowser(bundleID: "com.brave.Browser", displayName: "Brave", kind: .chromium),
        SupportedBrowser(bundleID: "company.thebrowser.Browser", displayName: "Arc", kind: .arc),
        SupportedBrowser(bundleID: "com.microsoft.edgemac", displayName: "Microsoft Edge", kind: .chromium),
        SupportedBrowser(bundleID: "com.vivaldi.Vivaldi", displayName: "Vivaldi", kind: .chromium),
        SupportedBrowser(bundleID: "org.chromium.Chromium", displayName: "Chromium", kind: .chromium),
        SupportedBrowser(bundleID: "com.operasoftware.Opera", displayName: "Opera", kind: .chromium)
    ]
}

@MainActor
final class BrowserTabAdapter: MediaTargetAdapting {
    private static let logger = Logger(subsystem: "com.finetuneapp.FineTune", category: "BrowserTabAdapter")

    let id: String
    let browser: SupportedBrowser
    let windowIndex: Int
    let tabIndex: Int
    let tabURL: String
    let tabTitle: String
    let isActiveInWindow: Bool
    let strategy: BSMediaStrategy
    private let isAudibleProvider: @MainActor (String) -> Bool

    var displayName: String {
        strategy.displayName
    }

    var title: String {
        let cleaned = tabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? strategy.displayName : cleaned
    }

    var subtitle: String {
        "\(strategy.displayName) · \(browser.displayName)"
    }

    var bundleID: String {
        browser.bundleID
    }

    var isNativeApp: Bool {
        false
    }

    var supportsFavorite: Bool {
        !strategy.favoriteScript.isEmpty
    }

    var icon: NSImage? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first {
            return app.icon
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: browser.displayName)
    }

    init(
        browser: SupportedBrowser,
        windowIndex: Int,
        tabIndex: Int,
        tabURL: String,
        tabTitle: String,
        isActiveInWindow: Bool,
        strategy: BSMediaStrategy,
        isAudibleProvider: @escaping @MainActor (String) -> Bool = { _ in false }
    ) {
        self.browser = browser
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.tabURL = tabURL
        self.tabTitle = tabTitle
        self.isActiveInWindow = isActiveInWindow
        self.strategy = strategy
        self.isAudibleProvider = isAudibleProvider
        self.id = "tab:\(browser.bundleID):w\(windowIndex):t\(tabIndex)"
    }

    // MARK: - MediaTargetAdapting

    func isPlaying() -> Bool {
        let script = combinedScript(
            primary: strategy.isPlayingScript,
            fallback: BSMediaStrategy.universalHTML5.isPlayingScript
        )
        if !script.isEmpty,
           let rawOut = executeJSRead(script)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !rawOut.isEmpty {
            return rawOut == "true" || rawOut == "1"
        }
        // Fallback when "Allow JavaScript from Apple Events" is disabled in Chromium:
        // use FineTune's real-time CoreAudio process tap!
        return isAudibleProvider(browser.bundleID)
    }

    func setPlaying(_ shouldPlay: Bool) {
        if !shouldPlay {
            pause()
            return
        }
        let checkScript = combinedScript(
            primary: strategy.isPlayingScript,
            fallback: BSMediaStrategy.universalHTML5.isPlayingScript
        )
        let actionScript = combinedActionScript(
            primary: strategy.toggleScript,
            fallback: BSMediaStrategy.universalHTML5.toggleScript
        )
        let idempotentPlayJS = """
        (function() {
            var alreadyPlaying = false;
            try { alreadyPlaying = Boolean(\(checkScript.isEmpty ? "false" : checkScript)); } catch(e) {}
            if (!alreadyPlaying) {
                \(actionScript);
            }
            return true;
        })()
        """
        executeJSAction(idempotentPlayJS)
    }

    func toggle() {
        let script = combinedActionScript(
            primary: strategy.toggleScript,
            fallback: BSMediaStrategy.universalHTML5.toggleScript
        )
        executeJSAction(script)
    }

    func pause() {
        let script = combinedActionScript(
            primary: strategy.pauseScript,
            fallback: BSMediaStrategy.universalHTML5.pauseScript
        )
        executeJSAction(script)
    }

    func next() {
        let script = combinedActionScript(
            primary: strategy.nextScript,
            fallback: BSMediaStrategy.universalHTML5.nextScript
        )
        executeJSAction(script)
    }

    func previous() {
        let script = combinedActionScript(
            primary: strategy.previousScript,
            fallback: BSMediaStrategy.universalHTML5.previousScript
        )
        executeJSAction(script)
    }

    func favorite() {
        let script = combinedActionScript(
            primary: strategy.favoriteScript,
            fallback: BSMediaStrategy.universalHTML5.favoriteScript
        )
        guard !script.isEmpty else { return }
        executeJSAction(script)
    }

    func fetchTrackInfo() -> MediaTrackInfo? {
        let primary = strategy.trackInfoScript
        let fallback = BSMediaStrategy.universalHTML5.trackInfoScript
        let jsonWrapper = """
        (function() {
            var info = null;
            try { info = \(primary.isEmpty ? "null" : primary); } catch(e) {}
            if (!info || (!info.track && !info.artist)) {
                try { info = \(fallback); } catch(e) {}
            }
            if (!info) return "";
            try { return JSON.stringify(info); } catch(e) { return ""; }
        })()
        """
        if let jsonStr = executeJSRead(jsonWrapper),
           let data = jsonStr.data(using: .utf8),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           var parsed = MediaTrackInfo(jsDictionary: dict, playerName: subtitle, bundleID: bundleID) {
            parsed.isPlaying = isPlaying()
            return parsed
        }
        return MediaTrackInfo(
            title: title,
            artist: subtitle,
            isPlaying: isPlaying(),
            playerName: subtitle,
            bundleID: bundleID
        )
    }

    func activate() {
        let appleScriptSource: String
        switch browser.kind {
        case .chromium:
            appleScriptSource = """
            tell application id "\(browser.bundleID)"
                activate
                try
                    set active tab index of window \(windowIndex) to \(tabIndex)
                    set index of window \(windowIndex) to 1
                end try
            end tell
            """
        case .arc:
            appleScriptSource = """
            tell application id "\(browser.bundleID)"
                activate
                try
                    tell window \(windowIndex)
                        tell tab \(tabIndex) to select
                    end tell
                end try
            end tell
            """
        case .safari:
            appleScriptSource = """
            tell application id "\(browser.bundleID)"
                activate
                try
                    set current tab of window \(windowIndex) to tab \(tabIndex) of window \(windowIndex)
                    set index of window \(windowIndex) to 1
                end try
            end tell
            """
        }
        _ = Self.runAppleScript(appleScriptSource)
    }

    func isFrontmost() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == browser.bundleID else {
            return false
        }
        return windowIndex == 1 && isActiveInWindow
    }

    // MARK: - JavaScript Execution with BeardedSpice `javascript:` URL Fallback

    private func combinedScript(primary: String, fallback: String) -> String {
        if primary.isEmpty { return fallback }
        if strategy.id == BSMediaStrategy.universalHTML5.id { return primary }
        return """
        (function() {
            try {
                var r = \(primary);
                if (r !== null && r !== undefined && r !== false) return r;
            } catch (e) {}
            try { return \(fallback); } catch (e) { return false; }
        })()
        """
    }

    private func combinedActionScript(primary: String, fallback: String) -> String {
        if primary.isEmpty { return fallback }
        if strategy.id == BSMediaStrategy.universalHTML5.id { return primary }
        return """
        (function() {
            try { \(primary); return true; } catch (e) {
                try { \(fallback); return true; } catch (e2) { return false; }
            }
        })()
        """
    }

    func executeJSRead(_ js: String) -> String? {
        Self.executeJSRead(
            js,
            in: browser,
            windowIndex: windowIndex,
            tabIndex: tabIndex
        )
    }

    func executeJSAction(_ js: String) {
        Self.executeJSAction(
            js,
            in: browser,
            windowIndex: windowIndex,
            tabIndex: tabIndex
        )
    }

    static func executeJSRead(
        _ js: String,
        in browser: SupportedBrowser,
        windowIndex: Int,
        tabIndex: Int
    ) -> String? {
        let escapedJS = escapeForAppleScriptString(js)
        let directScript: String
        switch browser.kind {
        case .chromium, .arc:
            directScript = """
            tell application id "\(browser.bundleID)"
                tell window \(windowIndex)
                    execute tab \(tabIndex) javascript "\(escapedJS)"
                end tell
            end tell
            """
        case .safari:
            directScript = """
            tell application id "\(browser.bundleID)"
                do JavaScript "\(escapedJS)" in tab \(tabIndex) of window \(windowIndex)
            end tell
            """
        }

        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: directScript) {
            let descriptor = appleScript.executeAndReturnError(&errorDict)
            if errorDict == nil {
                return descriptorToString(descriptor)
            }
        }
        return nil
    }

    static func executeJSAction(
        _ js: String,
        in browser: SupportedBrowser,
        windowIndex: Int,
        tabIndex: Int
    ) {
        if executeJSRead(js, in: browser, windowIndex: windowIndex, tabIndex: tabIndex) != nil {
            return
        }

        // BeardedSpice ChromeTabAdapter fallback when "Allow JavaScript from Apple Events" is disabled:
        // assigns `javascript:(function(){ ... })()` to `URL of tab`, which executes in page context!
        if browser.kind == .chromium || browser.kind == .arc {
            let oneLineJS = js
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            let jsURL = "javascript:(function(){try{\(oneLineJS);}catch(e){}})();"
            let escapedURL = escapeForAppleScriptString(jsURL)
            let urlFallbackScript = """
            tell application id "\(browser.bundleID)"
                set URL of tab \(tabIndex) of window \(windowIndex) to "\(escapedURL)"
            end tell
            """
            _ = runAppleScript(urlFallbackScript)
        }
    }

    // MARK: - Fast Tab Discovery Across Running Browsers

    static func discoverMediaTabs(
        registry: MediaStrategyRegistry,
        disabledStrategyIDs: Set<String>,
        universalFallbackEnabled: Bool,
        audibleBundleIDs: Set<String>,
        isAudibleProvider: @escaping @MainActor (String) -> Bool = { _ in false }
    ) -> [BrowserTabAdapter] {
        var results: [BrowserTabAdapter] = []
        let runningByBundleID = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app -> (String, NSRunningApplication)? in
                guard let bid = app.bundleIdentifier else { return nil }
                return (bid, app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for browser in SupportedBrowser.all {
            guard runningByBundleID[browser.bundleID] != nil else { continue }
            let rawTabs = listTabs(for: browser)
            let isBrowserAudible = audibleBundleIDs.contains(browser.bundleID)

            for raw in rawTabs {
                let allowUniversal = universalFallbackEnabled && isBrowserAudible
                let evalClosure: ((String) -> String?)? = allowUniversal
                    ? { js in executeJSRead(js, in: browser, windowIndex: raw.windowIndex, tabIndex: raw.tabIndex) ?? (raw.isActive ? "true" : nil) }
                    : nil

                if let matched = registry.matchingStrategy(
                    url: raw.url,
                    title: raw.title,
                    disabledIDs: disabledStrategyIDs,
                    universalFallbackEnabled: allowUniversal,
                    evaluateJS: evalClosure
                ) {
                    results.append(
                        BrowserTabAdapter(
                            browser: browser,
                            windowIndex: raw.windowIndex,
                            tabIndex: raw.tabIndex,
                            tabURL: raw.url,
                            tabTitle: raw.title,
                            isActiveInWindow: raw.isActive,
                            strategy: matched,
                            isAudibleProvider: isAudibleProvider
                        )
                    )
                }
            }
        }
        return results
    }

    private struct RawBrowserTab {
        let windowIndex: Int
        let tabIndex: Int
        let url: String
        let title: String
        let isActive: Bool
    }

    private static func listTabs(for browser: SupportedBrowser) -> [RawBrowserTab] {
        let scriptSource: String
        switch browser.kind {
        case .chromium:
            scriptSource = """
            set outputLines to ""
            tell application id "\(browser.bundleID)"
                set winCount to count of windows
                repeat with w from 1 to winCount
                    try
                        set activeIdx to active tab index of window w
                        set tabCount to count of tabs of window w
                        repeat with t from 1 to tabCount
                            try
                                set u to URL of tab t of window w
                                set ti to title of tab t of window w
                                set isAct to (t is equal to activeIdx)
                                set outputLines to outputLines & w & "\\t" & t & "\\t" & isAct & "\\t" & u & "\\t" & ti & "\\n"
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            return outputLines
            """
        case .arc:
            scriptSource = """
            set outputLines to ""
            tell application id "\(browser.bundleID)"
                set winCount to count of windows
                repeat with w from 1 to winCount
                    try
                        set tabCount to count of tabs of window w
                        repeat with t from 1 to tabCount
                            try
                                set u to URL of tab t of window w
                                set ti to title of tab t of window w
                                set outputLines to outputLines & w & "\\t" & t & "\\tfalse\\t" & u & "\\t" & ti & "\\n"
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            return outputLines
            """
        case .safari:
            scriptSource = """
            set outputLines to ""
            tell application id "\(browser.bundleID)"
                set winCount to count of windows
                repeat with w from 1 to winCount
                    try
                        set curTab to current tab of window w
                        set tabCount to count of tabs of window w
                        repeat with t from 1 to tabCount
                            try
                                set theTab to tab t of window w
                                set u to URL of theTab
                                set ti to name of theTab
                                set isAct to (theTab is equal to curTab)
                                set outputLines to outputLines & w & "\\t" & t & "\\t" & isAct & "\\t" & u & "\\t" & ti & "\\n"
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            return outputLines
            """
        }

        guard let rawOutput = runAppleScript(scriptSource), !rawOutput.isEmpty else {
            return []
        }

        var tabs: [RawBrowserTab] = []
        for line in rawOutput.components(separatedBy: "\n") where !line.isEmpty {
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 5,
                  let w = Int(fields[0]),
                  let t = Int(fields[1])
            else { continue }
            let isAct = fields[2].lowercased() == "true"
            let url = fields[3]
            let title = fields.dropFirst(4).joined(separator: "\t")
            tabs.append(RawBrowserTab(windowIndex: w, tabIndex: t, url: url, title: title, isActive: isAct))
        }
        return tabs
    }

    // MARK: - AppleScript Utilities

    private static func escapeForAppleScriptString(_ str: String) -> String {
        str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static var scriptCache: [String: NSAppleScript] = [:]

    @discardableResult
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
        if errorDict != nil {
            return nil
        }
        return descriptorToString(descriptor)
    }

    private static func descriptorToString(_ descriptor: NSAppleEventDescriptor) -> String? {
        if let str = descriptor.stringValue {
            return str
        }
        if descriptor.descriptorType == typeTrue {
            return "true"
        }
        if descriptor.descriptorType == typeFalse {
            return "false"
        }
        if descriptor.descriptorType == typeSInt32 {
            return String(descriptor.int32Value)
        }
        return nil
    }
}
