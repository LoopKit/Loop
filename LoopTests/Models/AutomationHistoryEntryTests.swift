//
//  AutomationHistoryEntryTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 9/19/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import XCTest

@testable import Loop

class TimelineTests: XCTestCase {

    func testEmptyArray() {
        let entries: [AutomationHistoryEntry] = []
        let start = Date()
        let end = start.addingTimeInterval(3600) // 1 hour later

        let timeline = entries.toTimeline(from: start, to: end)

        XCTAssertTrue(timeline.isEmpty, "Timeline should be empty for an empty array of entries")
    }

    func testSingleEntry() {
        let start = Date()
        let end = start.addingTimeInterval(3600) // 1 hour later
        let entries = [AutomationHistoryEntry(startDate: start, enabled: true)]

        let timeline = entries.toTimeline(from: start, to: end)

        XCTAssertEqual(timeline.count, 1, "Timeline should have one entry")
        XCTAssertEqual(timeline[0].startDate, start)
        XCTAssertEqual(timeline[0].endDate, end)
        XCTAssertEqual(timeline[0].value, true)
    }

    func testMultipleEntries() {
        let start = Date()
        let middleDate = start.addingTimeInterval(1800) // 30 minutes later
        let end = start.addingTimeInterval(3600) // 1 hour later
        let entries = [
            AutomationHistoryEntry(startDate: start, enabled: true),
            AutomationHistoryEntry(startDate: middleDate, enabled: false)
        ]

        let timeline = entries.toTimeline(from: start, to: end)

        XCTAssertEqual(timeline.count, 2, "Timeline should have two entries")
        XCTAssertEqual(timeline[0].startDate, start)
        XCTAssertEqual(timeline[0].endDate, middleDate)
        XCTAssertEqual(timeline[0].value, true)
        XCTAssertEqual(timeline[1].startDate, middleDate)
        XCTAssertEqual(timeline[1].endDate, end)
        XCTAssertEqual(timeline[1].value, false)
    }

    func testEntriesOutsideRange() {
        let start = Date()
        let end = start.addingTimeInterval(3600) // 1 hour later
        let beforeStart = start.addingTimeInterval(-1800) // 30 minutes before start
        let afterEnd = end.addingTimeInterval(1800) // 30 minutes after end
        let entries = [
            AutomationHistoryEntry(startDate: beforeStart, enabled: true),
            AutomationHistoryEntry(startDate: afterEnd, enabled: false)
        ]

        let timeline = entries.toTimeline(from: start, to: end)

        XCTAssertEqual(timeline.count, 1, "Timeline should have one entry")
        XCTAssertEqual(timeline[0].startDate, start)
        XCTAssertEqual(timeline[0].endDate, end)
        XCTAssertEqual(timeline[0].value, true)
    }

    func testConsecutiveEntriesWithSameValue() {
        let start = Date()
        let middle1 = start.addingTimeInterval(1200) // 20 minutes later
        let middle2 = start.addingTimeInterval(2400) // 40 minutes later
        let end = start.addingTimeInterval(3600) // 1 hour later
        let entries = [
            AutomationHistoryEntry(startDate: start, enabled: true),
            AutomationHistoryEntry(startDate: middle1, enabled: true),
            AutomationHistoryEntry(startDate: middle2, enabled: false)
        ]

        let timeline = entries.toTimeline(from: start, to: end)

        XCTAssertEqual(timeline.count, 2, "Timeline should have two entries")
        XCTAssertEqual(timeline[0].startDate, start)
        XCTAssertEqual(timeline[0].endDate, middle2)
        XCTAssertEqual(timeline[0].value, true)
        XCTAssertEqual(timeline[1].startDate, middle2)
        XCTAssertEqual(timeline[1].endDate, end)
        XCTAssertEqual(timeline[1].value, false)
    }
}
