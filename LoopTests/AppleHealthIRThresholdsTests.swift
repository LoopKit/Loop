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

    // MARK: - Default values: Sleep

    func testDefaults_sleepT1_is4h() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepT1, 4.0, accuracy: accuracy)
    }

    func testDefaults_sleepT2_is5_5h() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepT2, 5.5, accuracy: accuracy)
    }

    func testDefaults_sleepT3_is6_5h() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepT3, 6.5, accuracy: accuracy)
    }

    func testDefaults_sleepT4_is7_5h() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepT4, 7.5, accuracy: accuracy)
    }

    func testDefaults_sleepE1_is30percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepE1, 30.0, accuracy: accuracy)
    }

    func testDefaults_sleepE2_is20percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepE2, 20.0, accuracy: accuracy)
    }

    func testDefaults_sleepE3_is10percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepE3, 10.0, accuracy: accuracy)
    }

    func testDefaults_sleepE4_is5percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.sleepE4, 5.0, accuracy: accuracy)
    }

    // MARK: - Default values: Steps

    func testDefaults_stepsT1_is2000() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsT1, 2000, accuracy: accuracy)
    }

    func testDefaults_stepsT2_is5000() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsT2, 5000, accuracy: accuracy)
    }

    func testDefaults_stepsT3_is8000() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsT3, 8000, accuracy: accuracy)
    }

    func testDefaults_stepsT4_is12000() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsT4, 12000, accuracy: accuracy)
    }

    func testDefaults_stepsE1_is5percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsE1, 5.0, accuracy: accuracy)
    }

    func testDefaults_stepsE2_is0percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsE2, 0.0, accuracy: accuracy)
    }

    func testDefaults_stepsE3_isNeg3percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsE3, -3.0, accuracy: accuracy)
    }

    func testDefaults_stepsE4_isNeg6percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.stepsE4, -6.0, accuracy: accuracy)
    }

    // MARK: - Default values: HRV

    func testDefaults_hrvT1_is20ms() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvT1, 20.0, accuracy: accuracy)
    }

    func testDefaults_hrvT2_is35ms() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvT2, 35.0, accuracy: accuracy)
    }

    func testDefaults_hrvT3_is50ms() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvT3, 50.0, accuracy: accuracy)
    }

    func testDefaults_hrvT4_is70ms() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvT4, 70.0, accuracy: accuracy)
    }

    func testDefaults_hrvE1_is20percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvE1, 20.0, accuracy: accuracy)
    }

    func testDefaults_hrvE2_is10percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvE2, 10.0, accuracy: accuracy)
    }

    func testDefaults_hrvE3_is5percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvE3, 5.0, accuracy: accuracy)
    }

    func testDefaults_hrvE4_is0percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.hrvE4, 0.0, accuracy: accuracy)
    }

    // MARK: - Default values: Exercise

    func testDefaults_exerciseT1_is10min() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseT1, 10.0, accuracy: accuracy)
    }

    func testDefaults_exerciseT2_is30min() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseT2, 30.0, accuracy: accuracy)
    }

    func testDefaults_exerciseT3_is60min() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseT3, 60.0, accuracy: accuracy)
    }

    func testDefaults_exerciseT4_is120min() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseT4, 120.0, accuracy: accuracy)
    }

    func testDefaults_exerciseE1_is5percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseE1, 5.0, accuracy: accuracy)
    }

    func testDefaults_exerciseE2_isNeg3percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseE2, -3.0, accuracy: accuracy)
    }

    func testDefaults_exerciseE3_isNeg8percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseE3, -8.0, accuracy: accuracy)
    }

    func testDefaults_exerciseE4_isNeg12percent() {
        XCTAssertEqual(AppleHealthIRThresholds.default.exerciseE4, -12.0, accuracy: accuracy)
    }

    // MARK: - Default values: Multiplier clamp

    func testDefaults_multiplierBounds() {
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
        t.sleepE1 = 35.0
        t.stepsE4 = -10.0
        t.hrvE1 = 22.0
        t.exerciseE4 = -15.0
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
        t.sleepE1 = 35.0
        t.stepsE4 = -10.0
        t.save()
        let loaded = AppleHealthIRThresholds.load()
        XCTAssertEqual(loaded.sleepE1, 35.0, accuracy: accuracy)
        XCTAssertEqual(loaded.stepsE4, -10.0, accuracy: accuracy)
    }

    func testLoad_missingKey_returnsDefaults() {
        UserDefaults.standard.removeObject(forKey: key)
        let loaded = AppleHealthIRThresholds.load()
        XCTAssertEqual(loaded, AppleHealthIRThresholds.default)
    }

    func testResetToDefaults_restoresAllDocumentedValues() {
        var t = AppleHealthIRThresholds.default
        t.sleepE1 = 99.0
        t.stepsE4 = -99.0
        t.save()
        AppleHealthIRThresholds.default.save()
        let loaded = AppleHealthIRThresholds.load()
        XCTAssertEqual(loaded, AppleHealthIRThresholds.default)
    }

    // MARK: - validate() — ordering constraints

    func testValidate_defaults_doesNotThrow() {
        XCTAssertNoThrow(try AppleHealthIRThresholds.default.validate())
    }

    func testValidate_invalidSleepOrdering_T1T2_throws() {
        var t = AppleHealthIRThresholds.default
        t.sleepT2 = t.sleepT1 - 0.5
        XCTAssertThrowsError(try t.validate())
    }

    func testValidate_invalidSleepOrdering_T3T4_throws() {
        var t = AppleHealthIRThresholds.default
        t.sleepT4 = t.sleepT3 - 0.5
        XCTAssertThrowsError(try t.validate())
    }

    func testValidate_invalidStepsOrdering_throws() {
        var t = AppleHealthIRThresholds.default
        t.stepsT2 = t.stepsT3 + 1
        XCTAssertThrowsError(try t.validate())
    }

    func testValidate_invalidHRVOrdering_throws() {
        var t = AppleHealthIRThresholds.default
        t.hrvT2 = t.hrvT1 - 1
        XCTAssertThrowsError(try t.validate())
    }

    func testValidate_invalidExerciseOrdering_throws() {
        var t = AppleHealthIRThresholds.default
        t.exerciseT3 = t.exerciseT4 + 1
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

    func testOrdering_exerciseEffects_worsenWithLessActivity() {
        let t = AppleHealthIRThresholds.default
        XCTAssertGreaterThan(t.exerciseE1, t.exerciseE2)
        XCTAssertGreaterThan(t.exerciseE2, t.exerciseE3)
        XCTAssertGreaterThan(t.exerciseE3, t.exerciseE4)
        XCTAssertLessThanOrEqual(t.exerciseE4, 0.0)
    }

    func testOrdering_sleepEffects_worsenWithLessSleep() {
        let t = AppleHealthIRThresholds.default
        XCTAssertGreaterThan(t.sleepE1, t.sleepE2)
        XCTAssertGreaterThan(t.sleepE2, t.sleepE3)
        XCTAssertGreaterThan(t.sleepE3, t.sleepE4)
        XCTAssertGreaterThan(t.sleepE1, 0.0)
    }

    func testOrdering_hrvEffects_worsenWithLowerHRV() {
        let t = AppleHealthIRThresholds.default
        XCTAssertGreaterThanOrEqual(t.hrvE1, t.hrvE2)
        XCTAssertGreaterThanOrEqual(t.hrvE2, t.hrvE3)
        XCTAssertGreaterThanOrEqual(t.hrvE3, t.hrvE4)
    }
}
