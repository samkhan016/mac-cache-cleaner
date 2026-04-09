import Foundation
import Testing
@testable import SwiftUIMacCacheCleaner

@Test func discoveryModeCaseIterableHasFourModes() {
    #expect(CacheCleanerViewModel.DiscoveryMode.allCases.count == 4)
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

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
