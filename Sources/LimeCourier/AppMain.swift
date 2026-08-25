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
    private var userInitiatedQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 先注册状态栏图标再切换后台模式：macOS 26 对后台模式应用的
        // 菜单栏图标需要系统审批，常规模式下注册更容易触发“允许显示”弹窗。
        let controller = AppController()
        controller.onQuit = { [weak self] in
            self?.userInitiatedQuit = true
            NSApp.terminate(nil)
        }
        self.controller = controller
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.prepareToTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // macOS 26 StatusKit 在菜单栏图标未获批准时会触发系统终止请求，
        // 此时应用应继续运行（宠物窗口与右键菜单不受影响）；仅放行用户主动退出。
        userInitiatedQuit ? .terminateNow : .terminateCancel
    }
}
