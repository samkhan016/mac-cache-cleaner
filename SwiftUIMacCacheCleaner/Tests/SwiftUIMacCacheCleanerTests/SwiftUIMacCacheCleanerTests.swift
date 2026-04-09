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
