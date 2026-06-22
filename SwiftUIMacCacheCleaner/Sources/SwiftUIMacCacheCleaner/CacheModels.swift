import Foundation

enum DeleteBehavior: Hashable {
    /// Remove files inside the target folder; keep the folder itself (cache cleanup).
    case clearContents
    /// Remove the target folder entirely (orphaned app leftovers).
    case removeEntireFolder
}

struct CacheTarget: Identifiable, Hashable {
    let id: String
    let label: String
    let pathPattern: String
    let inclusionReason: String
    let enabledByDefault: Bool
    let deleteBehavior: DeleteBehavior

    init(
        id: String,
        label: String,
        pathPattern: String,
        inclusionReason: String,
        enabledByDefault: Bool,
        deleteBehavior: DeleteBehavior = .clearContents
    ) {
        self.id = id
        self.label = label
        self.pathPattern = pathPattern
        self.inclusionReason = inclusionReason
        self.enabledByDefault = enabledByDefault
        self.deleteBehavior = deleteBehavior
    }
}

struct DiskStats {
    let total: Int64
    let used: Int64
    let free: Int64
}

struct CleanupSummary: Equatable {
    let freedBytes: Int64
    let itemsDeleted: Int
    let itemsFailed: Int
    let inaccessibleFolders: Int
    let unsafeFolders: Int
    let completedAt: Date
}

func formatSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: bytes)
}
