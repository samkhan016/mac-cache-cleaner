import Foundation

@MainActor
final class CacheCleanerViewModel: ObservableObject {
    /// Sidebar rows: Home plus each discovery mode.
    enum SidebarDestination: Hashable {
        case home
        case discovery(DiscoveryMode)
    }

    enum DiscoveryMode: String, CaseIterable, Identifiable {
        case ultraSafe = "Ultra Safe"
        case strict = "Strict"
        case balanced = "Balanced"
        case developerDeepClean = "Developer Deep Clean"

        var id: String { rawValue }

        var sidebarLabel: String {
            switch self {
            case .ultraSafe: return "Ultra Safe"
            case .strict: return "Strict"
            case .balanced: return "Balanced"
            case .developerDeepClean: return "Dev Deep"
            }
        }

        var sidebarSystemImage: String {
            switch self {
            case .ultraSafe: return "shield.checkered"
            case .strict: return "lock.shield"
            case .balanced: return "circle.grid.2x2"
            case .developerDeepClean: return "hammer"
            }
        }
    }

    private struct ModeWorkspace: Equatable {
        var targets: [CacheTarget]
        var selections: [String: Bool]
        var targetSizes: [String: Int64]
        var totalCacheBytes: Int64
        var hasCompletedScan: Bool
        /// After a successful cleanup (until the user runs a visible scan again).
        var hasCleanedSinceLastScan: Bool
        var lastOperationReport: String
        var statusText: String
        var lastCleanupSummary: CleanupSummary?
    }

    @Published var discoveryMode: DiscoveryMode = .ultraSafe
    @Published var targets: [CacheTarget] = []
    @Published var selections: [String: Bool] = [:]
    @Published var targetSizes: [String: Int64] = [:]
    @Published var statusText: String = "Ready"
    @Published var lastOperationReport: String = "No cleanup run yet."
    @Published var isBusy: Bool = false
    @Published var operationProgress: Double = 0
    @Published var operationProgressLabel: String = ""
    @Published var diskStats: DiskStats = DiskStats(total: 0, used: 0, free: 0)
    @Published var totalCacheBytes: Int64 = 0
    @Published var isSilentlyScanning: Bool = false
    @Published var hasCompletedScan: Bool = false
    @Published var hasCleanedSinceLastScan: Bool = false
    @Published var lastCleanupSummary: CleanupSummary?

    private var workspaces: [DiscoveryMode: ModeWorkspace] = [:]

    private enum OperationOutcome {
        case cancelled
        case scan(sizes: [String: Int64], total: Int64, diskStats: DiskStats)
        case cleanup(itemsDeleted: Int, itemsFailed: Int, inaccessibleFolders: Int, unsafeFolders: Int, freedBytes: Int64)
        case dryRun(itemsEstimated: Int, inaccessibleFolders: Int, unsafeFolders: Int, estimatedFreed: Int64)
    }

    private var activeOperation: Task<OperationOutcome, Never>?
    private var activeOperationID: UUID?

    func refreshDiskStats() {
        diskStats = Self.getDiskStats()
    }

    init() {
        diskStats = Self.getDiskStats()
        refreshTargets()
        if targets.isEmpty {
            statusText = "No known cache folders were found on this Mac."
        } else {
            statusText = "Ready"
        }
    }

    func selectDiscoveryMode(_ mode: DiscoveryMode) {
        guard !isBusy else { return }
        guard discoveryMode != mode else { return }
        persistCurrentWorkspace()
        discoveryMode = mode
        if let existing = workspaces[mode] {
            applyWorkspace(existing)
        } else {
            refreshTargets()
            hasCompletedScan = false
            hasCleanedSinceLastScan = false
            lastCleanupSummary = nil
            lastOperationReport = "No cleanup run yet."
            if targets.isEmpty {
                statusText = "No safe cache folders found for \(discoveryMode.rawValue.lowercased()) mode."
                totalCacheBytes = 0
            } else {
                statusText = "Ready"
            }
        }
    }

    private func persistCurrentWorkspace() {
        workspaces[discoveryMode] = ModeWorkspace(
            targets: targets,
            selections: selections,
            targetSizes: targetSizes,
            totalCacheBytes: totalCacheBytes,
            hasCompletedScan: hasCompletedScan,
            hasCleanedSinceLastScan: hasCleanedSinceLastScan,
            lastOperationReport: lastOperationReport,
            statusText: statusText,
            lastCleanupSummary: lastCleanupSummary
        )
    }

