import AppKit
import SwiftUI

@MainActor
final class OverlayController: NSObject {
    private let database: DatabaseManager
    private let settings: SettingsStore
    private var panel: CapturePanel?
    private var viewModel: CaptureViewModel
    private var appResignObserver: NSObjectProtocol?

    init(database: DatabaseManager, settings: SettingsStore, meetingSession: MeetingSession) {
        self.database = database
        self.settings = settings
        self.viewModel = CaptureViewModel(database: database, settings: settings, meetingSession: meetingSession)
        super.init()
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hide()
            }
        }
    }

    deinit {
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
        }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let frame = panelFrame()
            let panel = CapturePanel(frame: frame)
            panel.contentView = NSHostingView(rootView: CaptureView(viewModel: viewModel, onDismiss: { [weak self] in
                self?.hide()
            }))
            panel.delegate = self
            self.panel = panel
        }

        if let panel {
            viewModel.requestFocus()
            panel.setFrame(panelFrame(), display: true)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        viewModel.clear()
    }

    private func panelFrame() -> NSRect {
        let screen = activeScreen()
        let visible = screen.visibleFrame
        let width = min(680, visible.width - 80)
        let height: CGFloat = 104
        let x = visible.midX - (width / 2)

        let y: CGFloat
        switch settings.overlayPosition {
        case .upperThird:
            y = visible.origin.y + (visible.height * 0.62)
        case .center:
            y = visible.midY - (height / 2)
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let match = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }
}

extension OverlayController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
