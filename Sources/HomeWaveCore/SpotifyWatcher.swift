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
            if !info.id.isEmpty, info.id != self.lastTrackID {
                self.lastTrackID = info.id
                self.cachedArtDataURL = nil
                self.fetchArtwork { [weak self] dataURL in
                    guard let self else { return }
                    // A rapid skip can start a newer fetch before this one
                    // returns — drop the stale result.
                    guard info.id == self.lastTrackID else { return }
                    self.cachedArtDataURL = dataURL
                    self.onTrack?(info, dataURL)
                }
            } else {
                self.onTrack?(info, self.cachedArtDataURL)
            }
        }
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
