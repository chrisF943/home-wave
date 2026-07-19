import AppKit
import HomeWaveCore
import WebKit

// The webview covers the full window (including the transparent titlebar),
// which swallows every click — this invisible strip drives the window drag
// itself so the top edge behaves like a titlebar again.
final class WindowDragStrip: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let engine = AudioEngine()
    let spotify = SpotifyWatcher()
    private let frameEncoder = JSONEncoder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "HomeWave"
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.fullScreenPrimary]

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "homewave")
        // file:// pages need these to import ES modules and read canvas pixels.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(webView)

        // Top 28px acts as the drag handle, stopping 70px short of the right
        // edge so the settings gear underneath stays clickable.
        let contentBounds = window.contentView!.bounds
        let dragStrip = WindowDragStrip(frame: NSRect(
            x: 0, y: contentBounds.height - 28,
            width: contentBounds.width - 70, height: 28))
        dragStrip.autoresizingMask = [.width, .minYMargin]
        window.contentView!.addSubview(dragStrip, positioned: .above, relativeTo: webView)

        let dir = webDirectoryURL()
        webView.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Start feeds only once the page is ready to receive them.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        engine.onStatus = { [weak self] status in
            NSLog("audio status: %@", status)
            self?.push("window.homewave && window.homewave.onAudioStatus('\(status)')")
        }
        engine.onFrame = { [weak self] frame in self?.pushFrame(frame) }
        engine.start()

        spotify.onTrack = { [weak self] info, art in self?.pushTrack(info, artDataURL: art) }
        spotify.start()
    }

    private func webDirectoryURL() -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.html").path) {
            return bundled
        }
        // Dev fallback for `swift run` from the repo root.
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("web")
    }

    private func push(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func pushFrame(_ frame: AudioFrame) {
        guard let data = try? frameEncoder.encode(frame),
              let json = String(data: data, encoding: .utf8) else { return }
        push("window.homewave && window.homewave.onAudioFrame(\(json))")
    }

    private func pushTrack(_ info: TrackInfo, artDataURL: String?) {
        var dict: [String: Any] = [
            "title": info.title, "artist": info.artist,
            "album": info.album, "playing": info.playing,
        ]
        if let artDataURL { dict["artDataURL"] = artDataURL }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return }
        push("window.homewave && window.homewave.onTrack(\(json))")
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "homewave",
              let body = message.body as? [String: Any],
              let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "retryAudioPermission":
            engine.start()
        case "openSystemSettings":
            if let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    func applicationWillTerminate(_ notification: Notification) { engine.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