    private func applyWorkspace(_ workspace: ModeWorkspace) {
        targets = workspace.targets
        selections = workspace.selections
        targetSizes = workspace.targetSizes
        totalCacheBytes = workspace.totalCacheBytes
        hasCompletedScan = workspace.hasCompletedScan
        hasCleanedSinceLastScan = workspace.hasCleanedSinceLastScan
        lastOperationReport = workspace.lastOperationReport
        statusText = workspace.statusText
        lastCleanupSummary = workspace.lastCleanupSummary
    }

    var discoveryModeDescription: String {
        switch discoveryMode {
        case .ultraSafe:
            return "Ultra Safe cleans only ~/Library/Caches and is best for quick low-risk cleanup."
        case .strict:
            return "Strict adds app container cache locations and conservative Xcode/Simulator cache roots."
        case .balanced:
            return "Balanced includes Strict plus common logs and temporary folders for broader cleanup."
        case .developerDeepClean:
            return "Developer Deep Clean includes Balanced plus optional developer tool caches (for example Xcode, Android/Gradle, JetBrains, Node, and Python)."
        }
    }

    func selectAll() {
        for target in targets {
            selections[target.id] = true
        }
        statusText = "All targets selected."
    }

    func selectRecommended() {
        for target in targets {
            selections[target.id] = target.enabledByDefault
        }
        statusText = "Recommended targets selected."
    }

    func selectedTargets() -> [CacheTarget] {
        targets.filter { selections[$0.id] == true }
    }

    func selectedSummary() -> (count: Int, bytes: Int64) {
        let selected = selectedTargets()
        let bytes = selected.reduce(Int64(0)) { partial, target in
            partial + (targetSizes[target.id] ?? 0)
        }
        return (selected.count, bytes)
    }

    func cancelCurrentOperation() {
        guard isBusy else { return }
        activeOperation?.cancel()
        activeOperation = nil
        activeOperationID = nil
        isBusy = false
        operationProgress = 0
        operationProgressLabel = ""
        statusText = "Operation cancelled."
        lastOperationReport = "Last operation was cancelled."
    }

    func scanSizes(showProgressUI: Bool = true) async {
        let modeForOperation = discoveryMode
        isSilentlyScanning = !showProgressUI
        if showProgressUI {
            cancelCurrentOperation()
        } else {
            activeOperation?.cancel()
            activeOperation = nil
            activeOperationID = nil
            operationProgress = 0
            operationProgressLabel = ""
        }
        guard discoveryMode == modeForOperation else { return }
        guard !targets.isEmpty else {
            totalCacheBytes = 0
            diskStats = Self.getDiskStats()
            isSilentlyScanning = false
            if showProgressUI {
                statusText = "No known cache folders were found on this Mac."
            }
            return
        }
        if showProgressUI {
            isBusy = true
            statusText = "Scanning cache sizes..."
        }
        let targetsSnapshot = targets
        let operationID = UUID()
        activeOperationID = operationID

        let operation = Task.detached(priority: .userInitiated) { () -> OperationOutcome in
            var localSizes: [String: Int64] = [:]
            var localTotal: Int64 = 0
            for target in targetsSnapshot {
                if Task.isCancelled { return .cancelled }
                let resolved = Self.resolvePaths(pattern: target.pathPattern)
                var size: Int64 = 0
                for path in resolved {
                    if Task.isCancelled { return .cancelled }
                    size += Self.sizeOfPath(path)
                }
                localSizes[target.id] = size
                localTotal += size
            }
            if Task.isCancelled { return .cancelled }
            return .scan(sizes: localSizes, total: localTotal, diskStats: Self.getDiskStats())
        }
        activeOperation = operation
        let outcome = await operation.value

        guard activeOperationID == operationID else { return }
        guard discoveryMode == modeForOperation else { return }
        activeOperation = nil
        activeOperationID = nil

        switch outcome {
        case .cancelled:
            isSilentlyScanning = false
            if showProgressUI {
                statusText = "Scan cancelled."
                lastOperationReport = "Scan was cancelled before completion."
            }
        case let .scan(sizes, total, stats):
            targetSizes = sizes
            totalCacheBytes = total
            diskStats = stats
            isSilentlyScanning = false
            hasCompletedScan = true
            if showProgressUI {
                hasCleanedSinceLastScan = false
                statusText = "Scan complete. Cache footprint: \(formatSize(total))"
            }
        case .cleanup, .dryRun:
            isSilentlyScanning = false
            statusText = "Unexpected operation state."
        }
        operationProgress = 0
        operationProgressLabel = ""
        if showProgressUI {
            isBusy = false
        }
    }

