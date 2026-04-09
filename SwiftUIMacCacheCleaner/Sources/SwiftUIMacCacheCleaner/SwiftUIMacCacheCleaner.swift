import SwiftUI

@main
struct MacCacheCleanerApp: App {
    @StateObject private var viewModel = CacheCleanerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 920, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
