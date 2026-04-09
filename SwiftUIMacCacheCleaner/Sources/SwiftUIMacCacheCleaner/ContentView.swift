import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: CacheCleanerViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConfirm = false
    @State private var activePrimaryAction: PrimaryAction?
    @State private var statShimmerSweep: Bool = false
    /// Drives `List(selection:)`; includes Home plus discovery modes.
    @State private var selectedSidebar: CacheCleanerViewModel.SidebarDestination = .home
    /// Keeps the sidebar open; paired with `hideSidebarToggleIfAvailable()`.
    @State private var splitViewColumnVisibility: NavigationSplitViewVisibility = .all
    private let statsColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    private var canClean: Bool {
        viewModel.hasCompletedScan && viewModel.selectedSummary().count > 0
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewColumnVisibility) {
            List(selection: $selectedSidebar) {
                Label("Home", systemImage: "house.fill")
                    .tag(CacheCleanerViewModel.SidebarDestination.home)
                ForEach(CacheCleanerViewModel.DiscoveryMode.allCases) { mode in
                    Label(mode.sidebarLabel, systemImage: mode.sidebarSystemImage)
                        .tag(CacheCleanerViewModel.SidebarDestination.discovery(mode))
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .navigationTitle("")
            .padding(.top, 14)
            .hideSidebarToggleIfAvailable()
            .disabled(viewModel.isBusy)
            .onAppear {
                if case .discovery(let mode) = selectedSidebar {
                    viewModel.selectDiscoveryMode(mode)
                }
            }
            .onChange(of: selectedSidebar) { newDest in
                guard !viewModel.isBusy else {
                    selectedSidebar = .discovery(viewModel.discoveryMode)
                    return
                }
                if case .discovery(let mode) = newDest {
                    viewModel.selectDiscoveryMode(mode)
                }
            }
        } detail: {
            ZStack(alignment: .top) {
                appBackground

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.black.opacity(0.16), Color.clear]
                                : [Color.black.opacity(0.045), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 8)
                    .ignoresSafeArea(edges: .top)
                    .frame(maxHeight: .infinity, alignment: .top)

                Group {
                    switch selectedSidebar {
                    case .home:
                        homeScrollContent
                    case .discovery:
                        modeScrollContent
                    }
                }
            }
            .navigationTitle("")
            .hideSidebarToggleIfAvailable()
        }
        .onChange(of: splitViewColumnVisibility) { newValue in
            if newValue == .detailOnly {
                splitViewColumnVisibility = .all
            }
        }
        .hideSidebarToggleIfAvailable()
        .onAppear {
            suppressNavigationSplitSidebarToolbarToggleIfNeeded()
        }
        .alert("Confirm Cleanup", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Selected", role: .destructive) {
                activePrimaryAction = .cleanSelected
                Task { await viewModel.clearSelected() }
            }
        } message: {
            Text("Delete only contents from selected safe cache/log/temp/dev-build folders. App data and personal files are not targeted. This cannot be undone.")
        }
        .onChange(of: viewModel.isBusy) { isBusy in
            if isBusy == false {
                activePrimaryAction = nil
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.linear(duration: 1.45).repeatForever(autoreverses: false)) {
                    statShimmerSweep = true
                }
            }
        }
        .toolbarBackground(toolbarGradient, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(colorScheme, for: .windowToolbar)
        .preferredColorScheme(.light)
    }

    private var modeIntroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.discoveryMode.rawValue)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(primaryTextColor)
            Text(viewModel.discoveryModeDescription)
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .sectionCard(cornerRadius: 20)
    }

    private var scanPromptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Cleanup Targets")
            Text("Run Scan to measure folders and show what can be reclaimed in this mode.")
                .font(.system(size: 13))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .sectionCard()
    }

    private var cleanupResultsCard: some View {
        Group {
            if let summary = viewModel.lastCleanupSummary {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Last cleanup")
                    Text(formatSize(summary.freedBytes))
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(primaryTextColor)
                    Text("Space reclaimed (estimated)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tertiaryTextColor)
                    Divider()
                        .overlay(Color(red: 0.45, green: 0.55, blue: 0.72))
                    HStack(spacing: 16) {
                        resultMetric(title: "Items removed", value: "\(summary.itemsDeleted)")
                        resultMetric(title: "Skipped", value: "\(summary.itemsFailed)")
                        resultMetric(title: "Inaccessible", value: "\(summary.inaccessibleFolders)")
                        resultMetric(title: "Blocked", value: "\(summary.unsafeFolders)")
                    }
                    Text(viewModel.lastOperationReport)
                        .font(.system(size: 11))
                        .foregroundStyle(tertiaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .sectionCard()
            }
        }
    }

    private func resultMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(primaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.06, green: 0.12, blue: 0.20),
                        Color(red: 0.06, green: 0.10, blue: 0.18),
                        Color(red: 0.05, green: 0.08, blue: 0.15)
                    ]
                    : [
                        Color(red: 0.31, green: 0.68, blue: 0.98),
                        Color(red: 0.52, green: 0.78, blue: 0.99),
                        Color(red: 0.69, green: 0.85, blue: 1.00)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if colorScheme != .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.49, blue: 0.94).opacity(0.72),
                        Color(red: 0.08, green: 0.33, blue: 0.80).opacity(0.58),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.12 : 0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -260, y: -250)

            Circle()
                .fill(Color.indigo.opacity(colorScheme == .dark ? 0.10 : 0.10))
                .frame(width: 510, height: 510)
                .blur(radius: 130)
                .offset(x: 230, y: -120)
        }
        .ignoresSafeArea()
    }

    private var topHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mac Cache Cleaner")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                Text("Safe cleanup for cache, logs and temporary files")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }
            Spacer()
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 58, height: 58)
                .scaleEffect(1.34)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.10, green: 0.49, blue: 0.94),
                                    Color(red: 0.08, green: 0.33, blue: 0.80)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .clipShape(Circle())
        }
        .padding(18)
        .sectionCard(cornerRadius: 20)
    }

    private var quickCleanCard: some View {
        let selected = viewModel.selectedSummary()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleanup Summary")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                    Text(formatSize(selected.bytes))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(primaryTextColor)
                    Text("Selected reclaimable size from \(selected.count) folders")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tertiaryTextColor)
                }
                Spacer()
                Label(viewModel.isBusy ? "Working" : "Ready", systemImage: viewModel.isBusy ? "clock.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.isBusy ? Color(red: 0.41, green: 0.26, blue: 0.0) : Color(red: 1.0, green: 1.0, blue: 1.0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(viewModel.isBusy
                                ? Color(red: 0.99, green: 0.74, blue: 0.35).opacity(0.72)
                                : Color(red: 0.15, green: 0.73, blue: 0.37).opacity(0.92))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Status")
                    .accessibilityValue(viewModel.isBusy ? "Working" : "Ready")
            }

            HStack {
                Spacer(minLength: 0)
                modePrimaryCircleButton
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .sectionCard(cornerRadius: 20)
    }

    private var homeScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                topHeader
                    .padding(.top, 10)
                homeStorageSection
                quickScanCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .onAppear {
            viewModel.refreshDiskStats()
        }
    }

    private var modeScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                topHeader
                    .padding(.top, 10)
                modeIntroCard
                quickCleanCard
                if viewModel.lastCleanupSummary != nil {
                    cleanupResultsCard
                }
                if viewModel.hasCompletedScan {
                    targetsSection
                } else if !viewModel.targets.isEmpty {
                    scanPromptCard
                }
                activitySection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    private var homeStorageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Storage")
            LazyVGrid(columns: statsColumns, spacing: 8) {
                statChip(title: "Total", value: formatSize(viewModel.diskStats.total), symbol: "internaldrive.fill", color: Color(red: 0.06, green: 0.53, blue: 0.98), shimmering: viewModel.isSilentlyScanning)
                statChip(title: "Used", value: formatSize(viewModel.diskStats.used), symbol: "chart.bar.fill", color: Color(red: 0.96, green: 0.57, blue: 0.20), shimmering: viewModel.isSilentlyScanning)
                statChip(title: "Free", value: formatSize(viewModel.diskStats.free), symbol: "circle.grid.2x2.fill", color: Color(red: 0.18, green: 0.70, blue: 0.39), shimmering: viewModel.isSilentlyScanning)
                statChip(title: "Cache", value: formatSize(viewModel.totalCacheBytes), symbol: "sparkles", color: Color(red: 0.45, green: 0.41, blue: 0.95), shimmering: viewModel.isSilentlyScanning)
            }
            storageDiskChart
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .sectionCard()
    }

    private var storageDiskChart: some View {
        let total = viewModel.diskStats.total
        let used = viewModel.diskStats.used
        let free = viewModel.diskStats.free
        let usedFraction: CGFloat = total > 0 ? CGFloat(Double(used) / Double(total)) : 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("Disk space")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primaryTextColor)
            if total > 0 {
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.18, green: 0.70, blue: 0.39).opacity(0.35))
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.62, blue: 0.28),
                                            Color(red: 0.96, green: 0.47, blue: 0.18)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: w * usedFraction)
                            Spacer(minLength: 0)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(borderColor.opacity(0.5), lineWidth: 1)
                    }
                }
                .frame(height: 28)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Disk usage")
                .accessibilityValue("\(Int(usedFraction * 100)) percent used, \(formatSize(used)) used, \(formatSize(free)) free")
            } else {
                Text("Storage information will appear when disk stats are available.")
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            HStack(spacing: 16) {
                chartLegendDot(color: Color(red: 0.96, green: 0.57, blue: 0.20), title: "Used", value: formatSize(used))
                chartLegendDot(color: Color(red: 0.18, green: 0.70, blue: 0.39), title: "Free", value: formatSize(free))
            }
            .padding(.top, 4)
        }
    }

    private func chartLegendDot(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryTextColor)
            }
        }
    }

    private var quickScanCard: some View {
        HStack {
            Spacer(minLength: 0)
            homeQuickScanCircleButton
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var homeQuickScanCircleButton: some View {
        let diameter: CGFloat = 132
        let topTint = Color(red: 0.26, green: 0.72, blue: 1.00)
        let bottomTint = Color(red: 0.06, green: 0.54, blue: 0.97)
        return Button {
            selectedSidebar = .discovery(.ultraSafe)
            activePrimaryAction = .scan
            Task { await viewModel.scanSizes() }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [topTint, bottomTint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: bottomTint.opacity(0.35), radius: 12, x: 0, y: 6)
                if viewModel.isBusy && activePrimaryAction == .scan {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 32, weight: .bold))
                            .symbolRenderingMode(.hierarchical)
                        Text("Scan")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.98))
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
        .opacity(viewModel.isBusy && activePrimaryAction != .scan ? 0.45 : 1)
        .keyboardShortcut("s", modifiers: [.command])
        .help("Open Ultra Safe mode and scan folders (Cmd+S)")
        .accessibilityLabel("Scan, Ultra Safe mode")
        .accessibilityHint("Opens Ultra Safe and measures reclaimable cache size.")
    }

    private var modePrimaryButtonPhase: ModePrimaryPhase {
        if viewModel.hasCompletedScan && !viewModel.hasCleanedSinceLastScan {
            return .clean
        }
        return viewModel.hasCleanedSinceLastScan ? .scanAgain : .scan
    }

    private var modePrimaryCircleButton: some View {
        let phase = modePrimaryButtonPhase
        let diameter: CGFloat = 132
        let scanTop = Color(red: 0.26, green: 0.72, blue: 1.00)
        let scanBottom = Color(red: 0.06, green: 0.54, blue: 0.97)
        let cleanTop = Color(red: 1.00, green: 0.56, blue: 0.52)
        let cleanBottom = Color(red: 0.90, green: 0.32, blue: 0.31)
        let topTint = phase == .clean ? cleanTop : scanTop
        let bottomTint = phase == .clean ? cleanBottom : scanBottom
        let title = phase == .clean ? "Clean" : (phase == .scanAgain ? "Scan again" : "Scan")
        let symbol = phase == .clean ? "trash.fill" : "arrow.clockwise"
        let isScanning = viewModel.isBusy && activePrimaryAction == .scan
        let isCleaning = viewModel.isBusy && activePrimaryAction == .cleanSelected
        let isRunning = isScanning || isCleaning
        return Button {
            switch phase {
            case .scan, .scanAgain:
                activePrimaryAction = .scan
                Task { await viewModel.scanSizes() }
            case .clean:
                guard canClean else { return }
                showConfirm = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [topTint, bottomTint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: bottomTint.opacity(0.35), radius: 12, x: 0, y: 6)
                if isRunning {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: symbol)
                            .font(.system(size: 32, weight: .bold))
                            .symbolRenderingMode(.hierarchical)
                        Text(title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                    }
                    .foregroundStyle(.white.opacity(0.98))
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy || (phase == .clean && !canClean))
        .keyboardShortcut(phase == .clean ? "k" : "s", modifiers: [.command])
        .help(modePrimaryHelp(phase: phase))
        .accessibilityLabel(title)
        .accessibilityHint(modePrimaryAccessibilityHint(phase: phase))
    }

    private func modePrimaryHelp(phase: ModePrimaryPhase) -> String {
        switch phase {
        case .scan:
            return "Scan folders for reclaimable cache size (Cmd+S)"
        case .clean:
            return "Clean selected folders after confirmation (Cmd+K)"
        case .scanAgain:
            return "Run a fresh scan (Cmd+S)"
        }
    }

    private func modePrimaryAccessibilityHint(phase: ModePrimaryPhase) -> String {
        switch phase {
        case .scan:
            return "Measures reclaimable cache size for this mode."
        case .clean:
            return "Opens confirmation before deleting selected cache folders."
        case .scanAgain:
            return "Starts a new scan after the last cleanup."
        }
    }

    private var primaryTextColor: Color {
        Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        Color.black.opacity(0.72)
    }

    private var tertiaryTextColor: Color {
        Color.black.opacity(0.56)
    }

    private var accentBlue: Color {
        Color(red: 0.12, green: 0.56, blue: 0.98)
    }

    private var toolbarGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.08, green: 0.16, blue: 0.24),
                    Color(red: 0.07, green: 0.12, blue: 0.20)
                ]
                : [
                    Color(red: 0.35, green: 0.70, blue: 0.99),
                    Color(red: 0.56, green: 0.80, blue: 1.00)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        Color.black.opacity(0.16)
    }

    private func statChip(title: String, value: String, symbol: String, color: Color, shimmering: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(color.opacity(0.15))
                    )
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(primaryTextColor.opacity(0.9))
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(minHeight: 76, alignment: .leading)
        .background(Color(red: 0.92, green: 0.95, blue: 0.99).opacity(0.64), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor.opacity(0.78), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
        }
        .overlay {
            if shimmering && !reduceMotion {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0),
                                    .white.opacity(0.18),
                                    .white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: max(proxy.size.width * 0.42, 24))
                        .offset(x: statShimmerSweep ? proxy.size.width : -proxy.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
            }
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Cleanup Targets")
                Spacer()
                Text("\(viewModel.targets.count) folders")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
            }

            HStack(spacing: 7) {
                actionButton("Select All", systemImage: "checklist", tint: Color(red: 0.10, green: 0.56, blue: 0.99), prominent: true) {
                    viewModel.selectAll()
                }
                .disabled(viewModel.isBusy)

                actionButton("Recommended", systemImage: "star.fill", tint: Color(red: 0.48, green: 0.46, blue: 0.95), prominent: true) {
                    viewModel.selectRecommended()
                }
                .disabled(viewModel.isBusy)

                Spacer()

                if viewModel.isBusy {
                    actionButton("Cancel", systemImage: "xmark.circle.fill", tint: .orange) {
                        viewModel.cancelCurrentOperation()
                    }
                }
            }

            Divider()
                .overlay(Color(red: 0.45, green: 0.55, blue: 0.72))

            LazyVStack(spacing: 6) {
                ForEach(viewModel.targets) { target in
                    let isSelected = viewModel.selections[target.id] ?? false
                    LiquidTargetRow(
                        target: target,
                        isOn: Binding(
                            get: { viewModel.selections[target.id] ?? false },
                            set: { viewModel.selections[target.id] = $0 }
                        ),
                        sizeText: formatSize(viewModel.targetSizes[target.id] ?? 0),
                        isSelected: isSelected,
                        isDisabled: viewModel.isBusy
                    )
                }
            }
        }
        .padding(14)
        .sectionCard()
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Activity")
            if viewModel.isBusy, !viewModel.operationProgressLabel.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if viewModel.operationProgress > 0 {
                        ProgressView(value: viewModel.operationProgress)
                            .progressViewStyle(.linear)
                            .tint(Color(red: 0.08, green: 0.53, blue: 0.98))
                    } else {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .leading)
                    }
                    Text(viewModel.operationProgressLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(secondaryTextColor)
                }
            }
            HStack {
                if viewModel.isBusy {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Text(viewModel.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(primaryTextColor)
                    .accessibilityLabel("Activity status")
                    .accessibilityValue(viewModel.statusText)
                Spacer()
                let selected = viewModel.selectedSummary()
                Text("Selected: \(selected.count) (\(formatSize(selected.bytes)))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .accessibilityLabel("Selected folders")
                    .accessibilityValue("\(selected.count), \(formatSize(selected.bytes))")
                Text("Close IDEs before cleaning")
                    .font(.system(size: 10))
                    .foregroundStyle(tertiaryTextColor)
                    .accessibilityLabel("Tip")
                    .accessibilityValue("Close IDEs before cleaning.")
            }
            Text(viewModel.lastOperationReport)
                .font(.system(size: 10))
                .foregroundStyle(secondaryTextColor)
        }
        .padding(14)
        .sectionCard()
    }

    private func sectionTitle(_ title: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(accentBlue)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primaryTextColor)
        }
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        LiquidActionButton(title: title, systemImage: systemImage, tint: tint, prominent: prominent, action: action)
    }
}

