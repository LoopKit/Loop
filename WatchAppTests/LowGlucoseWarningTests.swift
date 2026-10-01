//  NOT IN THE WatchAppTests TARGET — and deliberately kept anyway.
//
//  The behaviour it covers (`WatchLowGlucoseWarning`, `LoanLowBGWarningSettings`) has not been
//  ported to this tree yet: it lives in the fork's `WatchApp Extension/StockLoop/` and its
//  settings ride in the fork's `LoanProtocolV2`. Deleting the suite would erase the only record
//  of what that feature is supposed to do; leaving it in the target would break the build for
//  everyone. So it sits here, visible in the project navigator, compiling for nobody, until the
//  feature lands — at which point add it back to the target and it should pass as written.
//
//  LowGlucoseWarningTests.swift
//  WatchAppTests
//
//  The predicted-low warning's decision, which is a truth table over three predictions and a set
//  of gates. Table-shaped logic hides table-shaped bugs: a transposed case or an inverted gate
//  reads perfectly and simply warns about the wrong thing, or stays silent when it should not.
//
//  Worth pinning on the wrist specifically because the watch OWNS this warning during a loan —
//  the phone stands down, so a wrong cell here is not a second opinion, it is the only one.
//
//  The evaluator is a pure function of its inputs, so every case below is exact: predictions are
//  synthesized to cross (or not cross) the warning level on demand, and the clock is injected.
//

import XCTest
import HealthKit
import LoopKit
import LoopCore
@testable import WatchApp

