import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SPM bare executables are not a .app bundle; without this the window often stays
        // behind other apps or never becomes key, so it looks like `swift run` did nothing.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MacCacheCleanerApp: App {
    @StateObject private var viewModel = CacheCleanerViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandMenu("Actions") {
                Button("Dry Run…") {
                    Task { await viewModel.dryRunSelected() }
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
    }
}
