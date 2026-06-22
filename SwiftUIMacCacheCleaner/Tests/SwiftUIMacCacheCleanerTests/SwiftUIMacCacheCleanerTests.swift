import Foundation
import Testing
@testable import SwiftUIMacCacheCleaner

@Test func discoveryModeCaseIterableHasFiveModes() {
    #expect(CacheCleanerViewModel.DiscoveryMode.allCases.count == 5)
}

@Test func cleanupSummaryEquality() {
    let a = CleanupSummary(
        freedBytes: 100,
        itemsDeleted: 1,
        itemsFailed: 0,
        inaccessibleFolders: 0,
        unsafeFolders: 0,
        completedAt: Date(timeIntervalSince1970: 100)
    )
    let b = CleanupSummary(
        freedBytes: 100,
        itemsDeleted: 1,
        itemsFailed: 0,
        inaccessibleFolders: 0,
        unsafeFolders: 0,
        completedAt: Date(timeIntervalSince1970: 100)
    )
    #expect(a == b)
}

@Test func pathSafetyRejectsOutsideHomeAndAllowsModeScopedCaches() throws {
    let home = try makeTemporaryDirectory(prefix: "home-")
    let outside = try makeTemporaryDirectory(prefix: "outside-")
    defer { try? FileManager.default.removeItem(at: home) }
    defer { try? FileManager.default.removeItem(at: outside) }

    let insideCache = home.appendingPathComponent("Library/Caches/com.example.app", isDirectory: true)
    try FileManager.default.createDirectory(at: insideCache, withIntermediateDirectories: true)
    #expect(CacheCleanerViewModel.isPathSafeForCleanup(insideCache, mode: .ultraSafe, homeURL: home))

    let insideLogs = home.appendingPathComponent("Library/Logs", isDirectory: true)
    try FileManager.default.createDirectory(at: insideLogs, withIntermediateDirectories: true)
    #expect(!CacheCleanerViewModel.isPathSafeForCleanup(insideLogs, mode: .strict, homeURL: home))
    #expect(CacheCleanerViewModel.isPathSafeForCleanup(insideLogs, mode: .balanced, homeURL: home))

    let outsidePath = outside.appendingPathComponent("Library/Caches", isDirectory: true)
    try FileManager.default.createDirectory(at: outsidePath, withIntermediateDirectories: true)
    #expect(!CacheCleanerViewModel.isPathSafeForCleanup(outsidePath, mode: .developerDeepClean, homeURL: home))
}

@Test func pathSafetyRejectsSymlinkEscapes() throws {
    let home = try makeTemporaryDirectory(prefix: "home-")
    let outside = try makeTemporaryDirectory(prefix: "outside-")
    defer { try? FileManager.default.removeItem(at: home) }
    defer { try? FileManager.default.removeItem(at: outside) }

    let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

    let outsideDir = outside.appendingPathComponent("real-cache", isDirectory: true)
    try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    let symlink = cacheRoot.appendingPathComponent("escape-link")
    try FileManager.default.createSymbolicLink(atPath: symlink.path, withDestinationPath: outsideDir.path)

    #expect(!CacheCleanerViewModel.isPathSafeForCleanup(symlink, mode: .ultraSafe, homeURL: home))
}