private struct LiquidActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let prominent: Bool
    let action: () -> Void
    @State private var isPressed = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: prominent ? 13 : 12, weight: .semibold))
                .padding(.horizontal, prominent ? 8 : 4)
                .padding(.vertical, prominent ? 4 : 2)
        }
        .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.96 : 1.0))
        .brightness(isHovered ? 0.05 : 0)
        .shadow(color: tint.opacity(isHovered ? 0.20 : 0.0), radius: isHovered ? 5 : 0, x: 0, y: isHovered ? 2 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isHovered)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.66), value: isPressed)
        .modifier(LiquidButtonStyleModifier(prominent: prominent))
        .tint(tint)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in isPressed = true }
            .onEnded { _ in isPressed = false }
        )
    }
}

private struct LiquidTargetRow: View {
    let target: CacheTarget
    @Binding var isOn: Bool
    let sizeText: String
    let isSelected: Bool
    let isDisabled: Bool
    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.90))
                    Text(target.pathPattern)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.56))
                    Text(target.inclusionReason)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.62))
                }
            }
            .toggleStyle(.checkbox)
            .disabled(isDisabled)

            Spacer()

            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.08, green: 0.56, blue: 0.99))
                }
                Text(sizeText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.84))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                            ? Color(red: 0.16, green: 0.45, blue: 0.84).opacity(0.9)
                            : Color.black.opacity(0.10),
                            lineWidth: 1
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.55 : 0.35), lineWidth: 0.5)
                )
        )
    }
}

