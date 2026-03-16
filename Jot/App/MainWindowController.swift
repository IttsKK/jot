import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    var onCloseRequested: (() -> Void)?

    init(database: DatabaseManager, settings: SettingsStore, meetingSession: MeetingSession) {
        let root = MainTaskListView(database: database, settings: settings, meetingSession: meetingSession)
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: host)
        window.title = "Jot"
        window.setContentSize(NSSize(width: 1060, height: 660))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCloseRequested?()
        return false
    }
}
