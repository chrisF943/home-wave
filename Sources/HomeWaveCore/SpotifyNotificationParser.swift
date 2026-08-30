import Foundation

public enum SpotifyNotificationParser {
    public static func parse(_ userInfo: [AnyHashable: Any]) -> TrackInfo? {
        guard let state = userInfo["Player State"] as? String else { return nil }
        return TrackInfo(
            id: userInfo["Track ID"] as? String ?? "",
            title: userInfo["Name"] as? String ?? "",
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            playing: state == "Playing")
    }

    /// Parses the newline-delimited result of the "current track" AppleScript.
    /// Field order: id, name, artist, album, player state.
    public static func parseScriptOutput(_ raw: String) -> TrackInfo? {
        let f = raw.components(separatedBy: "\n")
        guard f.count >= 5 else { return nil }
        let state = f[4].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !state.isEmpty else { return nil }
        return TrackInfo(
            id: f[0], title: f[1], artist: f[2], album: f[3],
            // The notification says "Playing"; AppleScript says "playing".
            playing: state.caseInsensitiveCompare("playing") == .orderedSame)
    }
}
