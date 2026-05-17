//
//  AppleHealthIRServiceTests.swift
//  LoopTests
//
//  Tests for the 4-threshold / 4-effect biometric IR engine.
//  Each metric uses 5-zone step logic: < T1→E1, < T2→E2, < T3→E3, < T4→E4, ≥T4→0 (or E4 for steps/exercise).
//  Multiplier is clamped to [multiplierMin, multiplierMax] = [0.5, 2.0].
//

import XCTest
import Combine
@testable import Loop

final class AppleHealthIRServiceTests: XCTestCase {

    private var service: AppleHealthIRService!
    private var thresholds: AppleHealthIRThresholds!

    override func setUp() {
        super.setUp()
        thresholds = .default
        service = AppleHealthIRService(thresholds: thresholds)
        UserDefaults.standard.removeObject(forKey: AppleHealthIREntry.userDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppleHealthIREntry.userDefaultsKey)
        service = nil
        thresholds = nil
        super.tearDown()
    }

    // MARK: - AC1: Very short sleep (< T1) raises multiplier by E1 (+30%)

    func testAC1_SleepBelowT1_RaisesMultiplierByE1() {
        let m = service.computeMultiplier(
            sleepHours: thresholds.sleepT1 - 1.0,
            stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.sleepE1 / 100.0, accuracy: 0.001,
            "AC1: sleep < T1 must raise multiplier by E1 (+30%)")
        XCTAssertGreaterThan(m, 1.0)
        XCTAssertEqual(m, 1.30, accuracy: 0.001, "AC1: default E1=30% => multiplier 1.30")
    }

    // MARK: - AC2: Very high steps (>= T4) lowers multiplier by E4 (-6%)

    func testAC2_StepsAtOrAboveT4_LowersMultiplierByE4() {
        let m = service.computeMultiplier(
            sleepHours: nil,
            stepCount: thresholds.stepsT4,
            hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.stepsE4 / 100.0, accuracy: 0.001,
            "AC2: steps >= T4 must lower multiplier by E4 (-6%)")
        XCTAssertLessThan(m, 1.0)
        XCTAssertEqual(m, 0.94, accuracy: 0.001, "AC2: default E4=-6% => multiplier 0.94")
    }

    // MARK: - AC3: Very low HRV (< T1) raises multiplier by E1 (+20%)

