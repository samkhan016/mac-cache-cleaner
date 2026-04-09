import Foundation

@MainActor
final class CacheCleanerViewModel: ObservableObject {
    @Published var targets: [CacheTarget] = CacheTarget.all
    @Published var selections: [String: Bool] = [:]
    @Published var targetSizes: [String: Int64] = [:]
    @Published var statusText: String = "Ready"
    @Published var isBusy: Bool = false
    @Published var diskStats: DiskStats = DiskStats(total: 0, used: 0, free: 0)
    @Published var totalCacheBytes: Int64 = 0

    init() {
        for target in targets {
            selections[target.id] = target.enabledByDefault
            targetSizes[target.id] = 0
        }
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
