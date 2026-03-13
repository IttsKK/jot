import AppKit
import Foundation
import Sparkle

@MainActor
final class AppContext: ObservableObject {
    static let shared = AppContext()
    private enum HotKeyID {
        static let quickCapture: UInt32 = 1
        static let openApp: UInt32 = 2
        static let dailyFocus: UInt32 = 3
    }

    let database: DatabaseManager
    let settings: SettingsStore
    let meetingSession: MeetingSession
    let overlay: OverlayController
    let statusBar: StatusBarController
    let notificationManager: NotificationManager
    private var mainWindowController: MainWindowController?
    private var dailyFocusWindowController: DailyFocusWindowController?
    private var settingsObserver: NSObjectProtocol?
    private var interfaceThemeObserver: NSObjectProtocol?
    private var windowCloseObserver: NSObjectProtocol?
    private lazy var updaterController = Self.makeUpdaterControllerIfAvailable()

    private init() {
        database = try! DatabaseManager()
        settings = SettingsStore()
        meetingSession = MeetingSession(database: database)
        overlay = OverlayController(database: database, settings: settings, meetingSession: meetingSession)
        statusBar = StatusBarController(database: database, settings: settings, overlay: overlay, meetingSession: meetingSession)
        notificationManager = NotificationManager(database: database, settings: settings)

        statusBar.onOpenApp = { [weak self] in
            self?.openMainWindow()
        }
        statusBar.onOpenDailyFocus = { [weak self] in
            self?.openDailyFocusWindow()
        }
        statusBar.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        statusBar.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }
        statusBar.onQuitCompletely = {
            (NSApplication.shared.delegate as? AppDelegate)?.requestFullTermination()
        }
        statusBar.canCheckForUpdates = canCheckForUpdates
    }

    func bootstrap() {
        _ = updaterController
        registerHotKeys()
        notificationManager.bootstrap()
        updateApplicationIcon()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .jotSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.registerHotKeys()
                self?.updateApplicationIcon()
            }
        }

        interfaceThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateApplicationIcon()
            }
        }

        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in
                self?.scheduleRestoreAccessoryActivationIfNeeded()
            }
        }
    }

    func registerHotKeys() {
        var failures: [String] = []

        let quickCaptureRegistered = HotKeyManager.shared.register(
            id: HotKeyID.quickCapture,
            shortcut: HotKeyShortcut(
                keyCode: settings.quickCaptureHotKeyCode,
                modifiers: settings.quickCaptureHotKeyModifiers
            )
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.overlay.toggle()
            }
        }
        if !quickCaptureRegistered {
            failures.append("Quick Capture")
        }

        let openAppRegistered = HotKeyManager.shared.register(
            id: HotKeyID.openApp,
            shortcut: HotKeyShortcut(
                keyCode: settings.openAppHotKeyCode,
                modifiers: settings.openAppHotKeyModifiers
            )
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.openMainWindow()
            }
        }
        if !openAppRegistered {
            failures.append("Open App")
        }

        let dailyFocusRegistered = HotKeyManager.shared.register(
            id: HotKeyID.dailyFocus,
            shortcut: HotKeyShortcut(
                keyCode: settings.dailyFocusHotKeyCode,
                modifiers: settings.dailyFocusHotKeyModifiers
            )
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.openDailyFocusWindow()
            }
        }
        if !dailyFocusRegistered {
            failures.append("Today List")
        }

        if failures.isEmpty {
            settings.hotKeyRegistrationError = nil
        } else {
            settings.hotKeyRegistrationError = "Jot couldn't register \(failures.joined(separator: ", ")). The shortcut may already be in use by macOS or another app."
        }
    }

    func openMainWindow() {
        overlay.hide()
        NSApplication.shared.setActivationPolicy(.regular)
        if mainWindowController == nil {
            mainWindowController = MainWindowController(database: database, settings: settings, meetingSession: meetingSession)
            mainWindowController?.onMainWindowClosed = { [weak self] in
                self?.handleMainWindowClosed()
            }
        }
        mainWindowController?.present()
    }

    func openDailyFocusWindow() {
        if dailyFocusWindowController == nil {
            dailyFocusWindowController = DailyFocusWindowController(database: database)
        }
        dailyFocusWindowController?.toggle()
    }

    func openSettingsWindow() {
        overlay.hide()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func closePrimaryWindowsKeepingBackgroundRunning() {
        dismissFrontendKeepingBackgroundRunning()
    }

    func dismissFrontendKeepingBackgroundRunning() {
        overlay.hide()
        dailyFocusWindowController?.hide()

        for window in NSApplication.shared.windows where window.isVisible && !(window is NSPanel) {
            window.performClose(nil)
        }

        scheduleRestoreAccessoryActivationIfNeeded()
    }

    private func handleMainWindowClosed() {
        scheduleRestoreAccessoryActivationIfNeeded()
    }

    private func scheduleRestoreAccessoryActivationIfNeeded() {
        _Concurrency.Task { @MainActor [weak self] in
            await _Concurrency.Task.yield()
            self?.restoreAccessoryActivationIfNeeded()
        }
    }

    private func restoreAccessoryActivationIfNeeded() {
        let hasVisibleStandardWindow = hasVisibleStandardWindow()
        if !hasVisibleStandardWindow {
            NSApplication.shared.setActivationPolicy(.accessory)
            hideAppIfFullyBackgrounded()
        }
    }

    private func hasVisibleStandardWindow() -> Bool {
        NSApplication.shared.windows.contains { window in
            window.isVisible && !(window is NSPanel)
        }
    }

    private func hasVisibleWindow() -> Bool {
        NSApplication.shared.windows.contains(where: \.isVisible)
    }

    private func hideAppIfFullyBackgrounded() {
        guard NSApplication.shared.isActive else { return }
        guard !hasVisibleWindow() else { return }

        DispatchQueue.main.async {
            guard !self.hasVisibleWindow() else { return }
            NSApplication.shared.hide(nil)
        }
    }

    private func updateApplicationIcon() {
        // If modern themed app icons are configured via asset catalogs,
        // let the system drive icon appearance (light/dark/tinted/clear).
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String != nil {
            return
        }

        let prefersDarkIcon: Bool
        switch settings.appearance {
        case .dark:
            prefersDarkIcon = true
        case .light:
            prefersDarkIcon = false
        case .system:
            prefersDarkIcon = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        let preferredResource = prefersDarkIcon ? "AppIconDark" : "AppIconLight"
        if let image = Bundle.main.image(forResource: preferredResource) ?? Bundle.main.image(forResource: "AppIcon") {
            NSApp.applicationIconImage = image
        }
    }

    private static func makeUpdaterControllerIfAvailable() -> SPUStandardUpdaterController? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
}
