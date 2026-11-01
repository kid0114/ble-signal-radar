import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: SignalWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = SignalWindowController()
        self.controller = controller
        controller.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

@main
struct SignalRadar {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
