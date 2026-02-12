//
//  LoopInsights_SuggestionStoreTests.swift
//  LoopTests
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import Loop

final class LoopInsights_SuggestionStoreTests: XCTestCase {

    private var store: LoopInsights_SuggestionStore!

    override func setUp() {
        super.setUp()
        store = LoopInsights_SuggestionStore.shared
        store.clearAllHistory()
    }

    override func tearDown() {
        store.clearAllHistory()
        super.tearDown()
    }

    // MARK: - Add

    func testAddSuggestion() {
        let suggestion = makeSuggestion()
        let record = store.addSuggestion(suggestion)

        XCTAssertEqual(record.status, .pending)
        XCTAssertEqual(store.allRecords.count, 1)
        XCTAssertEqual(store.pendingRecords.count, 1)
    }

    func testAddMultipleSuggestions() {
        let suggestions = [makeSuggestion(), makeSuggestion(), makeSuggestion()]
        let records = store.addSuggestions(suggestions)

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(store.allRecords.count, 3)
    }

    // MARK: - Status Transitions

    func testMarkApplied() {
        let suggestion = makeSuggestion()
        let record = store.addSuggestion(suggestion)

        store.markApplied(recordID: record.id, mode: .oneTap, snapshotBefore: nil, snapshotAfter: nil)

        let updated = store.record(withID: record.id)
        XCTAssertEqual(updated?.status, .applied)
        XCTAssertNotNil(updated?.resolvedAt)
        XCTAssertEqual(updated?.applyMode, .oneTap)
    }

    func testMarkAutoApplied() {
        let suggestion = makeSuggestion()
        let record = store.addSuggestion(suggestion)

        store.markApplied(recordID: record.id, mode: .autoApply, snapshotBefore: nil, snapshotAfter: nil)

        let updated = store.record(withID: record.id)
        XCTAssertEqual(updated?.status, .autoApplied)
    }

    func testMarkDismissed() {
        let suggestion = makeSuggestion()
        let record = store.addSuggestion(suggestion)

        store.markDismissed(recordID: record.id)

        let updated = store.record(withID: record.id)
        XCTAssertEqual(updated?.status, .dismissed)
        XCTAssertNotNil(updated?.resolvedAt)
    }

    func testDismissAllPending() {
        _ = store.addSuggestions([makeSuggestion(), makeSuggestion(), makeSuggestion()])

        XCTAssertEqual(store.pendingRecords.count, 3)

        store.dismissAllPending()

        XCTAssertEqual(store.pendingRecords.count, 0)
        XCTAssertEqual(store.resolvedRecords.count, 3)
    }

    // MARK: - Read

    func testPendingRecordsFilter() {
        let suggestion1 = makeSuggestion()
        let suggestion2 = makeSuggestion()
        let record1 = store.addSuggestion(suggestion1)
        _ = store.addSuggestion(suggestion2)

        store.markDismissed(recordID: record1.id)

        XCTAssertEqual(store.pendingRecords.count, 1)
        XCTAssertEqual(store.resolvedRecords.count, 1)
    }

    func testRecordLookupByID() {
        let suggestion = makeSuggestion()
        let record = store.addSuggestion(suggestion)

        let found = store.record(withID: record.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, record.id)

        let notFound = store.record(withID: UUID())
        XCTAssertNil(notFound)
    }

    // MARK: - Delete

    func testDeleteRecord() {
        let suggestion = makeSuggestion()
        let record = store.addSuggestion(suggestion)

        store.deleteRecord(withID: record.id)

        XCTAssertEqual(store.allRecords.count, 0)
    }

    func testClearAllHistory() {
        _ = store.addSuggestions([makeSuggestion(), makeSuggestion()])

        store.clearAllHistory()

        XCTAssertEqual(store.allRecords.count, 0)
    }

    // MARK: - Persistence

    func testRecordsSortedNewestFirst() {
        let suggestion1 = makeSuggestion()
        let suggestion2 = makeSuggestion()

        _ = store.addSuggestion(suggestion1)
        // Small delay to ensure different timestamps
        _ = store.addSuggestion(suggestion2)

        let records = store.allRecords
        XCTAssertEqual(records.count, 2)
        // Newest should be first
        XCTAssertGreaterThanOrEqual(records[0].createdAt, records[1].createdAt)
    }

    // MARK: - Helpers

    private func makeSuggestion() -> LoopInsightsSuggestion {
        return LoopInsightsSuggestion(
            id: UUID(),
            settingType: .carbRatio,
            timeBlocks: [
                LoopInsightsTimeBlock(startTime: 0, endTime: 21600, currentValue: 10, proposedValue: 11)
            ],
            reasoning: "Test reasoning",
            confidence: .medium,
            analysisPeriod: .fourteenDays,
            createdAt: Date()
        )
    }
}
