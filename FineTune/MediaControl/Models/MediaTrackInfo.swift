// FineTune/MediaControl/Models/MediaTrackInfo.swift
import AppKit
import Foundation

/// Metadata describing the currently playing (or paused) media track/stream,
/// modeled after BeardedSpice's `BSTrack` and extended for FineTune's UI & HUD.
nonisolated struct MediaTrackInfo: Equatable, Sendable {
    var title: String
    var artist: String?
    var album: String?
    var progress: String?
    var artworkURL: URL?
    var isFavorited: Bool?
    var isPlaying: Bool?
    var playerName: String
    var bundleID: String?

    init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        progress: String? = nil,
        artworkURL: URL? = nil,
        isFavorited: Bool? = nil,
        isPlaying: Bool? = nil,
        playerName: String = "",
        bundleID: String? = nil
    ) {
        self.title = title
        self.artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.album = album?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.progress = progress?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.artworkURL = artworkURL
        self.isFavorited = isFavorited
        self.isPlaying = isPlaying
        self.playerName = playerName
        self.bundleID = bundleID
    }

    /// Parses a dictionary returned by a BeardedSpice JS `trackInfo()` evaluation.
    init?(jsDictionary dict: [String: Any], playerName: String, bundleID: String? = nil) {
        let rawTrack = (dict["track"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawArtist = (dict["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawAlbum = (dict["album"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawProgress = (dict["progress"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawTrack.isEmpty || !(rawArtist ?? "").isEmpty || !(rawAlbum ?? "").isEmpty else {
            return nil
        }

        var parsedURL: URL? = nil
        if let imageStr = (dict["image"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !imageStr.isEmpty {
            let cleaned = imageStr
                .replacingOccurrences(of: "url(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if cleaned.hasPrefix("//") {
                parsedURL = URL(string: "https:" + cleaned)
            } else {
                parsedURL = URL(string: cleaned)
            }
        }

        let fav: Bool?
        if let b = dict["favorited"] as? Bool {
            fav = b
        } else if let n = dict["favorited"] as? NSNumber {
            fav = n.boolValue
        } else {
            fav = nil
        }

        self.init(
            title: rawTrack.isEmpty ? playerName : rawTrack,
            artist: rawArtist,
            album: rawAlbum,
            progress: rawProgress,
            artworkURL: parsedURL,
            isFavorited: fav,
            playerName: playerName,
            bundleID: bundleID
        )
    }

    var subtitleLine: String {
        var parts: [String] = []
        if let artist, !artist.isEmpty {
            parts.append(artist)
        }
        if let album, !album.isEmpty, album != artist {
            parts.append(album)
        }
        if parts.isEmpty {
            return playerName
        }
        return parts.joined(separator: " — ")
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
