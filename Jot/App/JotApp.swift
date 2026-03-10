import SwiftUI

@main
struct JotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var context = AppContext.shared

    var body: some Scene {
        Settings {
            SettingsView(
                settings: context.settings,
                database: context.database,
                onCheckForUpdates: { context.checkForUpdates() },
                canCheckForUpdates: context.canCheckForUpdates
            )
        }
    }
}
