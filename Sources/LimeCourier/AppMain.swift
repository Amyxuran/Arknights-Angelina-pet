import AppKit

@main
enum LimeCourierMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = LimeCourierAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class LimeCourierAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AppController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.prepareToTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
