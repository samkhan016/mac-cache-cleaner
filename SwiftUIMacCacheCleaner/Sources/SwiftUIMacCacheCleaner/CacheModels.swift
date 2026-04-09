import Foundation

struct CacheTarget: Identifiable, Hashable {
    let id: String
    let label: String
    let pathPattern: String
    let inclusionReason: String
    let enabledByDefault: Bool
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
