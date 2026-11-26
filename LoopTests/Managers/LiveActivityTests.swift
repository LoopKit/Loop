import XCTest
import LoopKit
import LoopCore
import UIKit

@testable import Loop

@available(iOS 16.2, *)
@MainActor
final class LiveActivityTests: XCTestCase {
    func testCGMOnlyActivityPublishesCompleteSnapshotsOnCreationAndNotification() async throws {
        let h = Harness()
        h.store.samples = [h.sample(118, minutesAgo: 5), h.sample(123, trend: .flat)]
        let manager = try h.makeManager()
        await manager.refresh()

        let initial = try XCTUnwrap(h.client.states.first)
        XCTAssertEqual(h.client.states.count, 1)
        XCTAssertEqual(initial.currentGlucose, 123)
        XCTAssertEqual(initial.glucoseSamples.map(\.y), [118, 123])
        XCTAssertEqual(initial.delta, "+5")
        XCTAssertEqual(initial.bottomRow.first?.value, "123")
        XCTAssertNil(initial.eventualGlucose)
        XCTAssertNil(initial.lastCompleted)

        let published = expectation(description: "New CGM reading published without a loop calculation")
        h.client.onPublish = { _ in published.fulfill() }
        h.store.samples.append(h.sample(125, trend: .up))
        h.center.post(name: GlucoseStore.glucoseSamplesDidChange, object: h.store)
        await fulfillment(of: [published], timeout: 2)

        let updated = try XCTUnwrap(h.client.states.last)
        XCTAssertEqual(updated.currentGlucose, 125)
        XCTAssertEqual(updated.delta, "+2")
        XCTAssertEqual(updated.trendType, .up)
        XCTAssertEqual(updated.bottomRow.first?.value, "125")
        XCTAssertEqual(updated.glucoseSamples.last?.y, 125)
        XCTAssertEqual(h.client.states.count, 2)
        XCTAssertEqual(h.client.endCount, 1)
        withExtendedLifetime(manager) {}
    }

    func testCGMReadingsAdvanceWhileSuspendedLoopCompletionRemainsStale() async throws {
        let h = Harness()
        let lastCompleted = h.date.addingTimeInterval(-.hours(1))
        // Suspending delivery does not turn off the closed-loop preference. Its
        // completion date can remain frozen while the CGM keeps producing readings.
        var context = StatusExtensionContext()
        context.isClosedLoop = true
        context.lastLoopCompleted = lastCompleted
        h.context = context
        h.store.samples = [h.sample(100)]
        let manager = try h.makeManager()
        await manager.refresh()

        for value in [125.0, 130.0] {
            h.date = h.date.addingTimeInterval(.minutes(5))
            h.store.samples.append(h.sample(value))
            let published = expectation(description: "CGM reading published while loop completion is frozen")
            h.client.onPublish = { _ in published.fulfill() }
            h.center.post(name: GlucoseStore.glucoseSamplesDidChange, object: h.store)
            await fulfillment(of: [published], timeout: 2)

            let state = try XCTUnwrap(h.client.states.last)
            XCTAssertEqual(state.currentGlucose, value)
            XCTAssertEqual(state.glucoseSamples.last?.y, value)
            XCTAssertEqual(state.date, h.date)
            XCTAssertEqual(state.lastCompleted, lastCompleted)
            XCTAssertTrue(state.isCloseLoop)
            XCTAssertFalse(state.ended)
        }
        XCTAssertEqual(h.client.states.count, 3)
        XCTAssertEqual(h.client.endCount, 1)
        withExtendedLifetime(manager) {}
    }

    func testRefreshReadsLatestDisplayUnit() async throws {
        let h = Harness()
        h.store.samples = [h.sample(108)]
        let manager = try h.makeManager()
        await manager.refresh()
        XCTAssertEqual(h.client.states.last?.currentGlucose, 108)

        h.unit = .millimolesPerLiter
        await manager.refresh()

        let state = try XCTUnwrap(h.client.states.last)
        XCTAssertTrue(state.isMmol)
        XCTAssertEqual(try XCTUnwrap(state.currentGlucose), 6.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(state.glucoseSamples.last?.y), 6.0, accuracy: 0.01)
        let formatter = NumberFormatter.glucoseFormatter(for: h.unit)
        let displayed = try XCTUnwrap(formatter.number(from: try XCTUnwrap(state.bottomRow.first?.value)))
        XCTAssertEqual(displayed.doubleValue, 6.0, accuracy: 0.05)
    }

