import Foundation
import HomeWaveCore

func runSpotifyParsingChecks() {
    let playing = SpotifyNotificationParser.parse([
        "Name": "Song", "Artist": "Artist", "Album": "Album",
        "Player State": "Playing", "Track ID": "spotify:track:abc",
    ])
    check(playing == TrackInfo(id: "spotify:track:abc", title: "Song",
                               artist: "Artist", album: "Album", playing: true),
          "playing notification parsed")

    let paused = SpotifyNotificationParser.parse([
        "Name": "Song", "Player State": "Paused", "Track ID": "spotify:track:abc",
    ])
    check(paused?.playing == false, "paused state parsed")
    check(paused?.artist == "", "missing artist defaults to empty")

    check(SpotifyNotificationParser.parse(["Name": "x"]) == nil,
          "missing player state returns nil")
}