@Test func developerModeDynamicallyFindsContainerAndToolCaches() throws {
    let home = try makeTemporaryDirectory(prefix: "home-")
    defer { try? FileManager.default.removeItem(at: home) }

    let containerCache = home.appendingPathComponent("Library/Containers/com.example.test/Data/Library/Caches", isDirectory: true)
    let groupCache = home.appendingPathComponent("Library/Group Containers/group.example.test/Library/Caches", isDirectory: true)
    let jetBrainsCache = home.appendingPathComponent("Library/Application Support/JetBrains/IntelliJIdea2025.3/caches", isDirectory: true)
    let androidStudioCache = home.appendingPathComponent("Library/Application Support/Google/AndroidStudio2025.1/caches", isDirectory: true)
    let logsPath = home.appendingPathComponent("Library/Containers/com.example.test/Data/Library/Logs", isDirectory: true)

    for path in [containerCache, groupCache, jetBrainsCache, androidStudioCache, logsPath] {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }

    let deepTargets = CacheCleanerViewModel.availableTargets(mode: .developerDeepClean, homeURL: home)
    let deepPaths = Set(deepTargets.map(\.pathPattern))
    #expect(deepPaths.contains(containerCache.standardizedFileURL.path))
    #expect(deepPaths.contains(groupCache.standardizedFileURL.path))
    #expect(deepPaths.contains(jetBrainsCache.standardizedFileURL.path))
    #expect(deepPaths.contains(androidStudioCache.standardizedFileURL.path))
    #expect(deepPaths.contains(logsPath.standardizedFileURL.path))

    let strictTargets = CacheCleanerViewModel.availableTargets(mode: .strict, homeURL: home)
    let strictPaths = Set(strictTargets.map(\.pathPattern))
    #expect(!strictPaths.contains(logsPath.standardizedFileURL.path))
}

@Test func uninstalledAppsModeFindsOrphanedContainersAndCaches() throws {
    let home = try makeTemporaryDirectory(prefix: "home-")
    defer { try? FileManager.default.removeItem(at: home) }

    let liveContainer = home.appendingPathComponent("Library/Containers/com.example.live/Data", isDirectory: true)
    let orphanContainer = home.appendingPathComponent("Library/Containers/com.example.removed/Data", isDirectory: true)
    let orphanCache = home.appendingPathComponent("Library/Caches/com.example.removed", isDirectory: true)
    let liveCache = home.appendingPathComponent("Library/Caches/com.example.live", isDirectory: true)
    let notBundleLike = home.appendingPathComponent("Library/Caches/Google", isDirectory: true)

    for path in [liveContainer, orphanContainer, orphanCache, liveCache, notBundleLike] {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }

    let targets = CacheCleanerViewModel.availableUninstalledAppTargets(
        homeURL: home,
        isBundleInstalled: { $0 == "com.example.live" },
        isAppSupportFolderLinked: { $0 == "LiveApp" || $0 == "Vendor/LiveProduct" }
    )
    let paths = Set(targets.map(\.pathPattern))

    #expect(paths.contains(orphanContainer.deletingLastPathComponent().standardizedFileURL.path))
    #expect(paths.contains(orphanCache.standardizedFileURL.path))
    #expect(!paths.contains(liveContainer.deletingLastPathComponent().standardizedFileURL.path))
    #expect(!paths.contains(liveCache.standardizedFileURL.path))
    #expect(!paths.contains(notBundleLike.standardizedFileURL.path))
    #expect(targets.allSatisfy { $0.deleteBehavior == .removeEntireFolder })
    #expect(targets.allSatisfy { $0.enabledByDefault == false })
    #expect(targets.count >= 2)
}

@Test func orphanRemovalSafetyAllowsDirectBundleFoldersOnly() throws {
    let home = try makeTemporaryDirectory(prefix: "home-")
    defer { try? FileManager.default.removeItem(at: home) }

    let containerRoot = home.appendingPathComponent("Library/Containers/com.example.removed", isDirectory: true)
    let nestedCache = containerRoot.appendingPathComponent("Data/Library/Caches", isDirectory: true)
    let cacheRoot = home.appendingPathComponent("Library/Caches/com.example.removed", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedCache, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

    #expect(CacheCleanerViewModel.isPathSafeForOrphanRemoval(containerRoot, homeURL: home))
    #expect(CacheCleanerViewModel.isPathSafeForOrphanRemoval(cacheRoot, homeURL: home))
    #expect(!CacheCleanerViewModel.isPathSafeForOrphanRemoval(nestedCache, homeURL: home))

    let appSupportRoot = home.appendingPathComponent("Library/Application Support/RemovedApp", isDirectory: true)
    let appSupportNested = home.appendingPathComponent("Library/Application Support/Vendor/Product", isDirectory: true)
    let appSupportDeep = home.appendingPathComponent("Library/Application Support/Vendor/Product/Extra", isDirectory: true)
    try FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: appSupportNested, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: appSupportDeep, withIntermediateDirectories: true)
    #expect(CacheCleanerViewModel.isPathSafeForOrphanRemoval(appSupportRoot, homeURL: home))
    #expect(CacheCleanerViewModel.isPathSafeForOrphanRemoval(appSupportNested, homeURL: home))
    #expect(!CacheCleanerViewModel.isPathSafeForOrphanRemoval(appSupportDeep, homeURL: home))
}