    func clearSelected() async {
        let modeForOperation = discoveryMode
        cancelCurrentOperation()
        guard discoveryMode == modeForOperation else { return }
        let selected = selectedTargets()
        guard !selected.isEmpty else {
            statusText = "Select at least one cache target."
            return
        }

        isBusy = true
        statusText = "Cleaning selected cache targets..."
        operationProgress = 0
        operationProgressLabel = "Preparing cleanup..."
        let operationID = UUID()
        activeOperationID = operationID

        let operation = Task.detached(priority: .userInitiated) { () -> OperationOutcome in
            var totalItemsDeleted = 0
            var totalItemsFailed = 0
            var inaccessibleFolders = 0
            var unsafeFolders = 0
            var totalFreed: Int64 = 0
            var workItems: [URL] = []

            for target in selected {
                if Task.isCancelled { return .cancelled }
                let resolved = Self.resolvePaths(pattern: target.pathPattern)
                workItems.append(contentsOf: resolved)
            }

            let totalSteps = max(workItems.count, 1)
            await MainActor.run { [weak self] in
                guard let self, self.activeOperationID == operationID else { return }
                self.operationProgress = 0
                self.operationProgressLabel = "Cleaning 0/\(workItems.count) folders..."
            }

            for (index, path) in workItems.enumerated() {
                if Task.isCancelled { return .cancelled }
                guard Self.isPathSafeForCleanup(path) else {
                    unsafeFolders += 1
                    totalItemsFailed += 1
                    continue
                }
                let clearResult = Self.clearFolderContents(path)
                totalItemsDeleted += clearResult.itemsDeleted
                totalItemsFailed += clearResult.itemsFailed
                inaccessibleFolders += clearResult.inaccessibleFolders
                totalFreed += clearResult.freedBytes

                let step = index + 1
                let progress = Double(step) / Double(totalSteps)
                await MainActor.run { [weak self] in
                    guard let self, self.activeOperationID == operationID else { return }
                    self.operationProgress = progress
                    self.operationProgressLabel = "Cleaning \(step)/\(workItems.count): \(Self.truncateMiddle(Self.displayPath(path), maxLength: 64))"
                }
            }
            return .cleanup(
                itemsDeleted: totalItemsDeleted,
                itemsFailed: totalItemsFailed,
                inaccessibleFolders: inaccessibleFolders,
                unsafeFolders: unsafeFolders,
                freedBytes: totalFreed
            )
        }
        activeOperation = operation
        let outcome = await operation.value

        guard activeOperationID == operationID else { return }
        guard discoveryMode == modeForOperation else { return }
        activeOperation = nil
        activeOperationID = nil

        switch outcome {
        case .cancelled:
            statusText = "Cleanup cancelled."
            lastOperationReport = "Cleanup was cancelled before completion."
            operationProgress = 0
            operationProgressLabel = ""
            isBusy = false
        case let .cleanup(itemsDeleted, itemsFailed, inaccessibleFolders, unsafeFolders, freedBytes):
            operationProgress = 1
            operationProgressLabel = "Cleanup finished."
            isBusy = false
            hasCleanedSinceLastScan = true
            lastCleanupSummary = CleanupSummary(
                freedBytes: freedBytes,
                itemsDeleted: itemsDeleted,
                itemsFailed: itemsFailed,
                inaccessibleFolders: inaccessibleFolders,
                unsafeFolders: unsafeFolders,
                completedAt: Date()
            )
            lastOperationReport = "Cleanup report: removed \(itemsDeleted) items, skipped \(itemsFailed), inaccessible folders \(inaccessibleFolders), blocked unsafe folders \(unsafeFolders), freed about \(formatSize(freedBytes))."
            statusText = "Cleanup complete."
            operationProgress = 0
            operationProgressLabel = ""
            await scanSizes(showProgressUI: false)
            guard discoveryMode == modeForOperation else { return }
        case .scan, .dryRun:
            statusText = "Unexpected operation state."
            operationProgress = 0
            operationProgressLabel = ""
            isBusy = false
        }
    }

