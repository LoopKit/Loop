//
//  AppleHealthIRThresholdsTests.swift
//  LoopTests
//

import XCTest
import Foundation
@testable import Loop

final class AppleHealthIRThresholdsTests: XCTestCase {

    private let accuracy = 1e-9
    private let key = AppleHealthIRThresholds.userDefaultsKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    // MARK: - Default values match spec

    func testDefaults_sleepSevereThreshold_is5h() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepSevereThreshold, 5.0, accuracy: accuracy)
    }

    func testDefaults_sleepMildThreshold_is7h() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepMildThreshold, 7.0, accuracy: accuracy)
    }

    func testDefaults_sleepSevereEffect_is20percent() {
        // AC1: documented default +20% for severe sleep deprivation
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepSevereEffect, 20.0, accuracy: accuracy)
    }

    func testDefaults_sleepMildEffect_is0percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepMildEffect, 0.0, accuracy: accuracy)
    }

    func testDefaults_stepsLowMin_is2000() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsLowMin, 2000, accuracy: accuracy)
    }

    func testDefaults_stepsMediumMin_is5000() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsMediumMin, 5000, accuracy: accuracy)
    }

    func testDefaults_stepsHighMin_is10000() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsHighMin, 10000, accuracy: accuracy)
    }

    func testDefaults_stepsHighEffect_isNeg8percent() {
        // AC2: documented default -8% for high activity
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsHighEffect, -8.0, accuracy: accuracy)
    }

    func testDefaults_stepsMediumEffect_isNeg5percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsMediumEffect, -5.0, accuracy: accuracy)
    }

    func testDefaults_stepsLowEffect_isNeg3percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsLowEffect, -3.0, accuracy: accuracy)
    }

    func testDefaults_hrvVeryLowMax_is20ms() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvVeryLowMax, 20.0, accuracy: accuracy)
    }

    func testDefaults_hrvLowMax_is40ms() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvLowMax, 40.0, accuracy: accuracy)
    }

    func testDefaults_hrvNormalMax_is60ms() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvNormalMax, 60.0, accuracy: accuracy)
    }

    func testDefaults_hrvVeryLowEffect_is15percent() {
        // AC3: documented default +15% for very low HRV
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvVeryLowEffect, 15.0, accuracy: accuracy)
    }

    func testDefaults_hrvLowEffect_is8percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvLowEffect, 8.0, accuracy: accuracy)
    }

    func testDefaults_hrvHighEffect_isNeg5percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvHighEffect, -5.0, accuracy: accuracy)
    }

    func testDefaults_exerciseMinThreshold_is20min() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseMinThreshold, 20.0, accuracy: accuracy)
    }

    func testDefaults_exerciseModerateMax_is60min() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseModerateMax, 60.0, accuracy: accuracy)
    }

    func testDefaults_exerciseSubstantialMax_is120min() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseSubstantialMax, 120.0, accuracy: accuracy)
    }

    func testDefaults_exerciseModerateEffect_isNeg5percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseModerateEffect, -5.0, accuracy: accuracy)
    }

    func testDefaults_exerciseSubstantialEffect_isNeg10percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseSubstantialEffect, -10.0, accuracy: accuracy)
    }

    func testDefaults_exerciseHeavyEffect_isNeg15percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseHeavyEffect, -15.0, accuracy: accuracy)
    }

    func testDefaults_multiplierBounds() {
        // AC4/AC5: hard-coded clamp values
        XCTAssertEqual(AppleHealthIRThresholds.default.multiplierMin, 0.5, accuracy: accuracy)
        XCTAssertEqual(AppleHealthIRThresholds.default.multiplierMax, 2.0, accuracy: accuracy)
    }

    // MARK: - Codable round-trip

    func testCodable_roundTrip_defaultValues() throws {
        let original = AppleHealthIRThresholds.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppleHealthIRThresholds.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodable_roundTrip_mutatedValues() throws {
        var t = AppleHealthIRThresholds.default
        t.sleepSevereEffect = 25.0
        t.stepsHighEffect = -10.0
        t.hrvVeryLowEffect = 18.0
        t.exerciseHeavyEffect = -12.0
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(AppleHealthIRThresholds.self, from: data)
        XCTAssertEqual(decoded, t)
    }

    func testCodable_corruptData_loadFallsBackToDefaults() {
        UserDefaults.standard.set(Data([0xDE, 0xAD]), forKey: key)
        let loaded = AppleHealthIRThresholds.load()
        XCTAssertEqual(loaded, AppleHealthIRThresholds.default)
    }

    // MARK: - UserDefaults persistence

    func testSaveAndLoad_roundTrips() {
        var t = AppleHealthIRThresholds.default
        t.sleepSevereEffect = 25.0
        t.stepsHighEffect = -10.0
        t.save()
        let loaded = AppleHealthIRThresholds.load()
        XCTAssertEqual(loaded.sleepSevereEffect, 25.0, accuracy: accuracy)
        XCTAssertEqual(loaded.stepsHighEffect, -10.0, accuracy: accuracy)
    }

    func testLoad_missingKey_returnsDefaults() {
        UserDefaults.standard.removeObject(forKey: key)
        let loaded = AppleHealthIRThresholds.load()
        XCTAssertEqual(loaded, AppleHealthIRThresholds.default)
    }

    // AC7: "Resetting to defaults in Settings restores all values to their documented defaults."
    func testResetToDefaults_restoresAllDocumentedValues() {
        var t = AppleHealthIRThresholds.default
        t.sleepSevereEffect = 99.0
        t.stepsHighEffect = -99.0
        t.save()

        // Simulate "Reset to Defaults": overwrite with the default struct
        AppleHealthIRThresholds.default.save()

        let loaded = AppleHealthIRThresholds.load()
        XCTAssertEqual(loaded, AppleHealthIRThresholds.default)
    }

    // MARK: - validate() — ordering constraints

    func testValidate_defaults_doesNotThrow() {
        XCTAssertNoThrow(try AppleHealthIRThresholds.default.validate())
    }

    func testValidate_invalidSleepOrdering_throws() {
        var t = AppleHealthIRThresholds.default
        t.sleepSevereThreshold = 8.0
        t.sleepMildThreshold = 5.0
        XCTAssertThrowsError(try t.validate())
    }

    func testValidate_invalidStepsOrdering_throws() {
        var t = AppleHealthIRThresholds.default
        t.stepsMediumMin = t.stepsHighMin + 1
        XCTAssertThrowsError(try t.validate())
    }

    func testValidate_invalidHRVOrdering_throws() {
        var t = AppleHealthIRThresholds.default
        t.hrvLowMax = t.hrvVeryLowMax - 1
        XCTAssertThrowsError(try t.validate())
    }

    func testValidate_invalidExerciseOrdering_throws() {
        var t = AppleHealthIRThresholds.default
        t.exerciseModerateMax = t.exerciseSubstantialMax + 1
        XCTAssertThrowsError(try t.validate())
    }

    func testValidate_invalidClampRange_throws() {
        var t = AppleHealthIRThresholds.default
        t.multiplierMin = 3.0
        t.multiplierMax = 2.0
        XCTAssertThrowsError(try t.validate())
    }

    func testValidate_zeroMultiplierMin_throws() {
        var t = AppleHealthIRThresholds.default
        t.multiplierMin = 0.0
        XCTAssertThrowsError(try t.validate())
    }

    // MARK: - Physiological ordering

    func testOrdering_exerciseEffects_magnitudeIncreasesWithIntensity() {
        let t = AppleHealthIRThresholds.default
        XCTAssertLessThanOrEqual(t.exerciseModerateEffect, 0.0)
        XCTAssertLessThanOrEqual(t.exerciseSubstantialEffect, 0.0)
        XCTAssertLessThanOrEqual(t.exerciseHeavyEffect, 0.0)
        XCTAssertLessThanOrEqual(t.exerciseModerateEffect, t.exerciseSubstantialEffect + 1e-9)
        XCTAssertLessThanOrEqual(t.exerciseSubstantialEffect, t.exerciseHeavyEffect + 1e-9)
    }

    func testOrdering_hrvEffects_veryLowExceedsLow() {
        let t = AppleHealthIRThresholds.default
        XCTAssertGreaterThan(t.hrvVeryLowEffect, t.hrvLowEffect)
        XCTAssertGreaterThan(t.hrvLowEffect, 0.0)
    }

    func testOrdering_sleepEffect_severeExceedsMild() {
        let t = AppleHealthIRThresholds.default
        XCTAssertGreaterThan(t.sleepSevereEffect, t.sleepMildEffect)
    }
}
