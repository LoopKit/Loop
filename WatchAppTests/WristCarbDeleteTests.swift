//
//  WristCarbDeleteTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  A wrist carb is stored and journaled under one identity, the one the phone stores it under,
//  so deleting it after an interim drain committed it still matches on the phone.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import WatchApp

final class WristCarbDeleteTests: XCTestCase {

    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WristCarbDeleteTests-\(UUID().uuidString)")!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func testADeleteAfterAnInterimCommitMatchesThePhonesCopy() async throws {
        let controller = try await liveLoan()
        let meal = NewCarbEntry(quantity: LoopQuantity(unit: .gram, doubleValue: 30),
                                startDate: Date().addingTimeInterval(-600), foodType: nil, absorptionTime: .hours(3))

        controller.loanDidRecordCarbs(meal)
        controller.queue.sync { }
        let local = try await localCarb(controller)
        guard let carbEvent = controller.journal.unackedEvents().first(where: { $0.record.kind == .carb }) else {
            return XCTFail("the carb is journaled")
        }
        XCTAssertEqual(local.syncIdentifier, carbEvent.id.uuidString, "one identity on the wrist and in the journal")

        // The interim drain: the phone stores the carb under the event ID, then acks.
        let committed = LoanReconciler.reconcile(.init(events: [carbEvent], schedule: nil,
                                                       loanStart: Date().addingTimeInterval(-3600), loanEnd: Date(),
                                                       isFinalHandback: false)).carbs
        XCTAssertEqual(committed.count, 1)
        let onPhone = StoredCarbEntry(startDate: meal.startDate, quantity: meal.quantity,
                                      syncIdentifier: committed.first?.eventID.uuidString)
        controller.journal.applyAck(committedCursor: carbEvent.seq)

        // Deleted on the wrist, as the Active Carbs list passes it.
        controller.loanDidDeleteCarb(syncIdentifier: local.syncIdentifier, startDate: local.startDate, grams: 30)
        controller.queue.sync { }

        let drain = LoanReconciler.reconcile(.init(events: controller.journal.unackedEvents(), schedule: nil,
                                                   loanStart: Date().addingTimeInterval(-3600), loanEnd: Date(),
                                                   isFinalHandback: false))
        XCTAssertEqual(drain.deletedCarbs.count, 1, "the delete reaches the phone")
        XCTAssertTrue(drain.deletedCarbs.first?.matches(onPhone) ?? false, "and finds the carb the phone stored")
    }

    private func localCarb(_ controller: PodLoanWatchController) async throws -> StoredCarbEntry {
        for _ in 0..<50 {
            if let entry = try await controller.loopManager.carbStore.getCarbEntries(start: Date().addingTimeInterval(-3600)).first {
                return entry
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("the carb is stored locally")
        throw CancellationError()
    }

    private func liveLoan() async throws -> PodLoanWatchController {
        let controller = await makeController()
        controller.send = { _ in }
        try controller.journal.begin(epoch: 5)
        controller.queue.sync {
            controller.epoch = 5
            controller.phase = .active
        }
        return controller
    }

    private func makeController() async -> PodLoanWatchController {
        let cacheStore = PersistenceController(directoryURL: dir.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "WristCarbDeleteTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: 4 * 60 * 60, provenanceIdentifier: "WristCarbDeleteTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: 24 * 60 * 60, provenanceIdentifier: "WristCarbDeleteTests")
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: dir)
        return PodLoanWatchController(loopManager: manager, journal: LoanEventJournal(directory: dir),
                                      stateDirectory: dir)
    }
}
