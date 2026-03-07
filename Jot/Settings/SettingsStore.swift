import AppKit
import Carbon
import Foundation

enum OverlayPosition: String, CaseIterable {
    case upperThird
    case center

    var displayName: String {
        switch self {
        case .upperThird:
            return "Upper Third"
        case .center:
            return "Center"
        }
    }
}

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        rawValue.capitalized
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: UserDefaultKeys.launchAtLogin)
            LaunchAtLoginManager.setEnabled(launchAtLogin)
            notify()
        }
    }

    @Published var defaultQueue: TaskQueue {
        didSet { defaults.set(defaultQueue.rawValue, forKey: UserDefaultKeys.defaultQueue); notify() }
    }

    @Published var quickCaptureHotKeyCode: UInt32 {
        didSet { defaults.set(Int(quickCaptureHotKeyCode), forKey: UserDefaultKeys.quickCaptureHotKeyCode); notify() }
    }

    @Published var quickCaptureHotKeyModifiers: UInt32 {
        didSet { defaults.set(Int(quickCaptureHotKeyModifiers), forKey: UserDefaultKeys.quickCaptureHotKeyModifiers); notify() }
    }

    @Published var openAppHotKeyCode: UInt32 {
        didSet { defaults.set(Int(openAppHotKeyCode), forKey: UserDefaultKeys.openAppHotKeyCode); notify() }
    }

    @Published var openAppHotKeyModifiers: UInt32 {
        didSet { defaults.set(Int(openAppHotKeyModifiers), forKey: UserDefaultKeys.openAppHotKeyModifiers); notify() }
    }

    @Published var dailyFocusHotKeyCode: UInt32 {
        didSet { defaults.set(Int(dailyFocusHotKeyCode), forKey: UserDefaultKeys.dailyFocusHotKeyCode); notify() }
    }

    @Published var dailyFocusHotKeyModifiers: UInt32 {
        didSet { defaults.set(Int(dailyFocusHotKeyModifiers), forKey: UserDefaultKeys.dailyFocusHotKeyModifiers); notify() }
    }

    @Published var overlayPosition: OverlayPosition {
        didSet { defaults.set(overlayPosition.rawValue, forKey: UserDefaultKeys.overlayPosition); notify() }
    }

    @Published var quickCaptureCommandPreviewEnabled: Bool {
        didSet { defaults.set(quickCaptureCommandPreviewEnabled, forKey: UserDefaultKeys.quickCaptureCommandPreviewEnabled); notify() }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: UserDefaultKeys.notificationsEnabled); notify() }
    }

    @Published var summaryEnabled: Bool {
        didSet { defaults.set(summaryEnabled, forKey: UserDefaultKeys.summaryEnabled); notify() }
    }

    @Published var summaryHour: Int {
        didSet { defaults.set(summaryHour, forKey: UserDefaultKeys.summaryHour); notify() }
    }

    @Published var summaryMinute: Int {
        didSet { defaults.set(summaryMinute, forKey: UserDefaultKeys.summaryMinute); notify() }
    }

    @Published var snoozeDays: Int {
        didSet { defaults.set(snoozeDays, forKey: UserDefaultKeys.snoozeDays); notify() }
    }

    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: UserDefaultKeys.appearance)
            NSApp.appearance = appearance.nsAppearance
            notify()
        }
    }

    @Published var hotKeyRegistrationError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        launchAtLogin = defaults.object(forKey: UserDefaultKeys.launchAtLogin) as? Bool ?? false

        let rawDefaultQueue = defaults.string(forKey: UserDefaultKeys.defaultQueue)
        defaultQueue = TaskQueue(rawValue: rawDefaultQueue ?? TaskQueue.work.rawValue) ?? .work

        let legacyCode = defaults.integer(forKey: UserDefaultKeys.hotKeyCode)
        let legacyModifiers = defaults.integer(forKey: UserDefaultKeys.hotKeyModifiers)

        let quickCode = defaults.object(forKey: UserDefaultKeys.quickCaptureHotKeyCode) as? Int
        let quickModifiers = defaults.object(forKey: UserDefaultKeys.quickCaptureHotKeyModifiers) as? Int
        quickCaptureHotKeyCode = UInt32(quickCode ?? (legacyCode == 0 ? 49 : legacyCode))
        quickCaptureHotKeyModifiers = UInt32(quickModifiers ?? (legacyModifiers == 0 ? optionKey : legacyModifiers))

        let openCode = defaults.object(forKey: UserDefaultKeys.openAppHotKeyCode) as? Int
        let openModifiers = defaults.object(forKey: UserDefaultKeys.openAppHotKeyModifiers) as? Int
        openAppHotKeyCode = UInt32(openCode ?? 49)
        openAppHotKeyModifiers = UInt32(openModifiers ?? (optionKey | shiftKey))

        let focusCode = defaults.object(forKey: UserDefaultKeys.dailyFocusHotKeyCode) as? Int
        let focusModifiers = defaults.object(forKey: UserDefaultKeys.dailyFocusHotKeyModifiers) as? Int
        dailyFocusHotKeyCode = UInt32(focusCode ?? 49) // space
        dailyFocusHotKeyModifiers = UInt32(focusModifiers ?? (controlKey | optionKey))

        let rawOverlay = defaults.string(forKey: UserDefaultKeys.overlayPosition)
        overlayPosition = OverlayPosition(rawValue: rawOverlay ?? OverlayPosition.upperThird.rawValue) ?? .upperThird

        quickCaptureCommandPreviewEnabled = defaults.object(forKey: UserDefaultKeys.quickCaptureCommandPreviewEnabled) as? Bool ?? true

        notificationsEnabled = defaults.object(forKey: UserDefaultKeys.notificationsEnabled) as? Bool ?? true
        summaryEnabled = defaults.object(forKey: UserDefaultKeys.summaryEnabled) as? Bool ?? true
        summaryHour = max(0, min(23, defaults.object(forKey: UserDefaultKeys.summaryHour) as? Int ?? 9))
        summaryMinute = max(0, min(59, defaults.object(forKey: UserDefaultKeys.summaryMinute) as? Int ?? 0))
        snoozeDays = max(1, defaults.object(forKey: UserDefaultKeys.snoozeDays) as? Int ?? 7)

        let rawAppearance = defaults.string(forKey: UserDefaultKeys.appearance)
        appearance = AppAppearance(rawValue: rawAppearance ?? AppAppearance.system.rawValue) ?? .system
        hotKeyRegistrationError = nil
        NSApp.appearance = appearance.nsAppearance
        LaunchAtLoginManager.setEnabled(launchAtLogin)
    }

    private func notify() {
        NotificationCenter.default.post(name: .jotSettingsDidChange, object: nil)
    }
}
