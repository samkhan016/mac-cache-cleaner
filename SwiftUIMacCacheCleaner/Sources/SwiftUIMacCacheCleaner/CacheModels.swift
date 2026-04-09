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

func formatSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: bytes)
}