private extension View {
    func sectionCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(SectionCardModifier(cornerRadius: cornerRadius))
    }
}

private struct SectionCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.90, green: 0.93, blue: 0.97).opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.16), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(0.12),
                radius: 9,
                x: 0,
                y: 5
            )
    }
}

private struct LiquidButtonStyleModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private extension View {
    /// Removes the split-view sidebar toggle from the window toolbar (macOS 14+). Older systems rely on pinned column visibility.
    @ViewBuilder
    func hideSidebarToggleIfAvailable() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

/// Hides the system sidebar toggle when SwiftUI's `toolbar(removing:)` is unavailable (macOS 13).
private func suppressNavigationSplitSidebarToolbarToggleIfNeeded() {
    if #available(macOS 14.0, *) { return }
    DispatchQueue.main.async {
        for window in NSApp.windows {
            window.toolbar?.items.forEach { item in
                let id = item.itemIdentifier.rawValue
                guard id.localizedCaseInsensitiveContains("sidebar") else { return }
                item.view?.isHidden = true
                item.menuFormRepresentation?.view?.isHidden = true
            }
        }
    }
}

private enum PrimaryAction: Hashable {
    case scan
    case cleanSelected
}

private enum ModePrimaryPhase {
    case scan
    case clean
    case scanAgain
}
