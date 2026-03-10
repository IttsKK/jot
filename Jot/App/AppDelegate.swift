import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let context = AppContext.shared
    private var allowsFullTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        context.bootstrap()
        // When users launch the app bundle directly, show the main window
        // immediately so launch feels explicit instead of "menu-bar only".
        context.openMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        context.openMainWindow()
        return true
    }

    func requestFullTermination() {
        allowsFullTermination = true
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowsFullTermination {
            return .terminateNow
        }
        context.closePrimaryWindowsKeepingBackgroundRunning()
        return .terminateCancel
    }
}
