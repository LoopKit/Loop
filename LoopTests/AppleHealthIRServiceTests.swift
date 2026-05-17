//
//  AppleHealthIRServiceTests.swift
//  LoopTests
//
//  Comprehensive tests for Apple Health Biometric IR integration.
//  Covers all 10 acceptance criteria from GitHub issue #1 plus full
//  coverage of each compute path and safety invariants.
//
//  IMPORTANT: This is medical software. Every assertion maps to a
//  documented safety invariant (multiplier clamped to [0.5, 2.0],
//  deterministic lerp with divide-by-zero guard, nil HealthKit data
//  => multiplier == 1.0).
//
//  No mocks for the IR service itself — tests use the real AppleHealthIRService.
//

import XCTest
import Combine
@testable import Loop

// ---------------------------------------------------------------------------
// MARK: - AppleHealthIRServiceTests
// ---------------------------------------------------------------------------

final class AppleHealthIRServiceTests: XCTestCase {

    private var service: AppleHealthIRService!
    private var thresholds: AppleHealthIRThresholds!

    override func setUp() {
        super.setUp()
        thresholds = .default
        service = AppleHealthIRService(thresholds: thresholds)
        // Isolate log storage from production data
        UserDefaults.standard.removeObject(forKey: AppleHealthIREntry.userDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppleHealthIREntry.userDefaultsKey)
        service = nil
        thresholds = nil
        super.tearDown()
    }

    // MARK: - AC 1: Sleep <= severe threshold => multiplier increases by severeEffect (+20%)

    func testAC1_SleepAtSevereThreshold_MultiplierIncreasesBySevereEffect() {
        // Default sleepSevereThreshold is 5.0 h, sleepSevereEffect is 20.0 (percent)
        let m = service.computeMultiplier(
            sleepHours: thresholds.sleepSevereThreshold,
            stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        let expected = 1.0 + thresholds.sleepSevereEffect / 100.0
        XCTAssertEqual(m, expected, accuracy: 0.001,
            "AC1: sleep at severe threshold => multiplier = 1 + severeEffect%")
        XCTAssertGreaterThan(m, 1.0,
            "AC1: insufficient sleep must raise the multiplier above 1.0")
        // Validate the documented default of +20%
        XCTAssertEqual(m, 1.20, accuracy: 0.001,
            "AC1: default severeEffect is 20% => multiplier 1.20")
    }

    // MARK: - AC 2: Steps >= stepsHighMin => multiplier decreases by stepsHighEffect (-8%)

    func testAC2_StepsAtHighMin_MultiplierDecreasesByHighEffect() {
        // Default stepsHighMin is 10 000; default stepsHighEffect is -8.0 (percent)
        let m = service.computeMultiplier(
            sleepHours: nil,
            stepCount: thresholds.stepsHighMin,
            hrvSDNN: nil, exerciseMinutes: nil)
        let expected = 1.0 + thresholds.stepsHighEffect / 100.0
        XCTAssertEqual(m, expected, accuracy: 0.001,
            "AC2: steps at stepsHighMin => multiplier = 1 + stepsHighEffect%")
        XCTAssertLessThan(m, 1.0,
            "AC2: high step count must lower the multiplier below 1.0")
        // Default stepsHighEffect == -8 => multiplier 0.92
        XCTAssertEqual(m, 0.92, accuracy: 0.001,
            "AC2: default stepsHighEffect is -8% => multiplier 0.92")
    }

    // MARK: - AC 3: HRV <= hrvVeryLowMax => multiplier increases by hrvVeryLowEffect (+15%)

    func testAC3_HRVAtVeryLowMax_MultiplierIncreasesByVeryLowEffect() {
        // Default hrvVeryLowMax is 20.0 ms; default hrvVeryLowEffect is 15.0 (percent)
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil,
            hrvSDNN: thresholds.hrvVeryLowMax,
            exerciseMinutes: nil)
        let expected = 1.0 + thresholds.hrvVeryLowEffect / 100.0
        XCTAssertEqual(m, expected, accuracy: 0.001,
            "AC3: HRV at veryLowMax => multiplier = 1 + hrvVeryLowEffect%")
        XCTAssertGreaterThan(m, 1.0,
            "AC3: very low HRV must raise the multiplier above 1.0")
        XCTAssertEqual(m, 1.15, accuracy: 0.001,
            "AC3: default hrvVeryLowEffect is 15% => multiplier 1.15")
    }

