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
}
