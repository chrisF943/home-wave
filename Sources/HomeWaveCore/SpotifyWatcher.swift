import AppKit
import Foundation

public final class SpotifyWatcher {
    public var onTrack: ((TrackInfo, String?) -> Void)?

    private var lastTrackID = ""
    private var cachedArtDataURL: String?

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
              let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let dataURL = data.map { "data:image/jpeg;base64," + $0.base64EncodedString() }
            DispatchQueue.main.async { completion(dataURL) }
        }.resume()
    }
}
