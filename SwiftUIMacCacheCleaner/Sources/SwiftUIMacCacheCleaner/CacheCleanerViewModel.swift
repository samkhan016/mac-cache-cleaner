import Foundation

@MainActor
final class CacheCleanerViewModel: ObservableObject {
    enum DiscoveryMode: String {
        case strict = "Strict"
        case balanced = "Balanced"
    }

    @Published var discoveryMode: DiscoveryMode = .strict
    @Published var targets: [CacheTarget] = []
    @Published var selections: [String: Bool] = [:]
    @Published var targetSizes: [String: Int64] = [:]
    @Published var statusText: String = "Ready"
    @Published var isBusy: Bool = false
    @Published var diskStats: DiskStats = DiskStats(total: 0, used: 0, free: 0)
    @Published var totalCacheBytes: Int64 = 0

    init() {
        refreshTargets()
        if targets.isEmpty {
            diskStats = Self.getDiskStats()
        } else {
            Task { await scanSizes() }
        }
    }

    func updateDiscoveryMode(_ mode: DiscoveryMode) {
        guard discoveryMode != mode else { return }
        discoveryMode = mode
        refreshTargets()
        Task { await scanSizes() }
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

    func scanSizes() async {
        guard !targets.isEmpty else {
            totalCacheBytes = 0
            diskStats = Self.getDiskStats()
            statusText = "No known cache folders were found on this Mac."
            return
        }
        isBusy = true
        statusText = "Scanning cache sizes..."
        let targetsSnapshot = targets

        let result = await Task.detached(priority: .userInitiated) {
            var localSizes: [String: Int64] = [:]
            var localTotal: Int64 = 0
            for target in targetsSnapshot {
                let resolved = Self.resolvePaths(pattern: target.pathPattern)
                let size = resolved.reduce(Int64(0)) { $0 + Self.sizeOfPath($1) }
                localSizes[target.id] = size
                localTotal += size
            }
            return (localSizes, localTotal, Self.getDiskStats())
        }.value

        targetSizes = result.0
        totalCacheBytes = result.1
        diskStats = result.2
        statusText = "Scan complete. Cache footprint: \(formatSize(result.1))"
        isBusy = false
    }

    func clearSelected() async {
        let selected = selectedTargets()
        guard !selected.isEmpty else {
            statusText = "Select at least one cache target."
            return
        }

        isBusy = true
        statusText = "Cleaning selected cache targets..."

        let result = await Task.detached(priority: .userInitiated) {
            var totalItemsDeleted = 0
            var totalFreed: Int64 = 0
            for target in selected {
                let resolved = Self.resolvePaths(pattern: target.pathPattern)
                for path in resolved {
                    let clearResult = Self.clearFolderContents(path)
                    totalItemsDeleted += clearResult.itemsDeleted
                    totalFreed += clearResult.freedBytes
                }
            }
            return (totalItemsDeleted, totalFreed)
        }.value

        statusText = "Cleanup complete. Removed \(result.0) items, freed about \(formatSize(result.1))."
        await scanSizes()
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
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let candidateRoots = [
            homeURL,
            homeURL.appendingPathComponent("Library", isDirectory: true)
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        var discovered: [CacheTarget] = []
        var seenPaths = Set<String>()
        for root in candidateRoots {
            traverseDirectories(root: root, home: homeURL, depth: 0, maxDepth: 5, mode: mode) { dir, reason in
                let standardized = dir.standardizedFileURL.path
                guard !seenPaths.contains(standardized) else { return }
                seenPaths.insert(standardized)

                let rel = standardized.replacingOccurrences(of: homeURL.path, with: "")
                let cleanRel = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
                let label = cleanRel.isEmpty ? "~" : "~/\(cleanRel)"
                let id = "auto_" + cleanRel.replacingOccurrences(of: "/", with: "_")
                discovered.append(CacheTarget(
                    id: id,
                    label: label,
                    pathPattern: standardized,
                    inclusionReason: reason,
                    enabledByDefault: true
                ))
            }
        }
        return discovered.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    nonisolated private static func traverseDirectories(
        root: URL,
        home: URL,
        depth: Int,
        maxDepth: Int,
        mode: DiscoveryMode,
        onCandidate: (URL, String) -> Void
    ) {
        guard depth <= maxDepth else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }

        for entry in entries {
            guard isDirectory(entry) else { continue }
            if isProtectedTopLevel(entry, home: home) { continue }

            if let reason = cacheReasonIfSafe(entry, home: home, mode: mode) {
                onCandidate(entry, reason)
            }
            traverseDirectories(root: entry, home: home, depth: depth + 1, maxDepth: maxDepth, mode: mode, onCandidate: onCandidate)
        }
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    nonisolated private static func isProtectedTopLevel(_ url: URL, home: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        guard parent == home.standardizedFileURL.path else { return false }
        let protected = Set([
            "Applications", "Desktop", "Documents", "Downloads", "Movies",
            "Music", "Pictures", "Public", "Sites"
        ])
        return protected.contains(url.lastPathComponent)
    }

    nonisolated private static func cacheReasonIfSafe(_ url: URL, home: URL, mode: DiscoveryMode) -> String? {
        let standardized = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard standardized.hasPrefix(homePath), standardized != homePath else { return nil }

        let lowerName = url.lastPathComponent.lowercased()
        let strictKeywords = ["cache", "caches", "deriveddata"]
        let balancedKeywords = strictKeywords + ["logs", "tmp", "temp"]
        let keywords = mode == .strict ? strictKeywords : balancedKeywords
        guard let matched = keywords.first(where: { lowerName.contains($0) }) else { return nil }

        guard let children = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
              !children.isEmpty else {
            return nil
        }
        if mode == .strict {
            return "Matched strict cache keyword: '\(matched)'"
        }
        return "Matched balanced cache keyword: '\(matched)'"
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

    nonisolated private static func clearFolderContents(_ folder: URL) -> (itemsDeleted: Int, freedBytes: Int64) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (0, 0)
        }

        guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return (0, 0)
        }

        var itemsDeleted = 0
        var freedBytes: Int64 = 0
        for child in children {
            let childSize = sizeOfPath(child)
            do {
                try FileManager.default.removeItem(at: child)
                itemsDeleted += 1
                freedBytes += childSize
            } catch {
                continue
            }
        }

        return (itemsDeleted, freedBytes)
    }
}