@Test func uninstalledAppsModeFindsOrphanedApplicationSupportFolders() throws {
    let home = try makeTemporaryDirectory(prefix: "home-")
    defer { try? FileManager.default.removeItem(at: home) }

    let orphanAppSupport = home.appendingPathComponent("Library/Application Support/RemovedApp", isDirectory: true)
    let liveAppSupport = home.appendingPathComponent("Library/Application Support/LiveApp", isDirectory: true)
    let orphanVendorProduct = home.appendingPathComponent("Library/Application Support/Google/RemovedProduct", isDirectory: true)
    let liveVendorProduct = home.appendingPathComponent("Library/Application Support/Google/LiveProduct", isDirectory: true)
    let protectedApple = home.appendingPathComponent("Library/Application Support/com.apple.shared", isDirectory: true)

    for path in [orphanAppSupport, liveAppSupport, orphanVendorProduct, liveVendorProduct, protectedApple] {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }

    let result = CacheCleanerViewModel.availableUninstalledAppTargets(
        homeURL: home,
        isBundleInstalled: { _ in false },
        isAppSupportFolderLinked: { name in
            name == "LiveApp" || name == "LiveProduct" || name == "Google/LiveProduct"
        }
    )
    let paths = Set(result.map(\.pathPattern))

    #expect(paths.contains(orphanAppSupport.standardizedFileURL.path))
    #expect(paths.contains(orphanVendorProduct.standardizedFileURL.path))
    #expect(!paths.contains(liveAppSupport.standardizedFileURL.path))
    #expect(!paths.contains(liveVendorProduct.standardizedFileURL.path))
    #expect(!paths.contains(protectedApple.standardizedFileURL.path))
}

@Test func isBundleInstalledOnSystemRequiresExistingAppBundle() {
    let index = CacheCleanerViewModel.InstalledAppIndex(
        bundleIDs: ["com.example.from-disk"],
        records: [
            CacheCleanerViewModel.InstalledAppRecord(
                bundleID: "com.example.from-disk",
                normalizedNames: ["example"]
            )
        ]
    )
    #expect(CacheCleanerViewModel.isBundleInstalledOnSystem("com.example.from-disk", installedAppIndex: index))
    #expect(!CacheCleanerViewModel.isBundleInstalledOnSystem("com.example.missing", installedAppIndex: index))
}

@Test func appleSystemBundleIDsAreExcludedFromLeftoverDiscovery() throws {
    let home = try makeTemporaryDirectory(prefix: "home-")
    defer { try? FileManager.default.removeItem(at: home) }

    let appleContainer = home.appendingPathComponent("Library/Containers/com.apple.ScreenTimeAgent/Data", isDirectory: true)
    let orphanContainer = home.appendingPathComponent("Library/Containers/com.example.removed/Data", isDirectory: true)
    try FileManager.default.createDirectory(at: appleContainer, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: orphanContainer, withIntermediateDirectories: true)

    let result = CacheCleanerViewModel.availableUninstalledAppTargets(
        homeURL: home,
        isBundleInstalled: { _ in false }
    )
    let paths = Set(result.map(\.pathPattern))

    #expect(!paths.contains(appleContainer.deletingLastPathComponent().standardizedFileURL.path))
    #expect(paths.contains(orphanContainer.deletingLastPathComponent().standardizedFileURL.path))
}

