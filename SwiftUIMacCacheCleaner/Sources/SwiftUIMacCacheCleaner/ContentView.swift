import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: CacheCleanerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConfirm = false
    @State private var activePrimaryAction: PrimaryAction?
    /// Drives the custom sidebar; includes Home plus discovery modes.
    @State private var selectedSidebar: CacheCleanerViewModel.SidebarDestination = .home
    /// Keeps the sidebar open; paired with `hideSidebarToggleIfAvailable()`.
    @State private var splitViewColumnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("safetyDisclaimerDoNotShowAgain") private var safetyDisclaimerDoNotShowAgain = false
    @State private var showSafetyDisclaimerSheet = false
    private let statsColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    private var canClean: Bool {
        viewModel.hasCompletedScan && viewModel.selectedSummary().count > 0
    }

    /// Scan/cleanup/target edits while a scan or discovery is in progress.
    private var blocksHeavyActions: Bool {
        viewModel.isBusy || viewModel.isDiscoveringTargets
    }

    private var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (s?, b?) where s != b:
            return "v\(s) (\(b))"
        case let (s?, _):
            return "v\(s)"
        case let (_, b?):
            return "v\(b)"
        default:
            return "Version unavailable"
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewColumnVisibility) {
            VStack(alignment: .leading, spacing: 4) {
                sidebarRow(title: "Home", symbol: "house.fill", destination: .home)
                ForEach(CacheCleanerViewModel.DiscoveryMode.allCases) { mode in
                    sidebarRow(
                        title: mode.sidebarLabel,
                        symbol: mode.sidebarSystemImage,
                        destination: .discovery(mode)
                    )
                }
                sidebarRow(title: "About", symbol: "info.circle.fill", destination: .about)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.08, blue: 0.19),
                            Color(red: 0.08, green: 0.09, blue: 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Rectangle()
                        .fill(Material.ultraThinMaterial)
                }
                // Fills behind title-bar safe area so the system’s rounded sidebar mask doesn’t show a separate “band” at the top.
                .ignoresSafeArea(edges: [.top, .leading, .bottom])
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .navigationTitle("")
            .hideSidebarToggleIfAvailable()
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
                            colors: [
                                Color(red: 0.28, green: 0.17, blue: 0.46).opacity(0.30),
                                Color.clear
                            ],
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
                    case .about:
                        aboutScrollContent
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
            Text(cleanupConfirmationMessage)
        }
        .onChange(of: viewModel.isBusy) { isBusy in
            if isBusy == false {
                activePrimaryAction = nil
            }
        }
        .toolbarBackground(toolbarGradient, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSafetyDisclaimerSheet) {
            safetyDisclaimerLaunchSheet
        }
        .onAppear {
            if !safetyDisclaimerDoNotShowAgain {
                showSafetyDisclaimerSheet = true
            }
        }
    }

    private func sidebarRow(
        title: String,
        symbol: String,
        destination: CacheCleanerViewModel.SidebarDestination
    ) -> some View {
        let isSelected = selectedSidebar == destination
        return Button {
            guard !viewModel.isBusy else { return }
            selectedSidebar = destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18, alignment: .center)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.52, green: 0.35, blue: 0.78),
                                    Color(red: 0.38, green: 0.25, blue: 0.58)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    private var safetyDisclaimerLaunchSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before you clean")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            ScrollView {
                Text(modeSafetyDisclaimer)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            Toggle("Do not show this message again", isOn: $safetyDisclaimerDoNotShowAgain)
                .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Continue") {
                    showSafetyDisclaimerSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
        .frame(maxWidth: 560)
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
                        .overlay(Color.white.opacity(0.18))
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
                colors: [
                    Color(red: 0.14, green: 0.10, blue: 0.26),
                    Color(red: 0.10, green: 0.13, blue: 0.28),
                    Color(red: 0.08, green: 0.11, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color(red: 0.40, green: 0.25, blue: 0.60).opacity(0.36),
                    Color(red: 0.18, green: 0.34, blue: 0.68).opacity(0.24),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.50, green: 0.35, blue: 0.88).opacity(0.20))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -260, y: -250)

            Circle()
                .fill(Color(red: 0.28, green: 0.52, blue: 0.98).opacity(0.18))
                .frame(width: 510, height: 510)
                .blur(radius: 130)
                .offset(x: 230, y: -120)

            Circle()
                .fill(Color(red: 0.60, green: 0.42, blue: 0.94).opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: 120, y: 280)
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
            headerBrandMark
        }
        .padding(18)
        .sectionCard(cornerRadius: 20)
    }

    /// Rounded-square frame with glowing accent ring (matches README mockup styling).
    private var headerBrandMark: some View {
        let side: CGFloat = 64
        let corner: CGFloat = 16
        return ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.black.opacity(0.42))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.62, green: 0.45, blue: 0.98),
                            Color(red: 0.32, green: 0.52, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .shadow(color: Color(red: 0.55, green: 0.38, blue: 0.95).opacity(0.55), radius: 10, x: 0, y: 0)
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
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
                Label(
                    viewModel.isDiscoveringTargets ? "Discovering…" : (viewModel.isBusy ? "Working" : "Ready"),
                    systemImage: viewModel.isDiscoveringTargets ? "ellipsis.circle" : (viewModel.isBusy ? "clock.fill" : "checkmark.circle.fill")
                )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(blocksHeavyActions ? Color(red: 0.15, green: 0.08, blue: 0.04) : Color.white.opacity(0.96))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(blocksHeavyActions
                                ? Color(red: 0.98, green: 0.72, blue: 0.38).opacity(0.88)
                                : Color(red: 0.22, green: 0.65, blue: 0.48).opacity(0.92))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Status")
                    .accessibilityValue(viewModel.isDiscoveringTargets ? "Discovering folders" : (viewModel.isBusy ? "Working" : "Ready"))
            }
            Text("If you are unsure, use Actions → Dry Run (⌘P) before clearing. Deselect any path you do not recognize.")
                .font(.system(size: 11))
                .foregroundStyle(tertiaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .sectionCard(cornerRadius: 20)
    }

    private var modePrimaryActionCard: some View {
        HStack {
            Spacer(minLength: 0)
            modePrimaryCircleButton
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
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

    private var aboutScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                topHeader
                    .padding(.top, 10)
                aboutDetailsCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    private var aboutDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("About this app")
                Spacer()
                Text(appVersionText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tertiaryTextColor)
            }
            Text(aboutAppIntro)
                .font(.system(size: 13))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
                .overlay(Color.white.opacity(0.14))
            sectionTitle("What you can do")
            Text(aboutFeaturesList)
                .font(.system(size: 13))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
                .overlay(Color.white.opacity(0.14))
            sectionTitle("Safety")
            Text(aboutSafetyBlurb)
                .font(.system(size: 12))
                .foregroundStyle(tertiaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .sectionCard(cornerRadius: 20)
    }

    private var aboutAppIntro: String {
        """
        Mac Cache Cleaner is a native macOS app that helps you free disk space by finding and clearing cache, log, and temporary data under safe, allowlisted locations in your home folder.

        It discovers folders dynamically as your system changes, shows how much space each target uses, and lets you scan, preview with Dry Run, and clear only what you select.
        """
    }

    private var aboutFeaturesList: String {
        """
        • Home: see disk usage and start a quick scan in Ultra Safe mode.

        • Ultra Safe, Strict, Balanced, and Developer Deep Clean: increasing scope—from user caches only up to optional developer tool caches.

        • Each target explains why it is included. Cleanup removes files inside selected folders only, not the folders themselves.
        """
    }

    private var aboutSafetyBlurb: String {
        """
        The app does not scan your entire disk or target Documents, Desktop, or arbitrary projects. No tool can guarantee that every file in a cache or toolchain folder is safe for you to lose—use Dry Run (⌘P) and deselect paths you do not recognize.
        """
    }

    private var modeScrollContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                topHeader
                    .padding(.top, 10)
                modeIntroCard
                if viewModel.hasCompletedScan {
                    quickCleanCard
                }
                if viewModel.lastCleanupSummary != nil, viewModel.hasCompletedScan {
                    cleanupResultsCard
                }
                modePrimaryActionCard
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
                StatChipView(title: "Total", value: formatSize(viewModel.diskStats.total), symbol: "internaldrive.fill", color: Color(red: 0.06, green: 0.53, blue: 0.98), shimmering: viewModel.isSilentlyScanning)
                StatChipView(title: "Used", value: formatSize(viewModel.diskStats.used), symbol: "chart.bar.fill", color: Color(red: 0.96, green: 0.57, blue: 0.20), shimmering: viewModel.isSilentlyScanning)
                StatChipView(title: "Free", value: formatSize(viewModel.diskStats.free), symbol: "circle.grid.2x2.fill", color: Color(red: 0.18, green: 0.70, blue: 0.39), shimmering: viewModel.isSilentlyScanning)
                StatChipView(title: "Cache", value: formatSize(viewModel.totalCacheBytes), symbol: "sparkles", color: Color(red: 0.45, green: 0.41, blue: 0.95), shimmering: viewModel.isSilentlyScanning)
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
        let topTint = Color(red: 0.58, green: 0.45, blue: 0.99)
        let bottomTint = Color(red: 0.22, green: 0.52, blue: 0.98)
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
        .disabled(blocksHeavyActions)
        .opacity(blocksHeavyActions && activePrimaryAction != .scan ? 0.45 : 1)
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
        let scanTop = Color(red: 0.58, green: 0.45, blue: 0.99)
        let scanBottom = Color(red: 0.22, green: 0.52, blue: 0.98)
        let cleanTop = Color(red: 1.00, green: 0.62, blue: 0.58)
        let cleanBottom = Color(red: 0.94, green: 0.42, blue: 0.40)
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
        .disabled(blocksHeavyActions || (phase == .clean && !canClean))
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
            return "Opens confirmation before deleting files inside selected folders. No tool can guarantee you will never lose data you still care about; use Dry Run first if unsure."
        case .scanAgain:
            return "Starts a new scan after the last cleanup."
        }
    }

    private var modeSafetyDisclaimer: String {
        """
        Cleanup removes files inside the folders you select. This app targets allowlisted cache, log, temp, and (in developer modes) toolchain locations—not your Documents, Desktop, or arbitrary project folders.

        No cleaner can promise that every file under a cache or tool folder is expendable for you. Developer modes may remove large downloads or build outputs you would need to fetch or rebuild. Use Actions → Dry Run (⌘P) first, read each path’s note, and deselect anything unfamiliar.
        """
    }

    private var cleanupConfirmationMessage: String {
        """
        This will delete files inside the selected folders only (not the folders themselves).

        Locations are restricted by the current mode, but no app can guarantee that a cache or toolchain folder never contains something you still need. Balanced and Developer modes can clear more aggressive targets.

        Use Actions → Dry Run (⌘P) if you want a preview first. This cannot be undone.
        """
    }

    private var primaryTextColor: Color {
        Color.white.opacity(0.94)
    }

    private var secondaryTextColor: Color {
        Color.white.opacity(0.72)
    }

    private var tertiaryTextColor: Color {
        Color.white.opacity(0.52)
    }

    private var accentBlue: Color {
        Color(red: 0.62, green: 0.56, blue: 1.0)
    }

    private var toolbarGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.09, blue: 0.22),
                Color(red: 0.10, green: 0.11, blue: 0.24)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        Color.white.opacity(0.14)
    }

    /// True when every target is selected (matches “Select All”).
    private var selectionMatchesSelectAll: Bool {
        guard !viewModel.targets.isEmpty else { return false }
        return viewModel.targets.allSatisfy { viewModel.selections[$0.id] == true }
    }

    /// True when each row matches its recommended default (matches “Recommended”).
    private var selectionMatchesRecommended: Bool {
        guard !viewModel.targets.isEmpty else { return false }
        return viewModel.targets.allSatisfy { (viewModel.selections[$0.id] ?? false) == $0.enabledByDefault }
    }

    /// True when no target is currently selected (matches “Deselect All”).
    private var selectionMatchesNone: Bool {
        guard !viewModel.targets.isEmpty else { return false }
        return viewModel.targets.allSatisfy { viewModel.selections[$0.id] != true }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Cleanup Targets")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(viewModel.targets.count) folders")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                }
            }

            HStack(spacing: 7) {
                actionButton(
                    "Select All",
                    systemImage: "checklist",
                    tint: Color(red: 0.18, green: 0.60, blue: 0.99),
                    prominent: true,
                    isActive: selectionMatchesSelectAll
                ) {
                    viewModel.selectAll()
                }
                .disabled(blocksHeavyActions)

                actionButton(
                    "Recommended",
                    systemImage: "star.fill",
                    tint: Color(red: 0.54, green: 0.52, blue: 0.97),
                    prominent: true,
                    isActive: selectionMatchesRecommended
                ) {
                    viewModel.selectRecommended()
                }
                .disabled(blocksHeavyActions)

                actionButton(
                    "Deselect All",
                    systemImage: "minus.circle.fill",
                    tint: Color(red: 0.72, green: 0.45, blue: 0.91),
                    prominent: true,
                    isActive: selectionMatchesNone
                ) {
                    viewModel.deselectAll()
                }
                .disabled(blocksHeavyActions)

                Spacer()

                if viewModel.isBusy {
                    actionButton("Cancel", systemImage: "xmark.circle.fill", tint: .orange) {
                        viewModel.cancelCurrentOperation()
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.16))

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
                        isDisabled: blocksHeavyActions
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
                            .tint(Color(red: 0.56, green: 0.52, blue: 1.0))
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
                Text("Selected: \(selected.count) folders • \(selected.items) files • \(formatSize(selected.bytes))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .accessibilityLabel("Selected targets")
                    .accessibilityValue("\(selected.count) folders, \(selected.items) files, \(formatSize(selected.bytes))")
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

    private func actionButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        prominent: Bool = false,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        LiquidActionButton(
            title: title,
            systemImage: systemImage,
            tint: tint,
            prominent: prominent,
            isActive: isActive,
            action: action
        )
    }
}

