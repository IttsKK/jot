import AppKit
import Foundation
import Sparkle

@MainActor
final class AppContext: ObservableObject {
    static let shared = AppContext()
    private enum HotKeyID {
        static let quickCapture: UInt32 = 1
        static let openApp: UInt32 = 2
    }

    let database: DatabaseManager
    let settings: SettingsStore
    let overlay: OverlayController
    let statusBar: StatusBarController
    let notificationManager: NotificationManager
    private var mainWindowController: MainWindowController?
    private var settingsObserver: NSObjectProtocol?
    private var interfaceThemeObserver: NSObjectProtocol?
    private lazy var updaterController = Self.makeUpdaterControllerIfAvailable()

    private init() {
        database = try! DatabaseManager()
        settings = SettingsStore()
        overlay = OverlayController(database: database, settings: settings)
        statusBar = StatusBarController(database: database, settings: settings, overlay: overlay)
        notificationManager = NotificationManager(database: database, settings: settings)

        statusBar.onOpenApp = { [weak self] in
            self?.openMainWindow()
        }
        statusBar.onOpenSettings = {
            NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        statusBar.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
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
    }

    func registerHotKeys() {
        let quickCaptureShortcut = HotKeyShortcut(
            keyCode: settings.quickCaptureHotKeyCode,
            modifiers: settings.quickCaptureHotKeyModifiers
        )
        HotKeyManager.shared.register(id: HotKeyID.quickCapture, shortcut: quickCaptureShortcut) { [weak self] in
            DispatchQueue.main.async {
                self?.overlay.toggle()
            }
        }

        let openAppShortcut = HotKeyShortcut(
            keyCode: settings.openAppHotKeyCode,
            modifiers: settings.openAppHotKeyModifiers
        )
        HotKeyManager.shared.register(id: HotKeyID.openApp, shortcut: openAppShortcut) { [weak self] in
            DispatchQueue.main.async {
                self?.openMainWindow()
            }
        }
    }

    func openMainWindow() {
        overlay.hide()
        NSApplication.shared.setActivationPolicy(.regular)
        if mainWindowController == nil {
            mainWindowController = MainWindowController(database: database, settings: settings)
            mainWindowController?.onMainWindowClosed = { [weak self] in
                self?.handleMainWindowClosed()
            }
        }
        mainWindowController?.present()
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func handleMainWindowClosed() {
        NSApplication.shared.setActivationPolicy(.accessory)
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
