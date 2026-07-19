import AppKit
import HomeWaveCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let engine = AudioEngine()
    private var frameCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "HomeWave"
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        engine.onStatus = { NSLog("audio status: \($0)") }
        engine.onFrame = { [weak self] frame in
            guard let self else { return }
            self.frameCount += 1
            if self.frameCount % 30 == 0 {
                NSLog("level=%.3f beat=%@ maxBand=%.3f",
                      frame.level, frame.beat ? "Y" : "n", frame.bands.max() ?? 0)
            }
        }
        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) { engine.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
