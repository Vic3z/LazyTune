// FineTune/MediaControl/Strategies/BSMediaStrategy.swift
import Foundation
import os

nonisolated struct SerializedBSMediaStrategy: Codable, Sendable {
    let id: String
    let fileName: String
    let displayName: String
    let version: Int
    let acceptType: String
    let acceptFormat: String?
    let acceptArgs: [String]?
    let acceptScript: String?
    let isPlayingScript: String
    let toggleScript: String
    let previousScript: String
    let nextScript: String
    let pauseScript: String
    let favoriteScript: String
    let trackInfoScript: String
}

/// Swift 6 port of universal `BSMediaStrategy` (`BSMediaStrategy.h/.m`),
/// loaded from pre-compiled JSON (`MediaStrategies.json`) with zero JavaScriptCore heap overhead.
nonisolated final class BSMediaStrategy: Identifiable, Sendable {
    enum AcceptMethod: Sendable {
        case predicateOnTab(format: String, args: [String])
        case script(js: String)
        case universalHTML5
    }

    let id: String
    let fileName: String
    let displayName: String
    let version: Int
    let isCustom: Bool
    let acceptMethod: AcceptMethod

    let isPlayingScript: String
    let toggleScript: String
    let previousScript: String
    let nextScript: String
    let pauseScript: String
    let favoriteScript: String
    let trackInfoScript: String

    init(
        id: String,
        fileName: String,
        displayName: String,
        version: Int,
        isCustom: Bool = false,
        acceptMethod: AcceptMethod,
        isPlayingScript: String,
        toggleScript: String,
        previousScript: String,
        nextScript: String,
        pauseScript: String,
        favoriteScript: String,
        trackInfoScript: String
    ) {
        self.id = id
        self.fileName = fileName
        self.displayName = displayName
        self.version = version
        self.isCustom = isCustom
        self.acceptMethod = acceptMethod
        self.isPlayingScript = isPlayingScript
        self.toggleScript = toggleScript
        self.previousScript = previousScript
        self.nextScript = nextScript
        self.pauseScript = pauseScript
        self.favoriteScript = favoriteScript
        self.trackInfoScript = trackInfoScript
    }

    convenience init?(serialized: SerializedBSMediaStrategy, isCustom: Bool = false) {
        let acceptMethod: AcceptMethod
        if serialized.acceptType == "predicateOnTab", let fmt = serialized.acceptFormat {
            acceptMethod = .predicateOnTab(format: fmt, args: serialized.acceptArgs ?? ["URL"])
        } else if serialized.acceptType == "script", let script = serialized.acceptScript, !script.isEmpty {
            acceptMethod = .script(js: script)
        } else {
            return nil
        }

        self.init(
            id: serialized.id,
            fileName: serialized.fileName,
            displayName: serialized.displayName,
            version: serialized.version,
            isCustom: isCustom,
            acceptMethod: acceptMethod,
            isPlayingScript: serialized.isPlayingScript,
            toggleScript: serialized.toggleScript,
            previousScript: serialized.previousScript,
            nextScript: serialized.nextScript,
            pauseScript: serialized.pauseScript,
            favoriteScript: serialized.favoriteScript,
            trackInfoScript: serialized.trackInfoScript
        )
    }

    convenience init?(fileURL: URL, isCustom: Bool = false) {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SerializedBSMediaStrategy.self, from: data)
        else {
            return nil
        }
        self.init(serialized: decoded, isCustom: isCustom)
    }

    // MARK: - Matching

    /// Evaluates whether a browser tab with `url` and `title` matches this strategy.
    func accepts(url: String, title: String, evaluateJS: ((String) -> String?)? = nil) -> Bool {
        switch acceptMethod {
        case .predicateOnTab(let format, let args):
            return Self.evaluateTabPredicate(format: format, args: args, url: url, title: title)
        case .script(let js):
            guard let evaluateJS, let result = evaluateJS(js) else { return false }
            let lower = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lower == "true" || lower == "1"
        case .universalHTML5:
            guard let evaluateJS, let result = evaluateJS(Self.universalAcceptScript) else { return false }
            let lower = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lower == "true" || lower == "1"
        }
    }

    /// Safely evaluates universal `NSPredicate` format strings against `{ "URL": url, "title": title }`.
    static func evaluateTabPredicate(format: String, args: [String], url: String, title: String) -> Bool {
        // Normalize key names used across Universal Media strategies ("URL" vs "url", "title")
        let targetObj: NSDictionary = [
            "URL": url,
            "url": url,
            "title": title
        ]
        var normalizedFormat = format
        var predicateArgs: [Any] = []
        for arg in args {
            if arg.caseInsensitiveCompare("url") == .orderedSame {
                predicateArgs.append("URL")
            } else if arg.caseInsensitiveCompare("title") == .orderedSame {
                predicateArgs.append("title")
            } else {
                predicateArgs.append(arg)
            }
        }
        // Fix common Universal Media predicate quirk where `%@ LIKE[c]` was written instead of `%K LIKE[c]` for keypath args
        for (idx, arg) in args.enumerated() where idx > 0 && (arg.caseInsensitiveCompare("url") == .orderedSame || arg.caseInsensitiveCompare("title") == .orderedSame) {
            if let range = normalizedFormat.range(of: "%@ LIKE") {
                normalizedFormat.replaceSubrange(range, with: "%K LIKE")
            }
        }

        return ObjCExceptionCatcher.evaluatePredicate(
            format: normalizedFormat,
            argumentArray: predicateArgs,
            object: targetObj
        )
    }

    // MARK: - Universal HTML5 & Modern Web Player Strategy

    private static let universalAcceptScript = """
    (function() {
        try {
            var media = Array.from(document.querySelectorAll('video, audio'));
            return media.some(function(m) {
                return (m.readyState > 0 && (m.duration > 0 || !m.paused || m.currentTime > 0));
            });
        } catch (e) { return false; }
    })()
    """

    /// Built-in Universal HTML5 + MediaSession strategy that works on ANY website with `<video>` or `<audio>`
    /// (including modern YouTube, YouTube Music, SoundCloud, Spotify Web, Twitch, Bandcamp, Apple Music Web, etc.).
    static let universalHTML5 = BSMediaStrategy(
        id: "UniversalHTML5Media",
        fileName: "UniversalHTML5Media.js",
        displayName: "Universal Web Media (HTML5)",
        version: 1,
        isCustom: false,
        acceptMethod: .universalHTML5,
        isPlayingScript: """
        (function() {
            try {
                if (navigator.mediaSession && navigator.mediaSession.playbackState === 'playing') return true;
                var media = Array.from(document.querySelectorAll('video, audio'));
                return media.some(function(m) { return !m.paused && !m.ended && m.readyState > 1; });
            } catch (e) { return false; }
        })()
        """,
        toggleScript: """
        (function() {
            try {
                // Site-specific fast paths for modern DOMs
                var host = location.hostname;
                if (host.includes('music.youtube.com')) {
                    var ytmBtn = document.querySelector('#play-pause-button, tp-yt-paper-icon-button.play-pause-button');
                    if (ytmBtn) { ytmBtn.click(); return true; }
                }
                if (host.includes('youtube.com')) {
                    var ytPlayer = document.querySelector('#movie_player');
                    if (ytPlayer && typeof ytPlayer.getPlayerState === 'function') {
                        if (ytPlayer.getPlayerState() === 1) ytPlayer.pauseVideo(); else ytPlayer.playVideo();
                        return true;
                    }
                    var ytBtn = document.querySelector('.ytp-play-button');
                    if (ytBtn) { ytBtn.click(); return true; }
                }
                if (host.includes('open.spotify.com')) {
                    var spBtn = document.querySelector('[data-testid="control-button-playpause"]');
                    if (spBtn) { spBtn.click(); return true; }
                }
                if (host.includes('soundcloud.com')) {
                    var scBtn = document.querySelector('.playControl, .playControls__play');
                    if (scBtn) { scBtn.click(); return true; }
                }
                var media = Array.from(document.querySelectorAll('video, audio'));
                var playing = media.find(function(m) { return !m.paused && !m.ended; });
                if (playing) { playing.pause(); return false; }
                var candidate = media.find(function(m) { return m.currentTime > 0 || m.readyState > 1; }) || media[0];
                if (candidate) { candidate.play(); return true; }
                return false;
            } catch (e) { return false; }
        })()
        """,
        previousScript: """
        (function() {
            try {
                var host = location.hostname;
                if (host.includes('music.youtube.com')) {
                    var b = document.querySelector('.previous-button, tp-yt-paper-icon-button.previous-button');
                    if (b) { b.click(); return true; }
                }
                if (host.includes('youtube.com')) {
                    var p = document.querySelector('#movie_player');
                    if (p && typeof p.previousVideo === 'function') { p.previousVideo(); return true; }
                    var prevBtn = document.querySelector('.ytp-prev-button');
                    if (prevBtn && prevBtn.style.display !== 'none') { prevBtn.click(); return true; }
                }
                if (host.includes('open.spotify.com')) {
                    var sb = document.querySelector('[data-testid="control-button-skip-back"]');
                    if (sb) { sb.click(); return true; }
                }
                if (host.includes('soundcloud.com')) {
                    var scb = document.querySelector('.skipControl__previous');
                    if (scb) { scb.click(); return true; }
                }
                var genericPrev = document.querySelector('[aria-label*="Previous" i], [title*="Previous" i], [class*="prev" i]:not(div)');
                if (genericPrev && typeof genericPrev.click === 'function') { genericPrev.click(); return true; }
                var media = document.querySelector('video, audio');
                if (media) { media.currentTime = Math.max(0, media.currentTime - 10); return true; }
                return false;
            } catch (e) { return false; }
        })()
        """,
        nextScript: """
        (function() {
            try {
                var host = location.hostname;
                if (host.includes('music.youtube.com')) {
                    var b = document.querySelector('.next-button, tp-yt-paper-icon-button.next-button');
                    if (b) { b.click(); return true; }
                }
                if (host.includes('youtube.com')) {
                    var p = document.querySelector('#movie_player');
                    if (p && typeof p.nextVideo === 'function') { p.nextVideo(); return true; }
                    var nextBtn = document.querySelector('.ytp-next-button');
                    if (nextBtn) { nextBtn.click(); return true; }
                }
                if (host.includes('open.spotify.com')) {
                    var sb = document.querySelector('[data-testid="control-button-skip-forward"]');
                    if (sb) { sb.click(); return true; }
                }
                if (host.includes('soundcloud.com')) {
                    var scb = document.querySelector('.skipControl__next');
                    if (scb) { scb.click(); return true; }
                }
                var genericNext = document.querySelector('[aria-label*="Next" i], [title*="Next" i], [class*="next" i]:not(div)');
                if (genericNext && typeof genericNext.click === 'function') { genericNext.click(); return true; }
                var media = document.querySelector('video, audio');
                if (media) { media.currentTime = Math.min(media.duration || media.currentTime + 10, media.currentTime + 10); return true; }
                return false;
            } catch (e) { return false; }
        })()
        """,
        pauseScript: """
        (function() {
            try {
                var media = Array.from(document.querySelectorAll('video, audio'));
                media.forEach(function(m) { if (!m.paused) m.pause(); });
                return true;
            } catch (e) { return false; }
        })()
        """,
        favoriteScript: """
        (function() {
            try {
                var host = location.hostname;
                if (host.includes('youtube.com')) {
                    var likeBtn = document.querySelector('like-button-view-model button, #segmented-like-button button, ytd-toggle-button-renderer button');
                    if (likeBtn) { likeBtn.click(); return true; }
                }
                if (host.includes('open.spotify.com')) {
                    var spFav = document.querySelector('[data-testid="add-button"], [aria-label*="Save to Your Library" i]');
                    if (spFav) { spFav.click(); return true; }
                }
                if (host.includes('soundcloud.com')) {
                    var scFav = document.querySelector('.playbackSoundBadge__like, .sc-button-like');
                    if (scFav) { scFav.click(); return true; }
                }
                return false;
            } catch (e) { return false; }
        })()
        """,
        trackInfoScript: """
        (function() {
            try {
                var meta = (navigator.mediaSession && navigator.mediaSession.metadata) ? navigator.mediaSession.metadata : null;
                var title = (meta && meta.title) ? meta.title : document.title;
                var artist = (meta && meta.artist) ? meta.artist : location.hostname.replace(/^www\\./, '');
                var album = (meta && meta.album) ? meta.album : '';
                var image = (meta && meta.artwork && meta.artwork.length > 0) ? meta.artwork[meta.artwork.length - 1].src : '';
                return {
                    'track': title || document.title,
                    'artist': artist,
                    'album': album,
                    'image': image
                };
            } catch (e) {
                return { 'track': document.title, 'artist': location.hostname };
            }
        })()
        """
    )
}