final class LowGlucoseWarningTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let mgdl = HKUnit.milligramsPerDeciliter

    // Suspend threshold 70, day offset 5 → warning level 65.
    private func settings(enabled: Bool = true,
                          nightWarningsEnabled: Bool = true,
                          snooze: TimeInterval = .minutes(9),
                          sooner: TimeInterval = .minutes(5),
                          later: TimeInterval = .minutes(45),
                          carbDelay: TimeInterval = .minutes(30),
                          lastNotification: Date? = nil) -> LoanLowBGWarningSettings {
        LoanLowBGWarningSettings(
            enabled: enabled,
            nightWarningsEnabled: nightWarningsEnabled,
            dayWarningOffset: 5, nightWarningOffset: 10,
            warningSnooze: snooze, dontWarnIfSooner: sooner, dontWarnIfLater: later,
            delayAfterCarbEntry: carbDelay,
            nightStartMinutes: 22 * 60 + 30, nightEndMinutes: 6 * 60 + 30,
            glucoseUnitString: HKUnit.milligramsPerDeciliter.unitString,
            lastNotificationTime: lastNotification)
    }

    /// A prediction that either dives below the warning level at +20 min or stays flat at 120.
    /// Anchored to `from` so a test that moves the clock moves the prediction with it — otherwise
    /// every interval is measured against a curve that already happened.
    private func prediction(crosses: Bool, from: Date? = nil) -> [PredictedGlucoseValue] {
        let anchor = from ?? t0
        return (0..<73).map { i in
            let date = anchor.addingTimeInterval(TimeInterval(i) * 5 * 60)
            let value: Double
            if crosses {
                value = i < 4 ? 120 - Double(i) * 15 : 55
            } else {
                value = 120
            }
            return PredictedGlucoseValue(startDate: date, quantity: HKQuantity(unit: mgdl, doubleValue: value))
        }
    }

    private func inputs(p1: Bool, p2: Bool, p3: Bool,
                        settings s: LoanLowBGWarningSettings? = nil,
                        lastCarbEntry: Date? = nil,
                        lastNotificationTime: Date? = nil,
                        now: Date? = nil) -> WatchLowGlucoseWarning.Inputs {
        WatchLowGlucoseWarning.Inputs(
            predictionWithZeroTemp: prediction(crosses: p1, from: now),
            predictionWithObservedAbsorption: prediction(crosses: p2, from: now),
            predictionWithObservedAbsorptionAndZeroTemp: prediction(crosses: p3, from: now),
            absorptionRatio: 0.6,
            suspendThreshold: HKQuantity(unit: mgdl, doubleValue: 70),
            displayUnit: mgdl,
            insulinSensitivity: 50, carbRatio: 10,
            correctionTarget: 100,
            mostRecentCarbEntryDate: lastCarbEntry,
            lastNotificationTime: lastNotificationTime,
            now: now ?? t0,
            settings: s ?? settings())
    }

    // MARK: - The truth table

    func testEveryCellOfTheTruthTable() {
        typealias Outcome = WatchLowGlucoseWarning.Outcome
        // (P1 zero-temp, P2 observed, P3 observed+zero-temp) -> outcome
        //
        // Every row where P2 does not cross is `.none`, and that is structural rather than a
        // missing case: the "observed absorption does not cross, no warning needed" guard returns
        // before the table is consulted, on both devices. An advisory class used to sit on the
        // two (T,F,·) rows and could therefore never fire; it was removed rather than given the
        // separate timing anchor and snooze it would have needed. Pinned so a future reader sees
        // the silence is intended and does not "restore" a branch that cannot run.
        let table: [(p1: Bool, p2: Bool, p3: Bool, expected: Outcome, why: String)] = [
            (true,  true,  true,  .carbsDefinitelyNeeded, "low lands even with zero temping and full absorption"),
            (true,  true,  false, .carbsDefinitelyNeeded, "privileges the first True; same aggressive warning"),
            (false, true,  true,  .rescueCarbsLikelyNeeded, "observed absorption sends you low, low temping cannot save it"),
            (false, true,  false, .mayAvoidRescueCarbsWithEditing, "observed absorption sends you low, low temping might help"),
            (true,  false, false, .none, "unreachable: the P2 guard returns before the table"),
            (true,  false, true,  .none, "unreachable: same P2 guard"),
            (false, false, true,  .none, "unreachable: same P2 guard"),
            (false, false, false, .none, "ordinary no-warning case"),
        ]

        for row in table {
            let (outcome, context) = WatchLowGlucoseWarning.evaluate(
                inputs(p1: row.p1, p2: row.p2, p3: row.p3))
            XCTAssertEqual(outcome, row.expected,
                           "(\(row.p1),\(row.p2),\(row.p3)) should be \(row.expected) — \(row.why)")
            if row.expected == .none {
                XCTAssertNil(context, "silence carries no context")
            } else if let context = context {
                XCTAssertNotNil(WatchLowGlucoseWarning.messages(for: outcome, context: context),
                                "a warning must be able to render its message")
            } else {
                XCTFail("(\(row.p1),\(row.p2),\(row.p3)) warned but carried no context")
            }
        }
    }

    /// The phone traps here. On a wrist, while this device is the only thing driving the pod,
    /// a trap is strictly worse than a missed warning.
    func testNoneOutcomeReturnsNilRatherThanTrapping() {
        let empty = WatchLowGlucoseWarning.PredictionMetrics(
            minimumGlucoseValue: nil, glucoseValueAtAbsorptionTime: nil,
            timeToMinimumGlucose: nil, timeToCrossThreshold: nil, velocityAtThresholdCrossing: nil)
        let context = WatchLowGlucoseWarning.Context(
            standardWithSuspend: empty, observedAbsorption: empty, observedAbsorptionWithSuspend: empty,
            rescueCarbMessageStr: nil, absorptionRatio: 1, displayUnit: mgdl)
        XCTAssertNil(WatchLowGlucoseWarning.messages(for: .none, context: context))
    }

    // MARK: - Gates

    func testDisabledByThePhoneStaysSilent() {
        let (outcome, _) = WatchLowGlucoseWarning.evaluate(
            inputs(p1: true, p2: true, p3: true, settings: settings(enabled: false)))
        XCTAssertEqual(outcome, .none, "the phone's master switch must be honoured on the wrist")
    }

    func testSnoozeSuppressesASecondWarning() {
        // Warned 3 minutes ago, snooze is 9.
        let (suppressed, _) = WatchLowGlucoseWarning.evaluate(
            inputs(p1: false, p2: true, p3: true, lastNotificationTime: t0.addingTimeInterval(-.minutes(3))))
        XCTAssertEqual(suppressed, .none)

        // ...and 10 minutes ago is past it.
        let (allowed, _) = WatchLowGlucoseWarning.evaluate(
            inputs(p1: false, p2: true, p3: true, lastNotificationTime: t0.addingTimeInterval(-.minutes(10))))
        XCTAssertEqual(allowed, .rescueCarbsLikelyNeeded)
    }

    func testRecentCarbsSuppressMostClassesButNotTheAggressiveOne() {
        let justAte = t0.addingTimeInterval(-.minutes(5))   // inside the 30 min delay

        let (softened, _) = WatchLowGlucoseWarning.evaluate(
            inputs(p1: false, p2: true, p3: true, lastCarbEntry: justAte))
        XCTAssertEqual(softened, .none, "a low already being treated should not warn")

        let (aggressive, _) = WatchLowGlucoseWarning.evaluate(
            inputs(p1: true, p2: true, p3: true, lastCarbEntry: justAte))
        XCTAssertEqual(aggressive, .carbsDefinitelyNeeded,
                       "the (T,T,*) case fires even on recent carbs — the low lands regardless")
    }

    func testNightWarningsHonourTheInheritedFlag() {
        // 02:00 local, inside the 22:30–06:30 window.
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: t0)
        comps.hour = 2; comps.minute = 0
        let night = Calendar.current.date(from: comps)!

        let (off, _) = WatchLowGlucoseWarning.evaluate(
            inputs(p1: true, p2: true, p3: true,
                   settings: settings(nightWarningsEnabled: false), now: night))
        XCTAssertEqual(off, .none, "night warnings disabled means silence overnight")

        let (on, _) = WatchLowGlucoseWarning.evaluate(
            inputs(p1: true, p2: true, p3: true,
                   settings: settings(nightWarningsEnabled: true), now: night))
        XCTAssertEqual(on, .carbsDefinitelyNeeded, "night warnings enabled means the wrist still speaks")
    }

    func testNightWindowWrapsPastMidnight() {
        let s = settings()
        func at(_ hour: Int, _ minute: Int) -> Date {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: t0)
            c.hour = hour; c.minute = minute
            return Calendar.current.date(from: c)!
        }
        XCTAssertTrue(s.isNightTime(at: at(23, 0)), "before midnight is night")
        XCTAssertTrue(s.isNightTime(at: at(2, 0)), "after midnight is still night")
        XCTAssertFalse(s.isNightTime(at: at(12, 0)), "midday is not night")
        XCTAssertFalse(s.isNightTime(at: at(22, 0)), "22:00 is before the window opens")
    }

    func testMissingTherapySettingsStaySilentRatherThanGuessing() {
        var input = inputs(p1: true, p2: true, p3: true)
        input = WatchLowGlucoseWarning.Inputs(
            predictionWithZeroTemp: input.predictionWithZeroTemp,
            predictionWithObservedAbsorption: input.predictionWithObservedAbsorption,
            predictionWithObservedAbsorptionAndZeroTemp: input.predictionWithObservedAbsorptionAndZeroTemp,
            absorptionRatio: input.absorptionRatio,
            suspendThreshold: nil,                       // <- the thing the warning level is built from
            displayUnit: mgdl, insulinSensitivity: 50, carbRatio: 10, correctionTarget: 100,
            mostRecentCarbEntryDate: nil, lastNotificationTime: nil, now: t0, settings: settings())
        let (outcome, context) = WatchLowGlucoseWarning.evaluate(input)
        XCTAssertEqual(outcome, .none)
        XCTAssertNil(context)
    }

    func testEmptyPredictionsStaySilent() {
        let input = WatchLowGlucoseWarning.Inputs(
            predictionWithZeroTemp: [], predictionWithObservedAbsorption: [],
            predictionWithObservedAbsorptionAndZeroTemp: [],
            absorptionRatio: 1,
            suspendThreshold: HKQuantity(unit: mgdl, doubleValue: 70), displayUnit: mgdl,
            insulinSensitivity: 50, carbRatio: 10, correctionTarget: 100,
            mostRecentCarbEntryDate: nil, lastNotificationTime: nil, now: t0, settings: settings())
        let (outcome, _) = WatchLowGlucoseWarning.evaluate(input)
        XCTAssertEqual(outcome, .none, "no prediction, no opinion")
    }
}