    func testMissingGlucoseStaysOptionalInBothUnits() async throws {
        for unit in [LoopUnit.milligramsPerDeciliter, .millimolesPerLiter] {
            let h = Harness()
            h.unit = unit
            let manager = try h.makeManager()
            await manager.refresh()

            let state = try XCTUnwrap(h.client.states.last)
            XCTAssertNil(state.currentGlucose)
            XCTAssertNil(state.trendType)
            XCTAssertEqual(state.bottomRow.first?.value, "??")
            XCTAssertEqual(state.delta, "??")
            XCTAssertFalse(state.ended)
            XCTAssertTrue(state.glucoseSamples.isEmpty)
        }
    }

    func testOverlappingRequestsDiscardOldFetchAndCoalesceNewRequests() async throws {
        let h = Harness()
        let started = expectation(description: "First fetch started")
        var pending: CheckedContinuation<[StoredGlucoseSample], Error>?
        defer { h.store.fetch = nil }
        h.store.fetch = {
            if h.store.fetchCount == 1 {
                return try await withCheckedThrowingContinuation {
                    pending = $0
                    started.fulfill()
                }
            }
            return [h.sample(125)]
        }
        let manager = try h.makeManager()
        await fulfillment(of: [started], timeout: 2)

        for _ in 0..<5 {
            manager.update(scheduleOverride: nil, preMealOverride: nil, glucoseTargetRangeSchedule: nil, activeInsulin: nil)
        }
        try XCTUnwrap(pending).resume(returning: [h.sample(100)])
        await manager.refresh()

        XCTAssertEqual(h.store.fetchCount, 2)
        XCTAssertEqual(h.client.states.map(\.currentGlucose), [125])
    }

    func testPublicationIsSerializedAcrossSuspension() async throws {
        let h = Harness()
        h.store.samples = [h.sample(100)]
        let started = expectation(description: "First publication started")
        let premature = expectation(description: "Second publication started before the first finished")
        premature.isInverted = true
        var pending: CheckedContinuation<Void, Never>?
        var firstReleased = false
        h.client.onPublish = { state in
            if state.currentGlucose == 100 {
                await withCheckedContinuation {
                    pending = $0
                    started.fulfill()
                }
            } else if !firstReleased {
                premature.fulfill()
            }
        }
        let manager = try h.makeManager()
        await fulfillment(of: [started], timeout: 2)

        h.store.samples = [h.sample(125)]
        manager.update(scheduleOverride: nil, preMealOverride: nil, glucoseTargetRangeSchedule: nil, activeInsulin: nil)
        await fulfillment(of: [premature], timeout: 0.1)
        firstReleased = true
        try XCTUnwrap(pending).resume()
        await manager.refresh()

        XCTAssertEqual(h.client.maxConcurrentPublications, 1)
        XCTAssertEqual(h.client.states.map(\.currentGlucose), [100, 125])
    }

    func testDisablingDuringFetchPreventsPublication() async throws {
        let h = Harness()
        let started = expectation(description: "Fetch started")
        var pending: CheckedContinuation<[StoredGlucoseSample], Error>?
        h.store.fetch = {
            try await withCheckedThrowingContinuation {
                pending = $0
                started.fulfill()
            }
        }
        let manager = try h.makeManager()
        await fulfillment(of: [started], timeout: 2)

        h.settings.enabled = false
        manager.update(scheduleOverride: nil, preMealOverride: nil, glucoseTargetRangeSchedule: nil, activeInsulin: nil)
        try XCTUnwrap(pending).resume(returning: [h.sample(100)])
        await manager.refresh()

        XCTAssertTrue(h.client.states.isEmpty)
        XCTAssertEqual(h.store.fetchCount, 1)
        XCTAssertEqual(h.client.endCount, 1)
    }

    func testRequestDuringCleanupInvalidatesPreparedSnapshot() async throws {
        let h = Harness()
        h.store.samples = [h.sample(100)]
        let started = expectation(description: "Initial cleanup started")
        var pending: CheckedContinuation<Void, Never>?
        defer { h.client.onEnd = nil }
        h.client.onEnd = {
            if h.client.endCount == 1 {
                await withCheckedContinuation {
                    pending = $0
                    started.fulfill()
                }
            }
        }
        let manager = try h.makeManager()
        await fulfillment(of: [started], timeout: 2)

        h.store.samples = [h.sample(125)]
        manager.update(scheduleOverride: nil, preMealOverride: nil, glucoseTargetRangeSchedule: nil, activeInsulin: nil)
        try XCTUnwrap(pending).resume()
        await manager.refresh()

        XCTAssertEqual(h.client.states.map(\.currentGlucose), [125])
        XCTAssertEqual(h.client.endCount, 1)
    }