    func dryRunSelected() async {
        let modeForOperation = discoveryMode
        cancelCurrentOperation()
        guard discoveryMode == modeForOperation else { return }
        let selected = selectedTargets()
        guard !selected.isEmpty else {
            statusText = "Select at least one cache target."
            return
        }

        isBusy = true
        statusText = "Dry run in progress..."
        let operationID = UUID()
        activeOperationID = operationID

        let operation = Task.detached(priority: .userInitiated) { () -> OperationOutcome in
            var itemsEstimated = 0
            var inaccessibleFolders = 0
            var unsafeFolders = 0
            var estimatedFreed: Int64 = 0
            for target in selected {
                if Task.isCancelled { return .cancelled }
                let resolved = Self.resolvePaths(pattern: target.pathPattern)
                for path in resolved {
                    if Task.isCancelled { return .cancelled }
                    guard Self.isPathSafeForCleanup(path) else {
                        unsafeFolders += 1
                        continue
                    }
                    let preview = Self.previewFolderContents(path)
                    itemsEstimated += preview.itemsEstimated
                    inaccessibleFolders += preview.inaccessibleFolders
                    estimatedFreed += preview.freedBytesEstimate
                }
            }
            return .dryRun(
                itemsEstimated: itemsEstimated,
                inaccessibleFolders: inaccessibleFolders,
                unsafeFolders: unsafeFolders,
                estimatedFreed: estimatedFreed
            )
        }
        activeOperation = operation
        let outcome = await operation.value

        guard activeOperationID == operationID else { return }
        guard discoveryMode == modeForOperation else { return }
        activeOperation = nil
        activeOperationID = nil

        switch outcome {
        case .cancelled:
            statusText = "Dry run cancelled."
            lastOperationReport = "Dry run was cancelled before completion."
        case let .dryRun(itemsEstimated, inaccessibleFolders, unsafeFolders, estimatedFreed):
            lastOperationReport = "Dry run report: estimated \(itemsEstimated) removable items, around \(formatSize(estimatedFreed)) reclaimable, inaccessible folders \(inaccessibleFolders), blocked unsafe folders \(unsafeFolders)."
            statusText = "Dry run complete."
        case .scan, .cleanup:
            statusText = "Unexpected operation state."
        }
        operationProgress = 0
        operationProgressLabel = ""
        isBusy = false
    }

    nonisolated private static func getDiskStats() -> DiskStats {
        let homePath = NSHomeDirectory()
        guard
            let attrs = try? FileManager.default.attributesOfFileSystem(forPath: homePath),
            let total = attrs[.systemSize] as? NSNumber,
            let free = attrs[.systemFreeSize] as? NSNumber
        else {
            return DiskStats(total: 0, used: 0, free: 0)
        }
        let totalBytes = total.int64Value
        let freeBytes = free.int64Value
        return DiskStats(total: totalBytes, used: totalBytes - freeBytes, free: freeBytes)
    }

    private func refreshTargets() {
        let discovered = Self.availableTargets(mode: discoveryMode)
        let oldSelections = selections
        targets = discovered
        selections = [:]
        targetSizes = [:]
        totalCacheBytes = 0
        for target in discovered {
            selections[target.id] = oldSelections[target.id] ?? target.enabledByDefault
            targetSizes[target.id] = 0
        }
        if discovered.isEmpty {
            statusText = "No safe cache folders found for \(discoveryMode.rawValue.lowercased()) mode."
            totalCacheBytes = 0
        }
    }