/// Pure-Swift predicate evaluator so invalid Universal Media format strings never throw an uncaught Objective-C exception.
private enum ObjCExceptionCatcher {
    static func evaluatePredicate(format: String, argumentArray: [Any], object: NSDictionary) -> Bool {
        // Fast, safe parser for universal `%K LIKE[c] '*pattern*'` predicates
        let url = (object["URL"] as? String) ?? ""
        let title = (object["title"] as? String) ?? ""

        let clauses = format.components(separatedBy: "||")
        for orClause in clauses {
            let andClauses = orClause.components(separatedBy: "&&")
            var allAndMatched = true
            var argCursor = 0
            for rawAnd in andClauses {
                let clause = rawAnd.trimmingCharacters(in: .whitespacesAndNewlines)
                let isNegated = clause.hasPrefix("!") || clause.uppercased().hasPrefix("NOT ")
                let fieldName = (argCursor < argumentArray.count ? (argumentArray[argCursor] as? String) : "URL") ?? "URL"
                argCursor += 1
                let haystack = (fieldName.caseInsensitiveCompare("title") == .orderedSame ? title : url).lowercased()

                if let firstQuote = clause.firstIndex(of: "'"),
                   let lastQuote = clause.lastIndex(of: "'"),
                   firstQuote < lastQuote {
                    let pattern = String(clause[clause.index(after: firstQuote)..<lastQuote]).lowercased()
                    let matched = wildcardMatch(text: haystack, pattern: pattern)
                    let effective = isNegated ? !matched : matched
                    if !effective {
                        allAndMatched = false
                        break
                    }
                } else {
                    allAndMatched = false
                    break
                }
            }
            if allAndMatched {
                return true
            }
        }
        return false
    }

    private static func wildcardMatch(text: String, pattern: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return true }
        var searchRange = text.startIndex..<text.endIndex
        for (index, part) in parts.enumerated() {
            if index == 0 && !pattern.hasPrefix("*") {
                guard text.hasPrefix(part) else { return false }
                searchRange = text.index(text.startIndex, offsetBy: part.count)..<text.endIndex
            } else if index == parts.count - 1 && !pattern.hasSuffix("*") {
                guard text[searchRange].hasSuffix(part) else { return false }
            } else {
                guard let found = text.range(of: part, range: searchRange) else { return false }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return true
    }
}
