import Foundation

struct CacheTarget: Identifiable, Hashable {
    let id: String
    let label: String
    let pathPattern: String
    let enabledByDefault: Bool

    static let all: [CacheTarget] = [
        CacheTarget(id: "user_cache", label: "User cache", pathPattern: "~/Library/Caches", enabledByDefault: true),
        CacheTarget(id: "logs", label: "User logs", pathPattern: "~/Library/Logs", enabledByDefault: false),
        CacheTarget(id: "xcode_derived", label: "Xcode DerivedData", pathPattern: "~/Library/Developer/Xcode/DerivedData", enabledByDefault: true),
        CacheTarget(id: "xcode_archives", label: "Xcode Archives", pathPattern: "~/Library/Developer/Xcode/Archives", enabledByDefault: false),
        CacheTarget(id: "xcode_device_support", label: "Xcode iOS DeviceSupport", pathPattern: "~/Library/Developer/Xcode/iOS DeviceSupport", enabledByDefault: false),
        CacheTarget(id: "android_studio", label: "Android Studio caches", pathPattern: "~/Library/Caches/Google/AndroidStudio*", enabledByDefault: true),
        CacheTarget(id: "gradle", label: "Gradle caches", pathPattern: "~/.gradle/caches", enabledByDefault: true),
        CacheTarget(id: "npm", label: "npm cache", pathPattern: "~/.npm", enabledByDefault: false),
        CacheTarget(id: "yarn", label: "Yarn cache", pathPattern: "~/.yarn", enabledByDefault: false),
        CacheTarget(id: "cocoapods", label: "CocoaPods cache", pathPattern: "~/.cocoapods", enabledByDefault: false),
    ]
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