@Test func appExtensionContainersLinkToInstalledParentApp() {
    let index = CacheCleanerViewModel.InstalledAppIndex(
        bundleIDs: ["com.example.live", "net.whatsapp.WhatsApp"],
        records: []
    )
    #expect(
        CacheCleanerViewModel.isBundleIDLinkedToInstalledApp(
            "com.example.live.helper",
            installedAppIndex: index
        )
    )
    #expect(
        CacheCleanerViewModel.isBundleIDLinkedToInstalledApp(
            "net.whatsapp.WhatsApp.ServiceExtension",
            installedAppIndex: index
        )
    )
    #expect(
        !CacheCleanerViewModel.isBundleIDLinkedToInstalledApp(
            "com.example.removed",
            installedAppIndex: index
        )
    )
    #expect(
        CacheCleanerViewModel.isBundleIDLinkedToInstalledApp(
            "com.apple.mail.MailQuickLookExtension",
            installedAppIndex: index
        )
    )
}

@Test func genericApplicationSupportSubfolderNamesDoNotFalsePositive() {
    #expect(CacheCleanerViewModel.isGenericApplicationSupportSubfolderName("Cache"))
    #expect(CacheCleanerViewModel.isGenericApplicationSupportSubfolderName("Code Cache"))
    #expect(CacheCleanerViewModel.isGenericApplicationSupportSubfolderName("monitor"))
    #expect(!CacheCleanerViewModel.isGenericApplicationSupportSubfolderName("AndroidStudio2025.1"))
}

@Test func uninstalledAppSupportFolderConsolidatesToParent() throws {
    let home = try makeTemporaryDirectory(prefix: "home-")
    defer { try? FileManager.default.removeItem(at: home) }

    let slackRoot = home.appendingPathComponent("Library/Application Support/Slack", isDirectory: true)
    let slackCache = slackRoot.appendingPathComponent("Cache", isDirectory: true)
    let slackLogs = slackRoot.appendingPathComponent("logs", isDirectory: true)
    for path in [slackRoot, slackCache, slackLogs] {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }

    let result = CacheCleanerViewModel.availableUninstalledAppTargets(
        homeURL: home,
        isBundleInstalled: { _ in false },
        isAppSupportFolderLinked: { _ in false }
    )
    let paths = Set(result.map(\.pathPattern))

    #expect(paths.contains(slackRoot.standardizedFileURL.path))
    #expect(!paths.contains(slackCache.standardizedFileURL.path))
    #expect(!paths.contains(slackLogs.standardizedFileURL.path))
}

@Test func legacyMSTeamsFolderLinksToInstalledTeams2() {
    let index = CacheCleanerViewModel.InstalledAppIndex(
        bundleIDs: ["com.microsoft.teams2"],
        records: [
            CacheCleanerViewModel.InstalledAppRecord(
                bundleID: "com.microsoft.teams2",
                normalizedNames: ["microsoftteams"]
            )
        ]
    )
    #expect(
        CacheCleanerViewModel.isApplicationSupportFolderLinkedToInstalledApp(
            "Microsoft/MSTeams",
            index: index
        )
    )
}

@Test func swiftToolchainCachesAreExcludedFromLeftoverDiscovery() throws {
    let home = try makeTemporaryDirectory(prefix: "home-")
    defer { try? FileManager.default.removeItem(at: home) }

    let swiftCache = home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)
    try FileManager.default.createDirectory(at: swiftCache, withIntermediateDirectories: true)

    let result = CacheCleanerViewModel.availableUninstalledAppTargets(
        homeURL: home,
        isBundleInstalled: { _ in false }
    )
    let paths = Set(result.map(\.pathPattern))

    #expect(!paths.contains(swiftCache.standardizedFileURL.path))
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