    // MARK: - AC 4: Combined deltas > 1.0 raw => clamped to multiplierMax (2.0)

    func testAC4_CombinedDeltasAboveCeiling_ClampedToMax() {
        // Mutate thresholds to force large positive combined delta
        var t = AppleHealthIRThresholds.default
        t.sleepSevereEffect = 80.0   // +80%
        t.hrvVeryLowEffect  = 80.0   // +80%  => combined = +160%, raw = 2.6, clamped to 2.0
        service.thresholds = t

        // Sleep: below severe, HRV: below veryLow => both hit max positive effects
        let m = service.computeMultiplier(
            sleepHours: 0.0, stepCount: nil, hrvSDNN: 1.0, exerciseMinutes: nil)

        XCTAssertEqual(m, t.multiplierMax, accuracy: 0.001,
            "AC4: combined positive delta exceeding ceiling must be clamped to multiplierMax")
        XCTAssertLessThanOrEqual(m, 2.0,
            "AC4: multiplier must never exceed 2.0")
    }

    // MARK: - AC 5: Combined deltas < -0.5 raw => clamped to multiplierMin (0.5)

    func testAC5_CombinedDeltasBelowFloor_ClampedToMin() {
        var t = AppleHealthIRThresholds.default
        t.stepsHighEffect      = -80.0   // -80%
        t.exerciseHeavyEffect  = -80.0   // -80%  => combined = -160%, raw = -0.6, clamped to 0.5
        service.thresholds = t

        let m = service.computeMultiplier(
            sleepHours: nil,
            stepCount: t.stepsHighMin,
            hrvSDNN: nil,
            exerciseMinutes: t.exerciseSubstantialMax)

        XCTAssertEqual(m, t.multiplierMin, accuracy: 0.001,
            "AC5: combined negative delta below floor must be clamped to multiplierMin")
        XCTAssertGreaterThanOrEqual(m, 0.5,
            "AC5: multiplier must never fall below 0.5")
    }

    // MARK: - AC 6: Equal thresholds => no divide-by-zero, returns severeEffect

