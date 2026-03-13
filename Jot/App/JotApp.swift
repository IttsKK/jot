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
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    context.checkForUpdates()
                }
                .disabled(!context.canCheckForUpdates)
            }
            CommandGroup(replacing: .appTermination) {
                Button("Close Jot") {
                    context.dismissFrontendKeepingBackgroundRunning()
                }
                .keyboardShortcut("q")

                Divider()

                Button("Quit Jot Completely") {
                    appDelegate.requestFullTermination()
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
            }
        }
    }
}
