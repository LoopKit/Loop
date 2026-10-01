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
