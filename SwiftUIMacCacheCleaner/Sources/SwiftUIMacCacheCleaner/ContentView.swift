import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: CacheCleanerViewModel
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 14) {
            header
            statsRow
            actionRow
            cacheList
            footer
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.12), Color(red: 0.10, green: 0.12, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .alert("Confirm Cleanup", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Selected", role: .destructive) {
                Task { await viewModel.clearSelected() }
            }
        } message: {
            Text("Delete contents of selected cache folders? This cannot be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mac Cache Cleaner")
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(.white)
            Text("Native SwiftUI cleaner for macOS and developer caches.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.32), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(title: "Total Disk", value: formatSize(viewModel.diskStats.total), color: .blue)
            statCard(title: "Used", value: formatSize(viewModel.diskStats.used), color: .orange)
            statCard(title: "Free", value: formatSize(viewModel.diskStats.free), color: .green)
            statCard(title: "Cache Footprint", value: formatSize(viewModel.totalCacheBytes), color: .purple)
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Scan Sizes") { Task { await viewModel.scanSizes() } }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(viewModel.isBusy)
            Button("Select All") { viewModel.selectAll() }
                .buttonStyle(.bordered)
            Button("Recommended") { viewModel.selectRecommended() }
                .buttonStyle(.bordered)
            Spacer()
            Button("Clear Selected") { showConfirm = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isBusy)
        }
    }

    private var cacheList: some View {
        List {
            ForEach(viewModel.targets) { target in
                HStack(spacing: 12) {
                    Toggle(
                        isOn: Binding(
                            get: { viewModel.selections[target.id] ?? false },
                            set: { viewModel.selections[target.id] = $0 }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(target.pathPattern)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Text(formatSize(viewModel.targetSizes[target.id] ?? 0))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.white.opacity(0.04))
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(.clear)
    }

    private var footer: some View {
        HStack {
            if viewModel.isBusy {
                ProgressView()
                    .scaleEffect(0.8)
            }
            Text(viewModel.statusText)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text("Tip: Close Xcode/Android Studio before cleaning")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