/// Home stat tiles; keeps shimmer animation state local so a repeating animation does not invalidate the whole `ContentView` every frame (which made scrolling feel janky).
private struct StatChipView: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    let shimmering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerSweep = false

    private var labelColor: Color { Color.white.opacity(0.94) }
    private var borderColor: Color { Color.white.opacity(0.14) }

    var body: some View {
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
                    .foregroundStyle(labelColor.opacity(0.9))
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(minHeight: 76, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.08, blue: 0.20).opacity(0.55))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Material.ultraThinMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor.opacity(0.9), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .overlay {
            if shimmering && !reduceMotion {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0),
                                    .white.opacity(0.12),
                                    .white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: max(proxy.size.width * 0.42, 24))
                        .offset(x: shimmerSweep ? proxy.size.width : -proxy.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
            }
        }
        .onAppear { syncShimmerAnimation() }
        .onChange(of: shimmering) { _ in syncShimmerAnimation() }
        .onChange(of: reduceMotion) { _ in syncShimmerAnimation() }
    }

    private func syncShimmerAnimation() {
        if shimmering && !reduceMotion {
            shimmerSweep = false
            withAnimation(.linear(duration: 1.45).repeatForever(autoreverses: false)) {
                shimmerSweep = true
            }
        } else {
            shimmerSweep = false
        }
    }
}

