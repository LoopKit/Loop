//
//  WristOverrideRecordTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  An override set on the wrist during a loan is journaled, so it reaches the phone at hand-back.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import WatchApp

final class WristOverrideRecordTests: XCTestCase {

    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WristOverrideRecordTests-\(UUID().uuidString)")!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func override() -> TemporaryScheduleOverride {
        TemporaryScheduleOverride(context: .custom,
                                  settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter, targetRange: nil,
                                                                    insulinNeedsScaleFactor: 0.5),
                                  startDate: Date(), duration: .indefinite, enactTrigger: .local, syncIdentifier: UUID())
    }

    private func liveLoan(supportsOverrideRecords: Bool = true) async throws -> PodLoanWatchController {
        let controller = await makeController()
        controller.send = { _ in }
        try controller.journal.begin(epoch: 5)
        controller.queue.sync {
            controller.epoch = 5
            controller.phase = .active
            controller.phoneSupportsOverrideRecords = supportsOverrideRecords
        }
        return controller
    }

    func testAWristOverrideIsDosedAndJournaled() async throws {
        let controller = try await liveLoan()
        let set = override()

        controller.applyWristOverride(set)
        controller.queue.sync { }

        XCTAssertEqual(controller.loopManager.scheduleOverride?.syncIdentifier, set.syncIdentifier, "the wrist doses under it")
        let records = controller.journal.unackedEvents().map(\.record)
        XCTAssertEqual(records.map(\.kind), [.overrideChange], "the journal carries it to the phone")
        XCTAssertFalse(records.first?.overrideChangeIsClear ?? true)
    }

    func testClearingOnTheWristIsJournaledToo() async throws {
        let controller = try await liveLoan()

        controller.applyWristOverride(nil)
        controller.queue.sync { }

        let records = controller.journal.unackedEvents().map(\.record)
        XCTAssertEqual(records.map(\.kind), [.overrideChange])
        XCTAssertTrue(records.first?.overrideChangeIsClear ?? false)
    }

    func testAPhoneWithoutOverrideRecordsGetsNoRecord() async throws {
        let controller = try await liveLoan(supportsOverrideRecords: false)

        controller.applyWristOverride(override())
        controller.queue.sync { }

        XCTAssertTrue(controller.journal.unackedEvents().isEmpty)
        XCTAssertNotNil(controller.loopManager.scheduleOverride, "still dosed on the wrist")
    }

    // MARK: - Pre-meal, ended where stock ends it

    private func preMeal() -> TemporaryScheduleOverride {
        TemporaryScheduleOverride(context: .preMeal,
                                  settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter,
                                                                    targetRange: DoubleRange(minValue: 80, maxValue: 80)),
                                  startDate: Date().addingTimeInterval(-600), duration: .finite(3600),
                                  enactTrigger: .local, syncIdentifier: UUID())
    }

    private func meal() -> NewCarbEntry {
        NewCarbEntry(quantity: LoopQuantity(unit: .gram, doubleValue: 30), startDate: Date(), foodType: nil,
                     absorptionTime: .hours(3))
    }

    private func saveCarbs(_ controller: PodLoanWatchController) async {
        let saved = expectation(description: "saved")
        controller.loanDidRecordCarbs(meal()) { _ in saved.fulfill() }
        await fulfillment(of: [saved], timeout: 10)
        controller.queue.sync { }
    }

    /// Stock `LoopDataManager.addCarbEntry`: saving carbs ends a pre-meal preset, and the wrist's
    /// clear is journaled for the phone.
    func testSavingCarbsOnTheWristEndsPreMeal() async throws {
        let controller = try await liveLoan()
        controller.applyWristOverride(preMeal())
        controller.queue.sync { }

        await saveCarbs(controller)

        XCTAssertNil(controller.loopManager.scheduleOverride, "pre-meal ended")
        let overrides = controller.journal.unackedEvents().map(\.record).filter { $0.kind == .overrideChange }
        XCTAssertEqual(overrides.count, 2, "set, then cleared")
        XCTAssertTrue(overrides.last?.overrideChangeIsClear ?? false, "the phone is told")
    }

    /// Any other preset stays, as in stock.
    func testSavingCarbsLeavesAnotherPresetRunning() async throws {
        let controller = try await liveLoan()
        let set = override()
        controller.applyWristOverride(set)
        controller.queue.sync { }

        await saveCarbs(controller)

        XCTAssertEqual(controller.loopManager.scheduleOverride?.syncIdentifier, set.syncIdentifier)
    }

    /// Stock ends pre-meal when automatic dosing is turned off: the wrist, when its loop is opened.
    func testOpeningTheLoopOnTheWristEndsPreMeal() async throws {
        let controller = try await liveLoan()
        let loop = controller.loopManager
        loop.onLoopOpened = { [weak controller] in controller?.endPreMealOverride(reason: "test") }
        loop.setClosedLoopEnabled(true, reason: "test")
        controller.applyWristOverride(preMeal())
        controller.queue.sync { }

        loop.setClosedLoopEnabled(true, reason: "test")
        XCTAssertNotNil(loop.scheduleOverride, "closing it again changes nothing")

        loop.setClosedLoopEnabled(false, reason: "test")
        loop.dataAccessQueue.sync { }
        controller.queue.sync { }

        XCTAssertNil(loop.scheduleOverride, "pre-meal ended")
        let overrides = controller.journal.unackedEvents().map(\.record).filter { $0.kind == .overrideChange }
        XCTAssertTrue(overrides.last?.overrideChangeIsClear ?? false, "the phone is told")
    }

    private func makeController() async -> PodLoanWatchController {
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "WristOverrideRecordTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: 4 * 60 * 60, provenanceIdentifier: "WristOverrideRecordTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: 24 * 60 * 60, provenanceIdentifier: "WristOverrideRecordTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: dir)
        return PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: dir),
                                      stateDirectory: dir)
    }
}

/// A cancelled temp reaches the phone as a zero-length rate record (2026-10-09: six cancels in an overnight
/// loan were never journaled, leaving the cancelled temps standing in the phone's books).
final class LoanCancelRecordTests: XCTestCase {
    private let now = Date()

    /// The schedule resuming — how the pump manager reports a cancel — is journaled as a zero-length temp.
    func testTheScheduleResumingIsJournaledAsACancel() {
        let resume = DoseEntry(type: .basal, startDate: now, endDate: now, value: 0.6, unit: .unitsPerHour, decisionId: nil)
        let record = PodLoanWatchController.loanRecord(for: resume, raw: Data([0x01, 0x02]))
        XCTAssertEqual(record?.kind, .tempBasal)
        XCTAssertEqual(record?.startDate, now)
        XCTAssertEqual(record?.endDate, now)
        XCTAssertEqual(record?.unitsPerHour, 0)
        XCTAssertEqual(record?.syncIdentifier, "0102")
    }

    /// Scheduled basal over a span is still not a wrist command.
    func testScheduledBasalOverASpanIsNotJournaled() {
        let basal = DoseEntry(type: .basal, startDate: now, endDate: now.addingTimeInterval(300), value: 0.6,
                              unit: .unitsPerHour, decisionId: nil)
        XCTAssertNil(PodLoanWatchController.loanRecord(for: basal, raw: Data([0x03])))
    }
}
