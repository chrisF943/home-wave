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

    // AppleScript seed path used when a track is already playing at launch.
    let seeded = SpotifyNotificationParser.parseScriptOutput(
        "spotify:track:xyz\nSong\nArtist\nAlbum\nplaying")
    check(seeded == TrackInfo(id: "spotify:track:xyz", title: "Song",
                              artist: "Artist", album: "Album", playing: true),
          "script output parsed")

    check(SpotifyNotificationParser.parseScriptOutput(
        "id\nSong\nArtist\nAlbum\npaused")?.playing == false,
        "script paused state parsed")

    check(SpotifyNotificationParser.parseScriptOutput("id\nSong\nArtist") == nil,
          "truncated script output returns nil")
}
