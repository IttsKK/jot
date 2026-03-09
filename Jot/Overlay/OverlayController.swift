import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayController: NSObject {
    private let database: DatabaseManager
    private let settings: SettingsStore
    private var panel: CapturePanel?
    private var viewModel: CaptureViewModel
    private var appResignObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

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

        viewModel.$panelHeight
            .removeDuplicates()
            .sink { [weak self] height in
                guard let self else { return }
                self.updatePanelFrame(height: height, animated: true)
            }
            .store(in: &cancellables)
    }

    deinit {
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
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
            let frame = panelFrame(height: viewModel.panelHeight)
            let panel = CapturePanel(frame: frame)
            panel.onEscape = { [weak self] in
                self?.hide()
            }
            let host = NSHostingView(rootView: CaptureView(viewModel: viewModel, settings: settings, onDismiss: { [weak self] in
                self?.hide()
            }))
            host.wantsLayer = true
            host.layerContentsRedrawPolicy = .duringViewResize
            panel.contentView = host
            panel.refreshCornerMask()
            panel.delegate = self
            self.panel = panel
        }

        if let panel {
            installKeyMonitorIfNeeded()
            viewModel.requestFocus()
            panel.setFrame(panelFrame(height: viewModel.panelHeight), display: true)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        removeKeyMonitor()
        viewModel.clear()
    }

    private func panelFrame(height: CGFloat) -> NSRect {
        let screen = activeScreen()
        let visible = screen.visibleFrame
        let width = min(680, visible.width - 80)
        let x = visible.midX - (width / 2)

        let y: CGFloat
        switch settings.overlayPosition {
        case .upperThird:
            let minHeight: CGFloat = viewModel.meetingSession.isInMeeting ? 84 : 64
            let fixedTop = visible.origin.y + (visible.height * 0.62) + minHeight
            y = fixedTop - height
        case .center:
            y = visible.midY - (height / 2)
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func updatePanelFrame(height: CGFloat, animated: Bool) {
        guard let panel, panel.isVisible else { return }
        var targetFrame = panelFrame(height: height)
        targetFrame.origin.y = panel.frame.maxY - height
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let match = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isVisible == true else { return event }
            if event.keyCode == 53 {
                self.hide()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

extension OverlayController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
