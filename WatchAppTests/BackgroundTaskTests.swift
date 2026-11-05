//
//  BackgroundTaskTests.swift
//  WatchAppTests
//
//  One wake can hand the app several background tasks at once, and watchOS ends the app when any of
//  them is released unfinished. Seen on the watch: a refresh and a phone message in one wake, the
//  phone message handled first, the refresh never finished, the app ended a moment later.
//

import XCTest
import WatchKit
@testable import WatchApp

/// Records being finished instead of telling watchOS, which never handed these out.
private final class RecordingRefreshTask: WKApplicationRefreshBackgroundTask {
    private(set) var finished = 0
    override func setTaskCompletedWithSnapshot(_ refreshSnapshot: Bool) { finished += 1 }
}

private final class RecordingConnectivityTask: WKWatchConnectivityRefreshBackgroundTask {
    override func setTaskCompletedWithSnapshot(_ refreshSnapshot: Bool) {}
}

private final class RecordingSnapshotTask: WKSnapshotRefreshBackgroundTask {
    override func setTaskCompleted(restoredDefaultState: Bool, estimatedSnapshotExpiration: Date?, userInfo: (any NSSecureCoding & NSObjectProtocol)?) {}
}

@MainActor
final class BackgroundTaskTests: XCTestCase {

    private var delegate: ExtensionDelegate {
        get throws { try XCTUnwrap(ExtensionDelegate.sharedIfAvailable(), "the test host's delegate") }
    }

    func testARefreshAfterAPhoneMessageInTheSameWakeIsFinished() throws {
        let refresh = RecordingRefreshTask()
        try delegate.finish([RecordingConnectivityTask(), refresh])
        XCTAssertEqual(refresh.finished, 1)
    }

    func testARefreshBeforeAPhoneMessageInTheSameWakeIsFinished() throws {
        let refresh = RecordingRefreshTask()
        try delegate.finish([refresh, RecordingConnectivityTask()])
        XCTAssertEqual(refresh.finished, 1)
    }

    func testARefreshAfterASnapshotInTheSameWakeIsFinished() throws {
        let refresh = RecordingRefreshTask()
        try delegate.finish([RecordingSnapshotTask(), refresh])
        XCTAssertEqual(refresh.finished, 1)
    }
}
