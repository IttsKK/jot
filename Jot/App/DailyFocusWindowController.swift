import AppKit
import SwiftUI

@MainActor
final class DailyFocusWindowController: NSObject, NSWindowDelegate {
    private var panel: DailyFocusPanel?
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            present()
        }
    }

    func present() {
        if panel == nil {
            let p = DailyFocusPanel(
                contentRect: NSRect(x: 200, y: 200, width: 380, height: 560)
            )
            p.onEscape = { [weak self] in
                self?.hide()
            }
            
            let root = DailyFocusListView(database: database) { [weak self] in
                self?.hide()
            }
            p.contentView = NSHostingView(rootView: root)
            p.delegate = self
            p.center()
            self.panel = p
        }

        if let panel {
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

final class DailyFocusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onEscape: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow
        setFrameAutosaveName("JotDailyFocusWindow")
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