    func testAC6_EqualSleepThresholds_NoDivideByZero() {
        // Set severe == mild so lerp denominator would be 0
        var t = AppleHealthIRThresholds.default
        t.sleepSevereThreshold = 6.0
        t.sleepMildThreshold   = 6.0
        service.thresholds = t

        // Any sleep value that hits the equal-threshold boundary
        let delta: Double
        // We can probe via computeMultiplier using only sleep
        let m = service.computeMultiplier(
            sleepHours: 6.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        delta = (m - 1.0) * 100.0

        XCTAssertFalse(m.isNaN,      "AC6: multiplier must not be NaN with equal thresholds")
        XCTAssertFalse(m.isInfinite, "AC6: multiplier must not be infinite with equal thresholds")
        // The guard clause must return severeEffect directly
        XCTAssertEqual(delta, t.sleepSevereEffect, accuracy: 0.001,
            "AC6: equal thresholds must short-circuit to severeEffect without divide-by-zero")
    }

    // MARK: - AC 7: Reset to defaults => all values match documented defaults
    // Full default values verified in AppleHealthIRThresholdsTests.

    func testAC7_DefaultThresholds_PassValidation() {
        // After any mutation path: the static .default must always pass validate()
        // without requiring a user reset action.
        XCTAssertNoThrow(try AppleHealthIRThresholds.default.validate(),
            "AC7: .default must always satisfy all ordering and bound invariants")
    }

    func testAC7_DefaultThresholds_KeySleepAndStepsValues() {
        let t = AppleHealthIRThresholds.default
        XCTAssertEqual(t.sleepSevereEffect, 20.0, accuracy: 1e-9, "AC7: severeEffect default")
        XCTAssertEqual(t.stepsHighEffect,   -8.0, accuracy: 1e-9, "AC7: stepsHighEffect default")
        XCTAssertEqual(t.hrvVeryLowEffect,  15.0, accuracy: 1e-9, "AC7: hrvVeryLowEffect default")
        XCTAssertEqual(t.multiplierMin,      0.5, accuracy: 1e-9, "AC7: multiplierMin default")
        XCTAssertEqual(t.multiplierMax,      2.0, accuracy: 1e-9, "AC7: multiplierMax default")
    }

    // MARK: - AC 8: Threshold table reflects user-customised values

    func testAC8_CustomThresholds_ReflectedInComputation() {
        var t = AppleHealthIRThresholds.default
        t.sleepSevereEffect = 33.0   // custom: 33% instead of default 20%
        service.thresholds = t

        let m = service.computeMultiplier(
            sleepHours: t.sleepSevereThreshold - 1, // below severe => should use sleepSevereEffect
            stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)

        XCTAssertEqual(m, 1.0 + 33.0 / 100.0, accuracy: 0.001,
            "AC8: computation must use user-customised sleepSevereEffect, not a hardcoded constant")
    }

    // MARK: - AC 9: 24h log entries have timestamp, source (field identifiers), magnitude

    func testAC9_LogEntries_HaveRequiredFields() {
        service.updateBiometrics(sleepHours: 5.0, stepCount: 8_000, hrvSDNN: 35.0, exerciseMinutes: 25.0)

        let entries = AppleHealthIREntry.load()

        XCTAssertFalse(entries.isEmpty,
            "AC9: at least one log entry must exist after updateBiometrics")

        for entry in entries {
            // timestamp
            XCTAssertNotNil(entry.timestamp,
                "AC9: every entry must have a non-nil timestamp")
            XCTAssertLessThan(entry.timestamp.timeIntervalSinceNow, 5.0,
                "AC9: timestamp must be recent (within 5 s of now)")

            // source fields (each delta identifies which source contributed)
            XCTAssertFalse(entry.sleepDelta.isNaN,      "sleepDelta must not be NaN")
            XCTAssertFalse(entry.stepsDelta.isNaN,      "stepsDelta must not be NaN")
            XCTAssertFalse(entry.hrvDelta.isNaN,        "hrvDelta must not be NaN")
            XCTAssertFalse(entry.exerciseDelta.isNaN,   "exerciseDelta must not be NaN")
            XCTAssertFalse(entry.combinedDelta.isNaN,   "combinedDelta must not be NaN")

            // magnitude (multiplier)
            XCTAssertFalse(entry.multiplier.isNaN,      "AC9: multiplier must not be NaN")
            XCTAssertFalse(entry.multiplier.isInfinite, "AC9: multiplier must not be infinite")
            XCTAssertGreaterThanOrEqual(entry.multiplier, 0.5,
                "AC9: logged multiplier must respect floor 0.5")
            XCTAssertLessThanOrEqual(entry.multiplier, 2.0,
                "AC9: logged multiplier must respect ceiling 2.0")

            // thresholdsSnapshot must be present and valid
            XCTAssertNoThrow(try entry.thresholdsSnapshot.validate(),
                "AC9: thresholds snapshot stored in log must be valid")
        }
    }

    // MARK: - AC 10: nil HealthKit data => multiplier == 1.0

    func testAC10_AllNilInputs_MultiplierIsUnity() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0, accuracy: 0.001,
            "AC10: when all HealthKit data is nil the multiplier must be exactly 1.0")
    }

    // ---------------------------------------------------------------------------
    // MARK: - Sleep delta: all tiers + linear interpolation boundary
    // ---------------------------------------------------------------------------

    func testSleepDelta_Interpolated_MidpointIsMidEffect() {
        let mid = (thresholds.sleepSevereThreshold + thresholds.sleepMildThreshold) / 2.0
        let m = service.computeMultiplier(sleepHours: mid, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        let expectedDelta = (thresholds.sleepSevereEffect + thresholds.sleepMildEffect) / 2.0
        XCTAssertEqual(m, 1.0 + expectedDelta / 100.0, accuracy: 0.001,
            "Sleep midpoint should interpolate linearly to the average of severe and mild effects")
    }

    func testSleepDelta_AtMildThreshold_ReturnsMildEffect() {
        let m = service.computeMultiplier(
            sleepHours: thresholds.sleepMildThreshold,
            stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.sleepMildEffect / 100.0, accuracy: 0.001)
    }

    func testSleepDelta_AboveMildThreshold_ReturnsMildEffect() {
        let m = service.computeMultiplier(sleepHours: 9.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.sleepMildEffect / 100.0, accuracy: 0.001,
            "Sleep above mild threshold uses mildEffect (defaults to 0 => multiplier 1.0)")
    }

    // ---------------------------------------------------------------------------
    // MARK: - Steps delta: all four bands + below-minimum returns 0
    // ---------------------------------------------------------------------------

    func testStepsDelta_BelowLowMin_ReturnsZero() {
        let m = service.computeMultiplier(
            sleepHours: nil,
            stepCount: thresholds.stepsLowMin - 1,
            hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0, accuracy: 0.001,
            "Steps below stepsLowMin should contribute zero delta => multiplier 1.0")
    }

    func testStepsDelta_AtLowMin_ReturnsLowEffect() {
        let m = service.computeMultiplier(
            sleepHours: nil,
            stepCount: thresholds.stepsLowMin,
            hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.stepsLowEffect / 100.0, accuracy: 0.001)
    }

    func testStepsDelta_AtMediumMin_ReturnsMediumEffect() {
        let m = service.computeMultiplier(
            sleepHours: nil,
            stepCount: thresholds.stepsMediumMin,
            hrvSDNN: nil, exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.stepsMediumEffect / 100.0, accuracy: 0.001)
    }

    // ---------------------------------------------------------------------------
    // MARK: - HRV delta: all four tiers
    // ---------------------------------------------------------------------------

    func testHRVDelta_InLowBand_ReturnsLowEffect() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil,
            hrvSDNN: thresholds.hrvVeryLowMax + 1,
            exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.hrvLowEffect / 100.0, accuracy: 0.001)
    }

    func testHRVDelta_InNormalBand_ReturnsNormalEffect() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil,
            hrvSDNN: thresholds.hrvLowMax + 1,
            exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.hrvNormalEffect / 100.0, accuracy: 0.001)
    }

    func testHRVDelta_AboveNormalMax_ReturnsHighEffect() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil,
            hrvSDNN: thresholds.hrvNormalMax + 1,
            exerciseMinutes: nil)
        XCTAssertEqual(m, 1.0 + thresholds.hrvHighEffect / 100.0, accuracy: 0.001)
    }

    // ---------------------------------------------------------------------------
    // MARK: - Exercise delta: all four bands
    // ---------------------------------------------------------------------------

    func testExerciseDelta_BelowMin_ReturnsZero() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil,
            exerciseMinutes: thresholds.exerciseMinThreshold - 1)
        XCTAssertEqual(m, 1.0, accuracy: 0.001,
            "Exercise below minimum threshold contributes zero delta")
    }

    func testExerciseDelta_AtModerateMin_ReturnsModerateEffect() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil,
            exerciseMinutes: thresholds.exerciseMinThreshold)
        XCTAssertEqual(m, 1.0 + thresholds.exerciseModerateEffect / 100.0, accuracy: 0.001)
    }

    func testExerciseDelta_AtHeavyMin_ReturnsHeavyEffect() {
        let m = service.computeMultiplier(
            sleepHours: nil, stepCount: nil, hrvSDNN: nil,
            exerciseMinutes: thresholds.exerciseSubstantialMax)
        XCTAssertEqual(m, 1.0 + thresholds.exerciseHeavyEffect / 100.0, accuracy: 0.001)
    }

    // ---------------------------------------------------------------------------
    // MARK: - Multiplier floor (0.5) and ceiling (2.0) never exceeded
    // ---------------------------------------------------------------------------

    func testMultiplier_Floor_NeverExceeded_UnderExtremeNegativeDeltas() {
        var t = AppleHealthIRThresholds.default
        t.stepsHighEffect     = -500.0
        t.exerciseHeavyEffect = -500.0
        service.thresholds = t

        let m = service.computeMultiplier(
            sleepHours: nil,
            stepCount: t.stepsHighMin,
            hrvSDNN: nil,
            exerciseMinutes: t.exerciseSubstantialMax)

        XCTAssertGreaterThanOrEqual(m, 0.5,
            "Floor 0.5 must hold even with extreme negative deltas")
        XCTAssertEqual(m, t.multiplierMin, accuracy: 0.001)
    }

    func testMultiplier_Ceiling_NeverExceeded_UnderExtremePositiveDeltas() {
        var t = AppleHealthIRThresholds.default
        t.sleepSevereEffect = 500.0
        t.hrvVeryLowEffect  = 500.0
        service.thresholds = t

        let m = service.computeMultiplier(
            sleepHours: 0.0, stepCount: nil, hrvSDNN: 1.0, exerciseMinutes: nil)

        XCTAssertLessThanOrEqual(m, 2.0,
            "Ceiling 2.0 must hold even with extreme positive deltas")
        XCTAssertEqual(m, t.multiplierMax, accuracy: 0.001)
    }

    // ---------------------------------------------------------------------------
    // MARK: - Combined multiplier edge cases
    // ---------------------------------------------------------------------------

    func testMultiplier_CombinedPositiveDeltas_RaisesMultiplier() {
        // Very low sleep + very low HRV both increase IR
        let m = service.computeMultiplier(
            sleepHours: 2.0, stepCount: nil, hrvSDNN: 10.0, exerciseMinutes: nil)
        XCTAssertGreaterThan(m, 1.0,
            "Combined positive sources must raise the multiplier above 1.0")
    }

    func testMultiplier_CombinedNegativeDeltas_LowersMultiplier() {
        // High steps + heavy exercise lower IR
        let m = service.computeMultiplier(
            sleepHours: nil,
            stepCount: thresholds.stepsHighMin,
            hrvSDNN: nil,
            exerciseMinutes: thresholds.exerciseSubstantialMax)
        XCTAssertLessThan(m, 1.0,
            "Combined negative sources must lower the multiplier below 1.0")
    }

    // ---------------------------------------------------------------------------
    // MARK: - Thresholds validation (isValid / validate)
    // ---------------------------------------------------------------------------

    func testThresholdsValidate_InvalidSleepOrdering_Throws() {
        var t = AppleHealthIRThresholds.default
        t.sleepSevereThreshold = 8.0   // severe must be < mild
        t.sleepMildThreshold   = 5.0
        XCTAssertThrowsError(try t.validate())
    }

    func testThresholdsValidate_InvalidClampRange_Throws() {
        var t = AppleHealthIRThresholds.default
        t.multiplierMin = 3.0
        t.multiplierMax = 2.0
        XCTAssertThrowsError(try t.validate())
    }

    func testThresholdsValidate_ZeroMultiplierMin_Throws() {
        var t = AppleHealthIRThresholds.default
        t.multiplierMin = 0.0
        XCTAssertThrowsError(try t.validate(),
            "multiplierMin must be > 0")
    }

    // ---------------------------------------------------------------------------
    // MARK: - Publisher and updateBiometrics
    // ---------------------------------------------------------------------------

    func testMultiplierPublisher_EmitsOnUpdate() {
        let expectation = expectation(description: "publisher emits updated value")
        var received: Double?

        let cancellable = service.multiplierPublisher
            .dropFirst()  // skip the initial value
            .sink { value in
                received = value
                expectation.fulfill()
            }

        service.updateBiometrics(
            sleepHours: nil, stepCount: 12_000, hrvSDNN: nil, exerciseMinutes: nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertNotNil(received, "Publisher must emit after updateBiometrics")
        XCTAssertLessThan(received!, 1.0,
            "High step count should emit a multiplier below 1.0")
        _ = cancellable
    }

    // ---------------------------------------------------------------------------
    // MARK: - Log persistence (AC 9 extended)
    // ---------------------------------------------------------------------------

    func testLog_AppendAndLoad_RoundTrips() {
        service.updateBiometrics(
            sleepHours: 6.0, stepCount: 5_000, hrvSDNN: 45.0, exerciseMinutes: 30.0)

        let entries = AppleHealthIREntry.load()
        XCTAssertFalse(entries.isEmpty, "Log must contain at least one entry")

        let last = entries.last!
        XCTAssertEqual(last.sleepHours,     6.0,   accuracy: 0.001)
        XCTAssertEqual(last.stepCount!,     5_000, accuracy: 0.001)
        XCTAssertEqual(last.hrvSDNN!,       45.0,  accuracy: 0.001)
        XCTAssertEqual(last.exerciseMinutes!, 30.0, accuracy: 0.001)
    }

    func testLog_Prune_RemovesEntriesOlderThan24h() {
        let old = AppleHealthIREntry(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-90_000),  // 25 h ago
            sleepHours: nil, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil,
            sleepDelta: 0, stepsDelta: 0, hrvDelta: 0, exerciseDelta: 0,
            combinedDelta: 0, multiplier: 1.0,
            thresholdsSnapshot: .default
        )
        AppleHealthIREntry.append(old)
        AppleHealthIREntry.pruneToWindow(86_400)

        let entries = AppleHealthIREntry.load()
        XCTAssertTrue(entries.isEmpty, "Entry older than 24 h must be pruned from the log")
    }

    func testLog_RecentEntry_NotPruned() {
        service.updateBiometrics(
            sleepHours: 7.0, stepCount: nil, hrvSDNN: nil, exerciseMinutes: nil)
        AppleHealthIREntry.pruneToWindow(86_400)

        let entries = AppleHealthIREntry.load()
        XCTAssertFalse(entries.isEmpty,
            "A recent entry (< 24 h) must survive pruning")
    }
}
