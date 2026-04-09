import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
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
