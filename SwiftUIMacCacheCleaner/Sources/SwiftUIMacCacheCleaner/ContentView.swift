import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: CacheCleanerViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConfirm = false
    @State private var pressedPrimaryAction: PrimaryAction?
    @State private var activePrimaryAction: PrimaryAction?
    @State private var animatedGaugeRatio: Double = 0
    @State private var gaugePulse: Bool = false
    @State private var gaugeShine: Bool = false
    @State private var statShimmerSweep: Bool = false
    @State private var hoveredPrimaryAction: PrimaryAction?
    @Namespace private var modeSegmentAnimation
    private let statsColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ZStack(alignment: .top) {
            appBackground

            // Subtle top chrome so content transitions cleanly below title bar.
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

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    topHeader
                    .padding(.top, 10)
                    quickCleanCard
                    dashboardSection
                    targetsSection
                    activitySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
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
                pressedPrimaryAction = nil
            }
        }
        .onAppear {
            animatedGaugeRatio = diskUsageRatio
            if !reduceMotion {
                withAnimation(.linear(duration: 1.45).repeatForever(autoreverses: false)) {
                    statShimmerSweep = true
                }
            }
        }
        .onChange(of: diskUsageRatio) { value in
            if reduceMotion {
                animatedGaugeRatio = value
            } else {
                withAnimation(.easeInOut(duration: 0.45)) {
                    animatedGaugeRatio = value
                }
            }
        }
        .onChange(of: activePrimaryAction) { action in
            if action == .scan {
                gaugePulse = false
                gaugeShine = false
            }
        }
        .onChange(of: viewModel.isBusy) { isBusy in
            guard !isBusy, activePrimaryAction == .scan else { return }
            triggerGaugeCompletionAnimation()
        }
        .toolbarBackground(toolbarGradient, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(colorScheme, for: .windowToolbar)
        .preferredColorScheme(.light)
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
                cleanerGauge(usedRatio: animatedGaugeRatio)

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

            HStack(spacing: 12) {
                segmentedActionButton(
                    .scan,
                    title: "Scan",
                    systemImage: "arrow.clockwise",
                    topTint: Color(red: 0.26, green: 0.72, blue: 1.00),
                    bottomTint: Color(red: 0.06, green: 0.54, blue: 0.97)
                ) {
                    activePrimaryAction = .scan
                    Task { await viewModel.scanSizes() }
                }
                segmentedActionButton(
                    .dryRun,
                    title: "Dry Run",
                    systemImage: "eye.fill",
                    topTint: Color(red: 0.43, green: 0.66, blue: 1.00),
                    bottomTint: Color(red: 0.21, green: 0.45, blue: 0.91)
                ) {
                    activePrimaryAction = .dryRun
                    Task { await viewModel.dryRunSelected() }
                }
                segmentedActionButton(
                    .cleanSelected,
                    title: "Clean",
                    systemImage: "trash.fill",
                    topTint: Color(red: 1.00, green: 0.56, blue: 0.52),
                    bottomTint: Color(red: 0.90, green: 0.32, blue: 0.31)
                ) {
                    showConfirm = true
                }
            }

        }
        .padding(14)
        .sectionCard(cornerRadius: 20)
    }

    private var diskUsageRatio: Double {
        guard viewModel.diskStats.total > 0 else { return 0 }
        return min(max(Double(viewModel.diskStats.used) / Double(viewModel.diskStats.total), 0), 1)
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

    @ViewBuilder
    private func cleanerGauge(usedRatio: Double) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.24, green: 0.66, blue: 1.0).opacity(gaugePulse ? 0.18 : 0))
                    .scaleEffect(gaugePulse ? 1.12 : 0.92)
                    .frame(width: 126, height: 126)
                    .animation(.easeOut(duration: 0.75), value: gaugePulse)

                Circle()
                    .stroke(Color(red: 0.85, green: 0.90, blue: 0.97), lineWidth: 12)
                    .frame(width: 116, height: 116)

                Circle()
                    .trim(from: 0, to: usedRatio)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.08, green: 0.53, blue: 0.98),
                                Color(red: 0.31, green: 0.40, blue: 0.95),
                                Color(red: 0.11, green: 0.70, blue: 0.53)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 116, height: 116)

                VStack(spacing: 2) {
                    Text("\(Int(usedRatio * 100))%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.13, green: 0.25, blue: 0.47))
                    Text("Used")
                        .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.29, green: 0.40, blue: 0.57))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 58, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0),
                                .white.opacity(0.55),
                                .white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 18, height: 110)
                    .rotationEffect(.degrees(20))
                    .offset(x: gaugeShine ? 72 : -72)
                    .opacity(gaugeShine ? 0.9 : 0)
                    .blendMode(.screen)
                    .animation(.easeInOut(duration: 0.65), value: gaugeShine)
                    .clipped()
            }
            .frame(width: 132, height: 132)

            VStack(spacing: 1) {
                Text("Junk Files")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.23, green: 0.35, blue: 0.53))
                Text(formatSize(viewModel.totalCacheBytes))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.14, green: 0.29, blue: 0.49))
            }
        }
    }

    private func triggerGaugeCompletionAnimation() {
        guard !reduceMotion else { return }
        gaugePulse = true
        gaugeShine = false
        withAnimation(.easeInOut(duration: 0.15)) {
            gaugeShine = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            gaugeShine = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            gaugePulse = false
        }
    }

    private var heroSection: some View {
        EmptyView()
    }

    private var dashboardSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Storage")
                LazyVGrid(columns: statsColumns, spacing: 8) {
                    statChip(title: "Total", value: formatSize(viewModel.diskStats.total), symbol: "internaldrive.fill", color: Color(red: 0.06, green: 0.53, blue: 0.98), shimmering: viewModel.isSilentlyScanning)
                    statChip(title: "Used", value: formatSize(viewModel.diskStats.used), symbol: "chart.bar.fill", color: Color(red: 0.96, green: 0.57, blue: 0.20), shimmering: viewModel.isSilentlyScanning)
                    statChip(title: "Free", value: formatSize(viewModel.diskStats.free), symbol: "circle.grid.2x2.fill", color: Color(red: 0.18, green: 0.70, blue: 0.39), shimmering: viewModel.isSilentlyScanning)
                    statChip(title: "Cache", value: formatSize(viewModel.totalCacheBytes), symbol: "sparkles", color: Color(red: 0.45, green: 0.41, blue: 0.95), shimmering: viewModel.isSilentlyScanning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(height: 144, alignment: .top)
            .sectionCard()

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Mode")
                discoveryModeSegmentedControl
                Text(viewModel.discoveryModeDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: 380, alignment: .leading)
            .padding(12)
            .frame(height: 144, alignment: .top)
            .sectionCard()
        }
    }

    private var discoveryModeSegmentedControl: some View {
        HStack(spacing: 6) {
            modeSegmentButton(.ultraSafe, label: "Ultra Safe")
            modeSegmentButton(.strict, label: "Strict")
            modeSegmentButton(.balanced, label: "Balanced")
            modeSegmentButton(.developerDeepClean, label: "Dev Deep")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(red: 0.91, green: 0.94, blue: 0.98).opacity(0.66))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 2, x: 0, y: 1)
        )
    }

    private func keyEquivalent(for actionID: PrimaryAction) -> KeyEquivalent {
        switch actionID {
        case .scan: return "s"
        case .dryRun: return "p"
        case .cleanSelected: return "k"
        }
    }

    private func helpText(for actionID: PrimaryAction) -> String {
        switch actionID {
        case .scan:
            return "Scan folders for reclaimable cache size (Cmd+S)"
        case .dryRun:
            return "Preview what cleanup would remove (Cmd+P)"
        case .cleanSelected:
            return "Open confirmation before deleting selected items (Cmd+K)"
        }
    }

    private func accessibilityHint(for actionID: PrimaryAction) -> String {
        switch actionID {
        case .scan:
            return "Refreshes reclaimable size."
        case .dryRun:
            return "Shows what would be cleaned."
        case .cleanSelected:
            return "Opens confirmation before cleaning."
        }
    }

    private func sortPriority(for actionID: PrimaryAction) -> Double {
        switch actionID {
        case .scan:
            return 300
        case .dryRun:
            return 290
        case .cleanSelected:
            return 280
        }
    }

    private func modeAccessibilityLabel(for mode: CacheCleanerViewModel.DiscoveryMode, label: String) -> String {
        if viewModel.discoveryMode == mode {
            return "\(label), selected"
        }
        return label
    }

    private func modeSegmentButton(_ mode: CacheCleanerViewModel.DiscoveryMode, label: String) -> some View {
        let isSelected = viewModel.discoveryMode == mode
        return Button {
            if reduceMotion {
                viewModel.updateDiscoveryMode(mode, silentlyScan: true)
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewModel.updateDiscoveryMode(mode, silentlyScan: true)
                }
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : secondaryTextColor)
                .frame(maxWidth: .infinity, minHeight: 34)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.clear)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(accentBlue)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                                    .shadow(color: Color(red: 0.06, green: 0.29, blue: 0.65).opacity(0.18), radius: 3, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "modeSegmentSelection", in: modeSegmentAnimation)
                            }
                        }
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
        .help("Switch discovery mode to \(label)")
        .accessibilityLabel(modeAccessibilityLabel(for: mode, label: label))
        .accessibilityHint("Sets folder scanning strictness.")
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

    private var segmentedPrimaryActions: some View {
        EmptyView()
    }

    private var separatorLine: some View {
        EmptyView()
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

    private func segmentedActionButton(_ actionID: PrimaryAction, title: String, systemImage: String, topTint: Color, bottomTint: Color, action: @escaping () -> Void) -> some View {
        let isRunning = viewModel.isBusy && activePrimaryAction == actionID
        let isPressed = pressedPrimaryAction == actionID
        let isHovered = hoveredPrimaryAction == actionID
        let fillOpacity = isRunning ? 0.93 : 1.0
        return Button(action: action) {
            HStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .scaleEffect(0.92)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.98))
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                topTint.opacity(fillOpacity),
                                bottomTint.opacity(fillOpacity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(isHovered ? 0.20 : 0.10), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.08 : 0.04),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
        }
        .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.96 : 1.0))
        .shadow(color: bottomTint.opacity(isHovered ? 0.28 : 0.18), radius: isHovered ? 8 : 5, x: 0, y: isHovered ? 4 : 2)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isHovered)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.66), value: isPressed)
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
        .keyboardShortcut(keyEquivalent(for: actionID), modifiers: [.command])
        .help(helpText(for: actionID))
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint(for: actionID))
        .accessibilityValue(isRunning ? "Running" : "Idle")
        .accessibilitySortPriority(sortPriority(for: actionID))
        .onHover { hovering in
            hoveredPrimaryAction = hovering ? actionID : nil
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressedPrimaryAction = actionID }
            .onEnded { _ in pressedPrimaryAction = nil }
        )
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

private enum PrimaryAction: Hashable {
    case scan
    case dryRun
    case cleanSelected
}
