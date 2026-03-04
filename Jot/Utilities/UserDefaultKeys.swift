import Foundation

enum UserDefaultKeys {
    static let quickCaptureHotKeyCode = "quickCaptureHotKeyCode"
    static let quickCaptureHotKeyModifiers = "quickCaptureHotKeyModifiers"
    static let openAppHotKeyCode = "openAppHotKeyCode"
    static let openAppHotKeyModifiers = "openAppHotKeyModifiers"

    // Legacy keys for migration from earlier builds.
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let defaultQueue = "defaultQueue"
    static let overlayPosition = "overlayPosition"
    static let launchAtLogin = "launchAtLogin"
    static let notificationsEnabled = "notificationsEnabled"
    static let summaryEnabled = "summaryEnabled"
    static let summaryHour = "summaryHour"
    static let summaryMinute = "summaryMinute"
    static let snoozeDays = "snoozeDays"
    static let appearance = "appearance"
}