    nonisolated private static func availableTargets(mode: DiscoveryMode) -> [CacheTarget] {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
        let definitions = safeTargetDefinitions(mode: mode)
        var discovered: [CacheTarget] = []
        var seenPaths = Set<String>()

        for definition in definitions {
            let resolvedPaths = resolvePaths(pattern: definition.pattern)
            for resolved in resolvedPaths {
                let standardized = resolved.standardizedFileURL.path
                guard !seenPaths.contains(standardized) else { continue }
                guard isPathSafeForCleanup(resolved) else { continue }
                guard FileManager.default.fileExists(atPath: standardized) else { continue }
                seenPaths.insert(standardized)

                let rel = standardized.replacingOccurrences(of: homeURL.path, with: "")
                let cleanRel = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
                let label = cleanRel.isEmpty ? "~" : "~/\(cleanRel)"
                let id = "safe_" + cleanRel.replacingOccurrences(of: "/", with: "_")
                discovered.append(CacheTarget(
                    id: id,
                    label: label,
                    pathPattern: standardized,
                    inclusionReason: definition.reason,
                    enabledByDefault: definition.enabledByDefault
                ))
            }
        }

        return discovered.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    nonisolated private static func safeTargetDefinitions(mode: DiscoveryMode) -> [(pattern: String, reason: String, enabledByDefault: Bool)] {
        let ultraSafe: [(String, String, Bool)] = [
            ("~/Library/Caches", "Ultra Safe: user cache root only", true)
        ]
        let strict: [(String, String, Bool)] = [
            ("~/Library/Caches", "Known Apple/user cache root", true),
            ("~/Library/Containers/*/Data/Library/Caches", "App sandbox cache root", true),
            ("~/Library/Group Containers/*/Library/Caches", "Group container cache root", true),
            ("~/Library/Developer/Xcode/DerivedData", "Xcode build cache (DerivedData)", false),
            ("~/Library/Developer/CoreSimulator/Caches", "Simulator cache root", false)
        ]
        let balancedOnly: [(String, String, Bool)] = [
            ("~/Library/Logs", "User log files (safe to clear)", false),
            ("~/Library/Containers/*/Data/Library/Logs", "Sandbox app logs", false),
            ("~/Library/Group Containers/*/Library/Logs", "Group container logs", false),
            ("~/Library/tmp", "User temporary files", false),
            ("~/Library/Containers/*/Data/Library/tmp", "Sandbox temporary files", false)
        ]
        let developerDeepCleanOnly: [(String, String, Bool)] = [
            ("~/.gradle/caches", "Android/Gradle dependency and build caches", false),
            ("~/.gradle/daemon", "Gradle daemon state and logs", false),
            ("~/.gradle/native", "Gradle native extraction cache", false),
            ("~/.android/cache", "Android SDK/AVD cache data", false),
            ("~/.npm/_cacache", "npm package content-addressable cache", false),
            ("~/Library/Caches/Yarn", "Yarn classic package cache", false),
            ("~/Library/Caches/pnpm", "pnpm package store cache", false),
            ("~/Library/Caches/node-gyp", "node-gyp build cache", false),
            ("~/Library/Caches/CocoaPods", "CocoaPods artifact cache", false),
            ("~/Library/Developer/Xcode/Archives", "Xcode archive outputs (large, regeneratable)", false),
            ("~/Library/Developer/Xcode/iOS DeviceSupport", "Xcode iOS device support files", false),
            ("~/Library/Developer/Xcode/SourcePackages", "SwiftPM package caches for Xcode", false),
            ("~/.cache/pip", "pip wheel/download cache", false),
            ("~/Library/Caches/pip", "pip macOS cache location", false),
            ("~/.cache/pypoetry", "Poetry package cache", false),
            ("~/Library/Caches/pypoetry", "Poetry macOS cache location", false),
            ("~/.cache/uv", "uv package cache", false),
            ("~/Library/Caches/JetBrains", "JetBrains IDE system caches", false),
            ("~/Library/Application Support/JetBrains/*/caches", "JetBrains project/IDE caches", false),
            ("~/Library/Application Support/Google/AndroidStudio*/caches", "Android Studio IDE caches", false)
        ]
        switch mode {
        case .ultraSafe:
            return ultraSafe
        case .strict:
            return strict
        case .balanced:
            return strict + balancedOnly
        case .developerDeepClean:
            return strict + balancedOnly + developerDeepCleanOnly
        }
    }

    nonisolated private static func isPathSafeForCleanup(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL.path
        let expandedHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.path
        guard standardized.hasPrefix(expandedHome + "/") else { return false }

        let strictAllowedPrefixes = [
            "\(expandedHome)/Library/Caches",
            "\(expandedHome)/Library/Containers",
            "\(expandedHome)/Library/Group Containers",
            "\(expandedHome)/Library/Developer/Xcode/DerivedData",
            "\(expandedHome)/Library/Developer/CoreSimulator/Caches"
        ]
        let balancedAllowedPrefixes = strictAllowedPrefixes + [
            "\(expandedHome)/Library/Logs",
            "\(expandedHome)/Library/tmp"
        ]
        let developerDeepAllowedPrefixes = balancedAllowedPrefixes + [
            "\(expandedHome)/.gradle/caches",
            "\(expandedHome)/.gradle/daemon",
            "\(expandedHome)/.gradle/native",
            "\(expandedHome)/.android/cache",
            "\(expandedHome)/.npm/_cacache",
            "\(expandedHome)/.cache/pip",
            "\(expandedHome)/.cache/pypoetry",
            "\(expandedHome)/.cache/uv",
            "\(expandedHome)/Library/Caches/Yarn",
            "\(expandedHome)/Library/Caches/pnpm",
            "\(expandedHome)/Library/Caches/node-gyp",
            "\(expandedHome)/Library/Caches/CocoaPods",
            "\(expandedHome)/Library/Caches/pip",
            "\(expandedHome)/Library/Caches/pypoetry",
            "\(expandedHome)/Library/Caches/JetBrains",
            "\(expandedHome)/Library/Developer/Xcode/Archives",
            "\(expandedHome)/Library/Developer/Xcode/iOS DeviceSupport",
            "\(expandedHome)/Library/Developer/Xcode/SourcePackages",
            "\(expandedHome)/Library/Application Support/JetBrains",
            "\(expandedHome)/Library/Application Support/Google"
        ]
        let allowedPrefixes = developerDeepAllowedPrefixes
        guard allowedPrefixes.contains(where: { standardized == $0 || standardized.hasPrefix($0 + "/") }) else {
            return false
        }

        let lowercase = standardized.lowercased()
        let safeKeywords = [
            "cache", "caches", "deriveddata", "logs", "tmp", "temp",
            ".gradle", ".android", ".npm", ".cache", "sourcepackages",
            "archives", "devicesupport", "jetbrains", "androidstudio",
            "cocoapods", "yarn", "pnpm", "pip", "pypoetry", "uv"
        ]
        return safeKeywords.contains(where: { lowercase.contains($0) })
    }

    nonisolated private static func resolvePaths(pattern: String) -> [URL] {
        let expanded = (pattern as NSString).expandingTildeInPath
        if !expanded.contains("*") {
            return [URL(fileURLWithPath: expanded)]
        }

        let parentPath = (expanded as NSString).deletingLastPathComponent
        let namePattern = (expanded as NSString).lastPathComponent
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parentPath) else {
            return []
        }

        return entries
            .filter { wildcardMatches(pattern: namePattern, text: $0) }
            .map { URL(fileURLWithPath: parentPath).appendingPathComponent($0) }
    }

