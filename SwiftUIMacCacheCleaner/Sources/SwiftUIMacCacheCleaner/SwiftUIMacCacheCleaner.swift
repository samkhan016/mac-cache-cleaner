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
        WindowGroup("Mac Cache Cleaner") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 920, minHeight: 640)
        }
    }
}
