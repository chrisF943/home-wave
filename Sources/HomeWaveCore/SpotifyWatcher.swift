import AppKit
import Foundation

public final class SpotifyWatcher {
    public var onTrack: ((TrackInfo, String?) -> Void)?

    private var lastTrackID = ""
    private var cachedArtDataURL: String?
    private static let maxArtworkBytes = 8 * 1024 * 1024

    public init() {}

    public func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let info = SpotifyNotificationParser.parse(note.userInfo ?? [:]) else { return }
            self.handle(info)
        }

        // PlaybackStateChanged only fires on a *change*, so a track already
        // playing when HomeWave launches would never reach the UI until the
        // user paused or skipped. Seed from Spotify's current state instead.
        // Async so a first-run Automation prompt cannot block the launch.
        DispatchQueue.main.async { [weak self] in self?.seedFromCurrentTrack() }
    }

    private func handle(_ info: TrackInfo) {
        if !info.id.isEmpty, info.id != lastTrackID {
            lastTrackID = info.id
            cachedArtDataURL = nil
            fetchArtwork { [weak self] dataURL in
                guard let self else { return }
                // A rapid skip can start a newer fetch before this one
                // returns — drop the stale result.
                guard info.id == self.lastTrackID else { return }
                self.cachedArtDataURL = dataURL
                self.onTrack?(info, dataURL)
            }
        } else {
            onTrack?(info, cachedArtDataURL)
        }
    }

    /// Asks Spotify what is playing right now. Never launches Spotify: if it is
    /// not already running there is nothing to show, and `tell application`
    /// would start it.
    private func seedFromCurrentTrack() {
        guard !NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.spotify.client")
            .isEmpty else { return }
        let source = """
        tell application "Spotify"
            set t to current track
            return (id of t) & "\\n" & (name of t) & "\\n" & (artist of t) \
                 & "\\n" & (album of t) & "\\n" & (player state as string)
        end tell
        """
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let raw = script.executeAndReturnError(&errorInfo).stringValue,
              let info = SpotifyNotificationParser.parseScriptOutput(raw) else { return }
        handle(info)
    }

    private func fetchArtwork(completion: @escaping (String?) -> Void) {
        // First run triggers the Automation ("Apple Events") permission prompt for Spotify.
        let source = "tell application \"Spotify\" to get artwork url of current track"
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let urlString = script.executeAndReturnError(&errorInfo).stringValue,
              let url = URL(string: urlString),
              // Only ever fetch artwork over https. URLSession will happily read
              // file:// URLs, so any other scheme here would turn into a local
              // file read that gets base64'd into the webview as an "image".
              url.scheme == "https" else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            // Cover art is a few hundred KB; anything far larger isn't artwork,
            // and base64 would inflate it another third on its way into JS.
            var dataURL: String?
            if let data, data.count <= SpotifyWatcher.maxArtworkBytes {
                dataURL = "data:image/jpeg;base64," + data.base64EncodedString()
            }
            DispatchQueue.main.async { completion(dataURL) }
        }.resume()
    }
}
