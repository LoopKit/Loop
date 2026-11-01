//
//  SetupChangeTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
@testable import Loop

final class SetupChangeTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func settings(
        at hours: Double,
        basal: Double = 1.0,
        isf: Double = 50,
        isfUnit: LoopUnit = .milligramsPerDeciliter,
        maximumBolus: Double = 10,
        strategy: AutomaticDosingStrategy = .automaticBolus,
        dosingEnabled: Bool = true,
        deviceToken: String? = nil,
        insulinType: InsulinType? = .novolog,
        timeZone: TimeZone = TimeZone(identifier: "America/Chicago")!
    ) -> StoredSettings {
        StoredSettings(
            date: start.addingTimeInterval(.hours(hours)),
            dosingEnabled: dosingEnabled,
            maximumBolus: maximumBolus,
            deviceToken: deviceToken,
            insulinType: insulinType,
            basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: basal)], timeZone: timeZone),
            insulinSensitivitySchedule: InsulinSensitivitySchedule(unit: isfUnit, dailyItems: [RepeatingScheduleValue(startTime: 0, value: isf)], timeZone: timeZone),
            automaticDosingStrategy: strategy)
    }

    private func experiments(at hours: Double, _ identifiers: [String]?) -> ExperimentsRecord {
        ExperimentsRecord(date: start.addingTimeInterval(.hours(hours)), algorithmExperiments: identifiers?.map { AlgorithmExperiment(identifier: $0) })
    }

    private func history(_ settings: [StoredSettings], _ experiments: [ExperimentsRecord] = []) -> SetupHistory {
        SetupHistory(settings: settings, experiments: experiments)
    }

    func testNoChangeIsLowerBoundAtOldestRecord() {
        let change = history([settings(at: 5), settings(at: 0), settings(at: 10)]).latest
        XCTAssertEqual(change, SetupChange(date: start, isLowerBound: true, items: []))
    }

    func testEmptyHistory() {
        XCTAssertNil(history([]).latest)
    }

    func testEveryChangeWithItsPreviousDate() {
        let history = history([settings(at: 0), settings(at: 10, basal: 1.2), settings(at: 20, basal: 1.2, maximumBolus: 8)])
        XCTAssertEqual(history.changes, [
            SetupChange(date: start.addingTimeInterval(.hours(10)), isLowerBound: false, items: [.therapySetting(.basalRate)], previousDate: start),
            SetupChange(date: start.addingTimeInterval(.hours(20)), isLowerBound: false, items: [.therapySetting(.deliveryLimits)], previousDate: start.addingTimeInterval(.hours(10))),
        ])
        XCTAssertEqual(history.end(of: history.changes[0]), start.addingTimeInterval(.hours(20)))
        XCTAssertNil(history.end(of: history.changes[1]))
    }

    func testInitialSetup() {
        let onboarding = StoredSettings(date: start, dosingEnabled: false)
        let history = history([onboarding, settings(at: 0.1), settings(at: 10, basal: 1.2)])
        XCTAssertEqual(history.changes.map(\.isInitialSetup), [true, false])
    }

    func testRecordsWithoutTherapySettingsAreSkipped() {
        let empty = StoredSettings(date: start.addingTimeInterval(.hours(5)), dosingEnabled: false)
        let history = history([settings(at: 0), empty, settings(at: 6), settings(at: 10, basal: 1.2)])
        XCTAssertEqual(history.changes.map(\.date), [start.addingTimeInterval(.hours(10))])
        XCTAssertEqual(history.changes.map(\.isInitialSetup), [false])
    }

    func testChangesWithinAnHourAreGrouped() {
        let change = history([settings(at: 0), settings(at: 10, isf: 45), settings(at: 10.5, isf: 45, strategy: .tempBasalOnly)]).latest
        XCTAssertEqual(change?.date, start.addingTimeInterval(.hours(10.5)))
        XCTAssertEqual(change?.items, [.dosingStrategy, .therapySetting(.insulinSensitivity)])
        XCTAssertEqual(change?.previousDate, start)
    }

    func testIgnoredChanges() {
        let other = TimeZone(identifier: "Europe/Paris")!
        let change = history([
            settings(at: 0),
            settings(at: 1, dosingEnabled: false),
            settings(at: 2, deviceToken: "abc"),
            settings(at: 3, timeZone: other),
            settings(at: 4, insulinType: nil),
            settings(at: 5),
        ]).latest
        XCTAssertEqual(change, SetupChange(date: start, isLowerBound: true, items: []))
    }

    func testInsulinTypeChange() {
        let change = history([settings(at: 0), settings(at: 1, insulinType: nil), settings(at: 2, insulinType: .fiasp)]).latest
        XCTAssertEqual(change?.items, [.insulinType])
        XCTAssertEqual(change?.date, start.addingTimeInterval(.hours(2)))
    }

    func testSameSensitivityInAnotherUnitIsNotAChange() {
        let mmol = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 50).doubleValue(for: .millimolesPerLiter)
        let change = history([settings(at: 0), settings(at: 1, isf: (mmol * 10).rounded() / 10, isfUnit: .millimolesPerLiter)]).latest
        XCTAssertEqual(change?.isLowerBound, true)
    }

    func testExperimentChangesFromDosingDecisions() {
        let history = history([settings(at: 0)], [
            experiments(at: 1, nil),
            experiments(at: 2, []),
            experiments(at: 3, []),
            experiments(at: 4, ["guardAndRunway"]),
            experiments(at: 5, ["guardAndRunway", "unknownExperiment"]),
            experiments(at: 6, nil),
            experiments(at: 8, ["integralRetrospectiveCorrection"]),
        ])
        XCTAssertEqual(history.changes, [
            SetupChange(date: start.addingTimeInterval(.hours(4)), isLowerBound: false, items: [.experiment(.guardAndRunway, enabled: true)], previousDate: start),
            SetupChange(date: start.addingTimeInterval(.hours(8)), isLowerBound: false, items: [.experiment(.guardAndRunway, enabled: false), .experiment(.integralRetrospectiveCorrection, enabled: true)], previousDate: start.addingTimeInterval(.hours(4))),
        ])
    }

    func testCloseSettingsAndExperimentChangesAreGrouped() {
        let change = history(
            [settings(at: 0), settings(at: 10, strategy: .tempBasalOnly)],
            [experiments(at: 9, ["glucoseBasedApplicationFactor"]), experiments(at: 10.1, [])]
        ).latest
        XCTAssertEqual(change?.date, start.addingTimeInterval(.hours(10.1)))
        XCTAssertEqual(change?.items, [.experiment(.glucoseBasedApplicationFactor, enabled: false), .dosingStrategy])
    }

    func testTransitionsKeepOnlyChanges() {
        let records = [experiments(at: 0, nil), experiments(at: 1, []), experiments(at: 2, []), experiments(at: 3, ["guardAndRunway"]), experiments(at: 4, ["guardAndRunway"])]
        XCTAssertEqual(ExperimentsRecord.transitions(records), [experiments(at: 1, []), experiments(at: 3, ["guardAndRunway"])])
    }

    func testCacheReadsEachDecisionOnce() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let cache = ExperimentsHistoryCache(defaults: defaults)
        let all = [experiments(at: 1, []), experiments(at: 2, []), experiments(at: 3, ["guardAndRunway"]), experiments(at: 5, [])]
        var reads: [Date] = []
        func read(_ from: Date, until end: Date) -> [ExperimentsRecord] {
            reads.append(from)
            return all.filter { $0.date >= from && $0.date < end }
        }

        let first = try await cache.records(since: start, now: start.addingTimeInterval(.hours(4))) { read($0, until: start.addingTimeInterval(.hours(4))) }
        XCTAssertEqual(first, [experiments(at: 1, []), experiments(at: 3, ["guardAndRunway"])])

        let second = try await cache.records(since: start.addingTimeInterval(.hours(2)), now: start.addingTimeInterval(.hours(6))) { read($0, until: start.addingTimeInterval(.hours(6))) }
        XCTAssertEqual(reads, [start, start.addingTimeInterval(.hours(4))])
        XCTAssertEqual(second, [experiments(at: 1, []), experiments(at: 3, ["guardAndRunway"]), experiments(at: 5, [])])
    }

    func testStartIgnoresDecisionsWithoutExperiments() {
        let history = history([settings(at: 5)], [experiments(at: 1, nil), experiments(at: 3, [])])
        XCTAssertEqual(history.start, start.addingTimeInterval(.hours(3)))
    }
}