private struct LiquidActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let prominent: Bool
    /// When `prominent`, reflects whether the current app state matches this preset (filled vs outline).
    var isActive: Bool = false
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
        .opacity(prominent && !isActive ? 0.78 : 1.0)
        .shadow(color: tint.opacity(isHovered ? 0.20 : 0.0), radius: isHovered ? 5 : 0, x: 0, y: isHovered ? 2 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isHovered)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.66), value: isPressed)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isActive)
        .modifier(LiquidButtonStyleModifier(prominent: prominent, isActive: isActive))
        .tint(tint)
        .accessibilityAddTraits(isActive && prominent ? .isSelected : [])
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
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text(target.pathPattern)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.48))
                    Text(target.inclusionReason)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .toggleStyle(.checkbox)
            .disabled(isDisabled)

            Spacer()

            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 1.0))
                }
                Text(sizeText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.15, green: 0.12, blue: 0.25).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                            ? Color(red: 0.52, green: 0.45, blue: 0.98).opacity(0.82)
                            : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.14 : 0.06), lineWidth: 0.5)
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
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(red: 0.12, green: 0.08, blue: 0.22).opacity(0.42))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Material.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(0.28),
                radius: 12,
                x: 0,
                y: 6
            )
    }
}

private struct LiquidButtonStyleModifier: ViewModifier {
    let prominent: Bool
    let isActive: Bool

    func body(content: Content) -> some View {
        if prominent {
            if isActive {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
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