    func testAC3_HRVBelowT1_RaisesMultiplierByE1() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil,
            hrvSDNN: thresholds.hrvT1 - 1.0,
            exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.hrvE1 / 100.0, accuracy: 0.001,
            "AC3: HRV < T1 must raise multiplier by E1 (+20%)")
        XCTAssertGreaterThan(m, 1.0)
        XCTAssertEqual(m, 1.20, accuracy: 0.001, "AC3: default E1=20% => multiplier 1.20")
    }

    // MARK: - AC4: Combined positive deltas clamped to multiplierMax (2.0)

    func testAC4_CombinedDeltasAboveCeiling_ClampedToMax() {
        var t = AppleHealthIRThresholds.default
        t.sleepE1 = 80.0
        t.hrvE1   = 80.0
        service.thresholds = t
        let m = service.computeMultiplier(
            sleepHours: 0.0, stepCount: nil, hrvSDNN: 1.0, exerciseMinutes: nil)
        XCTAssertEqual(m, t.multiplierMax, accuracy: 0.001)
        XCTAssertLessThanOrEqual(m, 2.0, "AC4: multiplier must never exceed 2.0")
    }

    // MARK: - AC5: Combined negative deltas clamped to multiplierMin (0.5)

    func testAC5_CombinedDeltasBelowFloor_ClampedToMin() {
        var t = AppleHealthIRThresholds.default
        t.stepsE4     = -80.0
        t.exerciseE4  = -80.0
        service.thresholds = t
        let m = service.computeMultiplier(
            sleepHours: nil,
            stepCount: t.stepsT4,
            hrvSDNN: nil,
            exerciseMinutes: t.exerciseT4)
        XCTAssertEqual(m, t.multiplierMin, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(m, 0.5, "AC5: multiplier must never fall below 0.5")
    }

    // MARK: - AC6: Zone 5 (neutral) — values above T4 contribute 0%

    func testAC6_SleepAboveT4_ReturnsNeutralZone() {
        let m = service.computeMultiplier(
            sleepHours: thresholds.sleepT4 + 1.0,
            stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0, accuracy: 0.001, "Sleep >= T4 is zone 5 (neutral): 0% delta")
    }

    func testAC6_HRVAboveT4_ReturnsNeutralZone() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil,
            hrvSDNN: thresholds.hrvT4 + 1.0,
            exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0, accuracy: 0.001, "HRV >= T4 is zone 5 (neutral): 0% delta")
    }

    // MARK: - AC7: Default thresholds pass validation

    func testAC7_DefaultThresholds_PassValidation() {
        XCTAssertNoThrow(try AppleHealthIRThresholds.default.validate())
    }

    func testAC7_DefaultKeyValues() {
        let t = AppleHealthIRThresholds.default
        XCTAssertEqual(t.sleepE1,   30.0, accuracy: 1e-9, "default sleepE1")
        XCTAssertEqual(t.stepsE4,   -6.0, accuracy: 1e-9, "default stepsE4")
        XCTAssertEqual(t.hrvE1,     20.0, accuracy: 1e-9, "default hrvE1")
        XCTAssertEqual(t.multiplierMin, 0.5, accuracy: 1e-9)
        XCTAssertEqual(t.multiplierMax, 2.0, accuracy: 1e-9)
    }

    // MARK: - AC8: Custom thresholds reflected in computation

    func testAC8_CustomSleepE1_UsedInComputation() {
        var t = AppleHealthIRThresholds.default
        t.sleepE1 = 40.0
        service.thresholds = t
        let m = service.computeMultiplier(
            sleepHours: t.sleepT1 - 1.0,
            stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + 40.0 / 100.0, accuracy: 0.001,
            "AC8: custom sleepE1 must be used, not a hardcoded constant")
    }

    // MARK: - AC9: Log entries have required fields

    func testAC9_LogEntries_HaveRequiredFields() {
        service.updateBiometrics(sleepHours: 3.5, stepCount: 10_000, hrvSDNN: 15.0, exerciseMinutes: 45.0)
        let entries = AppleHealthIREntry.load()
        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            XCTAssertLessThan(entry.timestamp.timeIntervalSinceNow, 5.0)
            XCTAssertFalse(entry.sleepDelta.isNaN)
            XCTAssertFalse(entry.stepsDelta.isNaN)
            XCTAssertFalse(entry.hrvDelta.isNaN)
            XCTAssertFalse(entry.exerciseDelta.isNaN)
            XCTAssertFalse(entry.multiplier.isNaN)
            XCTAssertGreaterThanOrEqual(entry.multiplier, 0.5)
            XCTAssertLessThanOrEqual(entry.multiplier, 2.0)
            XCTAssertNoThrow(try entry.thresholdsSnapshot.validate())
        }
    }

    // MARK: - AC10: All nil inputs => multiplier == 1.0

    func testAC10_AllNilInputs_MultiplierIsUnity() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0, accuracy: 0.001)
    }

    // MARK: - Sleep delta: all 5 zones

    func testSleepDelta_Zone1_BelowT1_ReturnsE1() {
        let m = service.computeMultiplier(sleepHours: 3.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.sleepE1 / 100.0, accuracy: 0.001)
    }

    func testSleepDelta_Zone2_T1toT2_ReturnsE2() {
        let m = service.computeMultiplier(sleepHours: 5.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.sleepE2 / 100.0, accuracy: 0.001)
    }

    func testSleepDelta_Zone3_T2toT3_ReturnsE3() {
        let m = service.computeMultiplier(sleepHours: 6.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.sleepE3 / 100.0, accuracy: 0.001)
    }

    func testSleepDelta_Zone4_T3toT4_ReturnsE4() {
        let m = service.computeMultiplier(sleepHours: 7.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.sleepE4 / 100.0, accuracy: 0.001)
    }

    func testSleepDelta_Zone5_AboveT4_ReturnsZero() {
        let m = service.computeMultiplier(sleepHours: 9.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0, accuracy: 0.001)
    }

    // MARK: - Steps delta: all 5 zones

    func testStepsDelta_Zone1_BelowT1_ReturnsZero() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: 1000, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0, accuracy: 0.001, "Steps < T1 contribute 0 delta")
    }

    func testStepsDelta_Zone2_T1toT2_ReturnsE1() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: 3000, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.stepsE1 / 100.0, accuracy: 0.001)
    }

    func testStepsDelta_Zone3_T2toT3_ReturnsE2() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: 6000, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.stepsE2 / 100.0, accuracy: 0.001)
    }

    func testStepsDelta_Zone4_T3toT4_ReturnsE3() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: 10000, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.stepsE3 / 100.0, accuracy: 0.001)
    }

    func testStepsDelta_Zone5_AtOrAboveT4_ReturnsE4() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: 15000, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.stepsE4 / 100.0, accuracy: 0.001)
    }

    // MARK: - HRV delta: all 5 zones

    func testHRVDelta_Zone1_BelowT1_ReturnsE1() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: 10.0, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.hrvE1 / 100.0, accuracy: 0.001)
    }

    func testHRVDelta_Zone2_T1toT2_ReturnsE2() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: 25.0, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.hrvE2 / 100.0, accuracy: 0.001)
    }

    func testHRVDelta_Zone3_T2toT3_ReturnsE3() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: 42.0, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.hrvE3 / 100.0, accuracy: 0.001)
    }

    func testHRVDelta_Zone4_T3toT4_ReturnsE4() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: 60.0, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.hrvE4 / 100.0, accuracy: 0.001)
    }

    func testHRVDelta_Zone5_AboveT4_ReturnsZero() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: 80.0, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0, accuracy: 0.001)
    }

    // MARK: - Exercise delta: all 5 zones

    func testExerciseDelta_Zone1_BelowT1_ReturnsZero() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: 5.0)
        XCTAssertEqual(m, 1.0, accuracy: 0.001, "Exercise < T1 contributes 0 delta")
    }

    func testExerciseDelta_Zone2_T1toT2_ReturnsE1() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: 20.0)
        XCTAssertEqual(m, 1.0 + thresholds.exerciseE1 / 100.0, accuracy: 0.001)
    }

    func testExerciseDelta_Zone3_T2toT3_ReturnsE2() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: 45.0)
        XCTAssertEqual(m, 1.0 + thresholds.exerciseE2 / 100.0, accuracy: 0.001)
    }

    func testExerciseDelta_Zone4_T3toT4_ReturnsE3() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: 90.0)
        XCTAssertEqual(m, 1.0 + thresholds.exerciseE3 / 100.0, accuracy: 0.001)
    }

    func testExerciseDelta_Zone5_AtOrAboveT4_ReturnsE4() {
        let m = service.computeMultiplier(sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: 150.0)
        XCTAssertEqual(m, 1.0 + thresholds.exerciseE4 / 100.0, accuracy: 0.001)
    }

    // MARK: - Clamp: floor and ceiling hold under extreme deltas

    func testMultiplier_Floor_HoldsUnderExtremeNegativeDeltas() {
        var t = AppleHealthIRThresholds.default
        t.stepsE4    = -500.0
        t.exerciseE4 = -500.0
        service.thresholds = t
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: t.stepsT4, hrvSDNN: nil, exerciseMinutes: t.exerciseT4)
        XCTAssertGreaterThanOrEqual(m, 0.5)
        XCTAssertEqual(m, t.multiplierMin, accuracy: 0.001)
    }

    func testMultiplier_Ceiling_HoldsUnderExtremePositiveDeltas() {
        var t = AppleHealthIRThresholds.default
        t.sleepE1 = 500.0
        t.hrvE1   = 500.0
        service.thresholds = t
        let m = service.computeMultiplier(sleepHours: 0.0, stepCount: nil, hrvSDNN: 1.0, exerciseMinutes: nil)
        XCTAssertLessThanOrEqual(m, 2.0)
        XCTAssertEqual(m, t.multiplierMax, accuracy: 0.001)
    }

    // MARK: - Combined direction

    func testMultiplier_CombinedPositiveDeltas_RaisesMultiplier() {
        let m = service.computeMultiplier(sleepHours: 2.0, stepCount: nil, hrvSDNN: 10.0, exerciseMinutes: nil)
        XCTAssertGreaterThan(m, 1.0)
    }

    func testMultiplier_CombinedNegativeDeltas_LowersMultiplier() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: thresholds.stepsT4, hrvSDNN: nil,
            exerciseMinutes: thresholds.exerciseT4)
        XCTAssertLessThan(m, 1.0)
    }

    // MARK: - Validation

    func testThresholdsValidate_InvalidSleepOrdering_Throws() {
        var t = AppleHealthIRThresholds.default
        t.sleepT2 = t.sleepT1 - 1
        XCTAssertThrowsError(try t.validate())
    }

    func testThresholdsValidate_InvalidClampRange_Throws() {
        var t = AppleHealthIRThresholds.default
        t.multiplierMin = 3.0
        t.multiplierMax = 2.0
        XCTAssertThrowsError(try t.validate())
    }

    // MARK: - Publisher and updateBiometrics

    func testMultiplierPublisher_EmitsOnUpdate() {
        let expectation = expectation(description: "publisher emits updated value")
        var received: Double?
        let cancellable = service.multiplierPublisher
            .dropFirst()
            .sink { value in received = value; expectation.fulfill() }
        service.updateBiometrics(sleepHours: nil, stepCount: 15_000, hrvSDNN: nil, exerciseMinutes: nil)
        wait(for: [expectation], timeout: 1.0)
        XCTAssertNotNil(received)
        XCTAssertLessThan(received!, 1.0, "Very high steps should emit multiplier < 1.0")
        _ = cancellable
    }

    // MARK: - Log persistence

    func testLog_AppendAndLoad_RoundTrips() {
        service.updateBiometrics(sleepHours: 6.0, stepCount: 6_000, hrvSDNN: 45.0, exerciseMinutes: 45.0)
        let entries = AppleHealthIREntry.load()
        XCTAssertFalse(entries.isEmpty)
        let last = entries.last!
        XCTAssertEqual(last.sleepHours!,      6.0,  accuracy: 0.001)
        XCTAssertEqual(last.stepCount!,       6_000, accuracy: 0.001)
        XCTAssertEqual(last.hrvSDNN!,         45.0, accuracy: 0.001)
        XCTAssertEqual(last.exerciseMinutes!, 45.0, accuracy: 0.001)
    }

    func testLog_Prune_RemovesEntriesOlderThan24h() {
        let old = AppleHealthIREntry(
            id: UUID(), timestamp: Date().addingTimeInterval(-90_000),
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil,
            heartRate: nil,
            sleepDelta: 0, stepsDelta: 0, hrvDelta: 0, exerciseDelta: 0, rhrDelta: 0,
            combinedDelta: 0, multiplier: 1.0, thresholdsSnapshot: .default)
        AppleHealthIREntry.append(old)
        AppleHealthIREntry.pruneToWindow(86_400)
        XCTAssertTrue(AppleHealthIREntry.load().isEmpty, "Entry older than 24 h must be pruned")
    }

    func testLog_RecentEntry_NotPruned() {
        service.updateBiometrics(sleepHours: 7.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        AppleHealthIREntry.pruneToWindow(86_400)
        XCTAssertFalse(AppleHealthIREntry.load().isEmpty, "Recent entry must survive pruning")
    }

    // MARK: - RHR zone tests

    func testRHR_belowT1_isNeutral() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil,
            heartRate: thresholds.rhrT1 - 5.0)
        XCTAssertEqual(m, 1.0, accuracy: 0.001,
            "RHR < T1 (very low/athlete) must contribute 0% to multiplier")
    }

    func testRHR_betweenT1andT2_appliesE1() {
        let bpm = (thresholds.rhrT1 + thresholds.rhrT2) / 2.0
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil,
            heartRate: bpm)
        XCTAssertEqual(m, 1.0 + thresholds.rhrE1 / 100.0, accuracy: 0.001,
            "RHR T1–T2 must apply E1 (-2%)")
        XCTAssertLessThan(m, 1.0, "E1 is protective, multiplier must be < 1.0")
    }

    func testRHR_betweenT2andT3_appliesE2_neutral() {
        let bpm = (thresholds.rhrT2 + thresholds.rhrT3) / 2.0
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil,
            heartRate: bpm)
        XCTAssertEqual(m, 1.0 + thresholds.rhrE2 / 100.0, accuracy: 0.001,
            "RHR T2–T3 (normal) must apply E2 (0% → multiplier 1.0)")
        XCTAssertEqual(m, 1.0, accuracy: 0.001)
    }

    func testRHR_betweenT3andT4_appliesE3() {
        let bpm = (thresholds.rhrT3 + thresholds.rhrT4) / 2.0
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil,
            heartRate: bpm)
        XCTAssertEqual(m, 1.0 + thresholds.rhrE3 / 100.0, accuracy: 0.001,
            "RHR T3–T4 (mildly elevated) must apply E3 (+5%)")
        XCTAssertGreaterThan(m, 1.0)
        XCTAssertEqual(m, 1.05, accuracy: 0.001)
    }

    func testRHR_atOrAboveT4_appliesE4() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil,
            heartRate: thresholds.rhrT4)
        XCTAssertEqual(m, 1.0 + thresholds.rhrE4 / 100.0, accuracy: 0.001,
            "RHR >= T4 (significantly elevated) must apply E4 (+10%)")
        XCTAssertGreaterThan(m, 1.0)
        XCTAssertEqual(m, 1.10, accuracy: 0.001)
    }

    func testRHR_nil_contributesNothing() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil,
            heartRate: nil)
        XCTAssertEqual(m, 1.0, accuracy: 0.001, "nil heartRate must contribute 0%")
    }

    func testRHR_highCombinedWithBadSleep_clampedToMax() {
        var t = AppleHealthIRThresholds.default
        t.sleepE1 = 80.0
        t.rhrE4 = 80.0
        service.thresholds = t
        let m = service.computeMultiplier(
            sleepHours: 0.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil,
            heartRate: t.rhrT4)
        XCTAssertEqual(m, t.multiplierMax, accuracy: 0.001,
            "Combined sleep+RHR penalty must be clamped to multiplierMax")
    }
}