    nonisolated private static func wildcardMatches(pattern: String, text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*")
        let regex = "^\(escaped)$"
        return text.range(of: regex, options: .regularExpression) != nil
    }

    nonisolated private static func sizeOfPath(_ url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return fileSize(url)
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sizeNum = attrs[.size] as? NSNumber else {
            return 0
        }
        return sizeNum.int64Value
    }

    nonisolated private static func previewFolderContents(_ folder: URL) -> (itemsEstimated: Int, inaccessibleFolders: Int, freedBytesEstimate: Int64) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (0, 1, 0)
        }

        guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return (0, 1, 0)
        }

        var estimatedBytes: Int64 = 0
        for child in children {
            estimatedBytes += sizeOfPath(child)
        }
        return (children.count, 0, estimatedBytes)
    }

    nonisolated private static func clearFolderContents(_ folder: URL) -> (itemsDeleted: Int, itemsFailed: Int, inaccessibleFolders: Int, freedBytes: Int64) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (0, 0, 1, 0)
        }

        guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return (0, 0, 1, 0)
        }

        var itemsDeleted = 0
        var itemsFailed = 0
        var freedBytes: Int64 = 0
        for child in children {
            let childSize = sizeOfPath(child)
            do {
                try FileManager.default.removeItem(at: child)
                itemsDeleted += 1
                freedBytes += childSize
            } catch {
                itemsFailed += 1
            }
        }

        return (itemsDeleted, itemsFailed, 0, freedBytes)
    }

    nonisolated private static func displayPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.path
        guard standardized.hasPrefix(home) else { return standardized }

        let remainder = standardized.dropFirst(home.count)
        if remainder.isEmpty {
            return "~"
        }
        if remainder.first == "/" {
            return "~\(remainder)"
        }
        return "~/\(remainder)"
    }

    nonisolated private static func truncateMiddle(_ text: String, maxLength: Int) -> String {
        guard maxLength > 3, text.count > maxLength else { return text }

        let headCount = (maxLength - 1) / 2
        let tailCount = maxLength - headCount - 1

        let head = String(text.prefix(headCount))
        let tail = String(text.suffix(tailCount))
        return "\(head)...\(tail)"
    }
}