    func testSettingsNotificationReenablesWithCompleteSnapshot() async throws {
        let h = Harness()
        h.settings.enabled = false
        h.store.samples = [h.sample(100, minutesAgo: 5), h.sample(125)]
        let manager = try h.makeManager()
        await manager.refresh()
        XCTAssertTrue(h.client.states.isEmpty)
        XCTAssertEqual(h.store.fetchCount, 0)
        let published = expectation(description: "Reenabled activity published")
        h.client.onPublish = { _ in published.fulfill() }

        h.settings.enabled = true
        h.center.post(name: .LiveActivitySettingsChanged, object: nil)
        await fulfillment(of: [published], timeout: 2)

        XCTAssertEqual(h.client.states.count, 1)
        XCTAssertEqual(h.client.states.last?.glucoseSamples.count, 2)
        XCTAssertEqual(h.client.states.last?.currentGlucose, 125)
        withExtendedLifetime(manager) {}
    }

    func testForegroundReusesActiveActivityAndRecreatesExpiredActivity() async throws {
        let h = Harness()
        h.store.samples = [h.sample(100)]
        let manager = try h.makeManager()
        await manager.refresh()
        let reused = expectation(description: "Existing activity refreshed on foreground")
        h.client.onPublish = { _ in reused.fulfill() }
        h.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await fulfillment(of: [reused], timeout: 2)
        XCTAssertEqual(h.client.endCount, 1)

        h.client.recreationNeeded = true
        h.store.samples = [h.sample(125)]
        let published = expectation(description: "Recreated activity published")
        h.client.onPublish = { _ in published.fulfill() }
        h.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await fulfillment(of: [published], timeout: 2)

        XCTAssertEqual(h.client.endCount, 2)
        XCTAssertEqual(h.client.states.last?.glucoseSamples.last?.y, 125)
        withExtendedLifetime(manager) {}
    }

    func testFailedQueryPreservesPublishedSnapshot() async throws {
        let h = Harness()
        h.store.samples = [h.sample(100)]
        let manager = try h.makeManager()
        await manager.refresh()
        h.store.fetch = { throw TestError.failed }

        await manager.refresh()

        XCTAssertEqual(h.client.states.map(\.currentGlucose), [100])
    }

    private enum TestError: Error { case failed }

    @MainActor
    private final class Harness {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let center = NotificationCenter()
        let store = TestGlucoseStore()
        let client = TestActivityClient()
        var unit: LoopUnit = .milligramsPerDeciliter
        var settings = LiveActivitySettings()
        var context: StatusExtensionContext?

        func sample(_ value: Double, minutesAgo: Double = 0, trend: GlucoseTrend? = nil) -> StoredGlucoseSample {
            StoredGlucoseSample(
                startDate: date.addingTimeInterval(-.minutes(minutesAgo)),
                quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: value),
                trend: trend
            )
        }

        func makeManager() throws -> LiveActivityManager {
            try XCTUnwrap(LiveActivityManager(
                glucoseStore: store,
                glucoseUnit: { self.unit },
                client: client,
                notificationCenter: center,
                settings: { self.settings },
                statusContext: { self.context },
                now: { self.date }
            ))
        }
    }

    private final class TestGlucoseStore: MockGlucoseStore {
        var samples: [StoredGlucoseSample] = []
        var fetch: (@MainActor () async throws -> [StoredGlucoseSample])?
        @MainActor private(set) var fetchCount = 0

        override func getGlucoseSamples(start: Date?, end: Date?) async throws -> [StoredGlucoseSample] {
            try await fetchOnMainActor()
        }

        @MainActor
        private func fetchOnMainActor() async throws -> [StoredGlucoseSample] {
            fetchCount += 1
            if let fetch { return try await fetch() }
            return samples
        }
    }

    @MainActor
    private final class TestActivityClient: LiveActivityClient {
        var activitiesEnabled = true
        var canCreateActivity = true
        var recreationNeeded = false
        var states: [GlucoseActivityAttributes.ContentState] = []
        var endCount = 0
        var maxConcurrentPublications = 0
        private var concurrentPublications = 0
        var onPublish: ((GlucoseActivityAttributes.ContentState) async -> Void)?
        var onEnd: (() async -> Void)?

        func needsRecreation(settings: LiveActivitySettings) -> Bool { recreationNeeded }

        func endActivities() async {
            endCount += 1
            await onEnd?()
            recreationNeeded = false
        }

        func publish(_ state: GlucoseActivityAttributes.ContentState, settings: LiveActivitySettings) async throws {
            concurrentPublications += 1
            maxConcurrentPublications = max(maxConcurrentPublications, concurrentPublications)
            await onPublish?(state)
            states.append(state)
            concurrentPublications -= 1
        }
    }
}
