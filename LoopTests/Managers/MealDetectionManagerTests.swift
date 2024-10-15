//
//  MealDetectionManagerTests.swift
//  LoopTests
//
//  Created by Anna Quinlan on 11/28/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopCore
import LoopKit
import LoopAlgorithm

@testable import Loop

fileprivate class MockGlucoseSample: GlucoseSampleValue {

    let provenanceIdentifier = ""
    let isDisplayOnly: Bool
    let wasUserEntered: Bool
    let condition: GlucoseCondition? = nil
    let trendRate: HKQuantity? = nil
    var trend: LoopKit.GlucoseTrend?
    var syncIdentifier: String?
    let quantity: HKQuantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 100)
    let startDate: Date
    
    init(startDate: Date, isDisplayOnly: Bool = false, wasUserEntered: Bool = false) {
        self.startDate = startDate
        self.isDisplayOnly = isDisplayOnly
        self.wasUserEntered = wasUserEntered
    }
}

enum MissedMealTestType {
    private static var dateFormatter = ISO8601DateFormatter.localTimeDate()
    
    /// No meal is present
    case noMeal
    /// No meal is present, but if the counteraction effects aren't clamped properly it will look like there's a missed meal
    case noMealCounteractionEffectsNeedClamping
    // No meal is present and there is COB
    case noMealWithCOB
    /// Missed meal with no carbs on board
    case missedMealNoCOB
    /// Missed meal with carbs logged prior to it
    case missedMealWithCOB
    /// CGM data is noisy, but no meal is present
    case noisyCGM
    /// Realistic counteraction effects with multiple meals
    case manyMeals
    /// Test case to test dynamic computation of missed meal carb amount
    case dynamicCarbAutofill
    /// Test case for purely testing the notifications (not the algorithm)
    case notificationTest
    /// Test case for testing the algorithm with settings in mmol/L
    case mmolUser
}

extension MissedMealTestType {
    var counteractionEffectFixture: String {
        switch self {
        case .missedMealNoCOB, .noMealWithCOB, .notificationTest:
            return "missed_meal_counteraction_effect"
        case .noMeal:
            return "long_interval_counteraction_effect"
        case .noMealCounteractionEffectsNeedClamping:
            return "needs_clamping_counteraction_effect"
        case .noisyCGM:
            return "noisy_cgm_counteraction_effect"
        case .manyMeals, .missedMealWithCOB:
            return "realistic_report_counteraction_effect"
        case .dynamicCarbAutofill, .mmolUser:
            return "dynamic_autofill_counteraction_effect"
        }
    }
    
    var currentDate: Date {
        switch self {
        case .missedMealNoCOB, .noMealWithCOB, .notificationTest:
            return Self.dateFormatter.date(from: "2022-10-17T23:28:45")!
        case .noMeal, .noMealCounteractionEffectsNeedClamping:
            return Self.dateFormatter.date(from: "2022-10-17T02:49:16")!
        case .noisyCGM:
            return Self.dateFormatter.date(from: "2022-10-19T20:46:23")!
        case .missedMealWithCOB:
            return Self.dateFormatter.date(from: "2022-10-19T19:50:15")!
        case .manyMeals:
            return Self.dateFormatter.date(from: "2022-10-19T21:50:15")!
        case .dynamicCarbAutofill, .mmolUser:
            return Self.dateFormatter.date(from: "2022-10-17T07:51:09")!
        }
    }
    
    var missedMealDate: Date? {
        switch self {
        case .missedMealNoCOB:
            return Self.dateFormatter.date(from: "2022-10-17T21:55:00")
        case .missedMealWithCOB:
            return Self.dateFormatter.date(from: "2022-10-19T19:00:00")
        case .manyMeals:
            return Self.dateFormatter.date(from: "2022-10-19T20:40:00 ")
        case .dynamicCarbAutofill, .mmolUser:
            return Self.dateFormatter.date(from: "2022-10-17T07:20:00")!
        default:
            return nil
        }
    }
    
    var carbEntries: [NewCarbEntry] {
        switch self {
        case .missedMealWithCOB:
            return [
                NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 30),
                             startDate: Self.dateFormatter.date(from: "2022-10-19T15:41:36")!,
                             foodType: nil,
                             absorptionTime: nil),
                NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 10),
                             startDate: Self.dateFormatter.date(from: "2022-10-19T17:36:58")!,
                             foodType: nil,
                             absorptionTime: nil)
            ]
        case .noMealWithCOB:
            return [
                NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 30),
                             startDate: Self.dateFormatter.date(from: "2022-10-17T22:40:00")!,
                             foodType: nil,
                             absorptionTime: nil)
            ]
        case .manyMeals:
            return [
                NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 30),
                             startDate: Self.dateFormatter.date(from: "2022-10-19T15:41:36")!,
                             foodType: nil,
                             absorptionTime: nil),
                NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 10),
                             startDate: Self.dateFormatter.date(from: "2022-10-19T17:36:58")!,
                             foodType: nil,
                             absorptionTime: nil),
                NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 40),
                             startDate: Self.dateFormatter.date(from: "2022-10-19T19:11:43")!,
                             foodType: nil,
                             absorptionTime: nil)
            ]
        default:
            return []
        }
    }
    
    var carbSchedule: CarbRatioSchedule {
        CarbRatioSchedule(
            unit: .gram(),
            dailyItems: [
                RepeatingScheduleValue(startTime: 0.0, value: 15.0),
            ],
            timeZone: .utcTimeZone
        )!
    }
    
    var insulinSensitivitySchedule: InsulinSensitivitySchedule {
        let value = 50.0
        switch self {
        case .mmolUser:
            return InsulinSensitivitySchedule(
                unit: HKUnit.millimolesPerLiter,
                dailyItems: [
                    RepeatingScheduleValue(startTime: 0.0,
                                           value: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value).doubleValue(for: .millimolesPerLiter))
                ],
                timeZone: .utcTimeZone
            )!
        default:
            return InsulinSensitivitySchedule(
                unit: HKUnit.milligramsPerDeciliter,
                dailyItems: [
                    RepeatingScheduleValue(startTime: 0.0, value: value)
                ],
                timeZone: .utcTimeZone
            )!
        }
    }
}

@MainActor
class MealDetectionManagerTests: XCTestCase {
    let dateFormatter = ISO8601DateFormatter.localTimeDate()
    let pumpManager = MockPumpManager()

    var mealDetectionManager: MealDetectionManager!

    var now: Date {
        mealDetectionManager.test_currentDate!
    }

    var algorithmInput: StoredDataAlgorithmInput!
    var algorithmOutput: AlgorithmOutput<StoredCarbEntry>!

    var mockAlgorithmState: AlgorithmDisplayState!

    var insulinSensitivityScheduleApplyingOverrideHistory: InsulinSensitivitySchedule?

    var carbRatioSchedule: CarbRatioSchedule?

    var maximumBolus: Double? = 5
    var maximumBasalRatePerHour: Double = 6

    var bolusState: PumpManagerStatus.BolusState? = .noBolus

    func setUp(for testType: MissedMealTestType) {
        // Set up schedules

        let date = testType.currentDate
        let historyStart = date.addingTimeInterval(-.hours(24))

        let glucoseTarget = GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: [.init(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 110))])

        insulinSensitivityScheduleApplyingOverrideHistory = testType.insulinSensitivitySchedule
        carbRatioSchedule = testType.carbSchedule

        algorithmInput = StoredDataAlgorithmInput(
            glucoseHistory: [StoredGlucoseSample(startDate: date, quantity: .init(unit: .milligramsPerDeciliter, doubleValue: 100))],
            doses: [],
            carbEntries: testType.carbEntries.map { $0.asStoredCarbEntry },
            predictionStart: date,
            basal: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!.between(start: historyStart, end: date),
            sensitivity: testType.insulinSensitivitySchedule.quantitiesBetween(start: historyStart, end: date),
            carbRatio: testType.carbSchedule.between(start: historyStart, end: date),
            target: glucoseTarget!.quantityBetween(start: historyStart, end: date),
            suspendThreshold: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 65),
            maxBolus: maximumBolus!,
            maxBasalRate: maximumBasalRatePerHour,
            useIntegralRetrospectiveCorrection: false,
            includePositiveVelocityAndRC: true,
            carbAbsorptionModel: .piecewiseLinear,
            recommendationInsulinModel: ExponentialInsulinModelPreset.rapidActingAdult.model,
            recommendationType: .automaticBolus)

        // These tests don't actually run the loop algorithm directly; they were written to take ICE from fixtures, compute carb effects, and subtract them.
        let counteractionEffects = counteractionEffects(for: testType)

        let carbEntries = testType.carbEntries.map { $0.asStoredCarbEntry }
        // Carb Effects
        let carbStatus = carbEntries.map(
            to: counteractionEffects,
            carbRatio: algorithmInput.carbRatio,
            insulinSensitivity: algorithmInput.sensitivity
        )

        let carbEffects = carbStatus.dynamicGlucoseEffects(
            from: date.addingTimeInterval(-IntegralRetrospectiveCorrection.retrospectionInterval),
            carbRatios: algorithmInput.carbRatio,
            insulinSensitivities: algorithmInput.sensitivity,
            absorptionModel: algorithmInput.carbAbsorptionModel.model
        )

        let effects = LoopAlgorithmEffects(
            insulin: [],
            carbs: carbEffects,
            carbStatus: carbStatus,
            retrospectiveCorrection: [],
            momentum: [],
            insulinCounteraction: counteractionEffects,
            retrospectiveGlucoseDiscrepancies: []
        )

        algorithmOutput = AlgorithmOutput(
            recommendationResult: .success(.init()),
            predictedGlucose: [],
            effects: effects,
            dosesRelativeToBasal: []
        )

        mealDetectionManager = MealDetectionManager(
            algorithmStateProvider: self,
            settingsProvider: self,
            bolusStateProvider: self
        )
        mealDetectionManager.test_currentDate = testType.currentDate

    }
    
    private func counteractionEffects(for testType: MissedMealTestType) -> [GlucoseEffectVelocity] {
        let fixture: [JSONDictionary] = loadFixture(testType.counteractionEffectFixture)
        let dateFormatter = ISO8601DateFormatter.localTimeDate()

        return fixture.map {
            GlucoseEffectVelocity(startDate: dateFormatter.date(from: $0["startDate"] as! String)!,
                                  endDate: dateFormatter.date(from: $0["endDate"] as! String)!,
                                  quantity: HKQuantity(unit: HKUnit(from: $0["unit"] as! String),
                                                       doubleValue:$0["value"] as! Double))
        }
    }
    
    override func tearDown() {
        mealDetectionManager.lastMissedMealNotification = nil
        mealDetectionManager = nil
        UserDefaults.standard.missedMealNotificationsEnabled = false
    }
    
    // MARK: - Algorithm Tests
    func testNoMissedMeal() {
        setUp(for: .noMeal)
        
        let status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: algorithmInput.glucoseHistory,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .noMissedMeal)
    }
    
    func testNoMissedMeal_WithCOB() {
        setUp(for: .noMealWithCOB)

        let status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: algorithmInput.glucoseHistory,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .noMissedMeal)
    }
    
    func testMissedMeal_NoCarbEntry() {
        let testType = MissedMealTestType.missedMealNoCOB
        setUp(for: testType)

        let status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: algorithmInput.glucoseHistory,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 55))
    }
    
    func testDynamicCarbAutofill() {
        let testType = MissedMealTestType.dynamicCarbAutofill
        setUp(for: testType)

        let status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: algorithmInput.glucoseHistory,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 25))
    }
    
    func testMissedMeal_MissedMealAndCOB() {
        let testType = MissedMealTestType.missedMealWithCOB
        setUp(for: testType)

        let status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: algorithmInput.glucoseHistory,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 50))
    }
    
    func testNoisyCGM() {
        setUp(for: .noisyCGM)

        let status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: algorithmInput.glucoseHistory,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .noMissedMeal)
    }
    
    func testManyMeals() {
        let testType = MissedMealTestType.manyMeals
        setUp(for: testType)

        let status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: algorithmInput.glucoseHistory,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 40))
    }
    
    func testMMOLUser() {
        let testType = MissedMealTestType.mmolUser
        setUp(for: testType)

        let status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: algorithmInput.glucoseHistory,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 25))
    }
    
    // MARK: - Notification Tests
    func testNoMissedMealLastNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let status = MissedMealStatus.noMissedMeal
        mealDetectionManager.manageMealNotifications(
            at: now,
            for: status
        )

        mealDetectionManager.manageMealNotifications(at: now, for: status)

        XCTAssertNil(mealDetectionManager.lastMissedMealNotification)
    }

    func testMissedMealUpdatesLastNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(at: now, for: status)

        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.carbAmount, 40)
    }
    
    func testMissedMealWithoutNotificationsEnabled() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = false
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(at: now, for: status)

        XCTAssertNil(mealDetectionManager.lastMissedMealNotification)
    }

    func testMissedMealWithTooRecentNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let oldTime = now.addingTimeInterval(.hours(1))
        let oldNotification = MissedMealNotification(deliveryTime: oldTime, carbAmount: 40)
        mealDetectionManager.lastMissedMealNotification = oldNotification
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: MissedMealSettings.minCarbThreshold)
        mealDetectionManager.manageMealNotifications(at: now, for: status)

        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification, oldNotification)
    }
    
    func testMissedMealCarbClamping() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true

        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 120)
        mealDetectionManager.manageMealNotifications(at: now, for: status)

        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.carbAmount, 75)
    }
    
    func testMissedMealNoPendingBolus() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(at: now, for: status)

        /// The bolus units time delegate should never be called if there are 0 pending units
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.carbAmount, 40)
    }
    
    func testMissedMealLongPendingBolus() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true

        bolusState = .inProgress(
            DoseEntry(
                type: .bolus,
                startDate: now.addingTimeInterval(-.seconds(10)),
                endDate: now.addingTimeInterval(.minutes(10)),
                value: 20,
                unit: .units,
                automatic: true
            )
        )

        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(at: now, for: status)

        /// There shouldn't be a delay in delivering notification, since the autobolus will take the length of the notification window to deliver
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.carbAmount, 40)
    }
    
    func testNoMissedMealShortPendingBolus_DelaysNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true

        bolusState = .inProgress(
            DoseEntry(
                type: .bolus,
                startDate: now.addingTimeInterval(-.seconds(10)),
                endDate: now.addingTimeInterval(20),
                value: 2,
                unit: .units,
                automatic: true
            )
        )

        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 30)
        mealDetectionManager.manageMealNotifications(at: now, for: status)

        let expectedDeliveryTime = now.addingTimeInterval(TimeInterval(20))
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, expectedDeliveryTime)

        bolusState = .inProgress(
            DoseEntry(
                type: .bolus,
                startDate: now.addingTimeInterval(-.seconds(10)),
                endDate: now.addingTimeInterval(.minutes(3)),
                value: 4.5,
                unit: .units,
                automatic: true
            )
        )

        mealDetectionManager.lastMissedMealNotification = nil
        mealDetectionManager.manageMealNotifications(at: now, for: status)

        let expectedDeliveryTime2 = now.addingTimeInterval(TimeInterval(minutes: 3))
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, expectedDeliveryTime2)
    }
    
    func testHasCalibrationPoints_NoNotification() {
        let testType = MissedMealTestType.manyMeals
        setUp(for: testType)

        let calibratedGlucoseSamples = [MockGlucoseSample(startDate: now), MockGlucoseSample(startDate: now, isDisplayOnly: true)]

        var status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: calibratedGlucoseSamples,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .noMissedMeal)

        let manualGlucoseSamples = [MockGlucoseSample(startDate: now), MockGlucoseSample(startDate: now, wasUserEntered: true)]

        status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: manualGlucoseSamples,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .noMissedMeal)
    }
    
    func testHasTooOldCalibrationPoint_NoImpactOnNotificationDelivery() {
        let testType = MissedMealTestType.manyMeals
        setUp(for: testType)

        let tooOldCalibratedGlucoseSamples = [MockGlucoseSample(startDate: now, isDisplayOnly: false), MockGlucoseSample(startDate: now.addingTimeInterval(-MissedMealSettings.maxRecency-1), isDisplayOnly: true)]
        
        let status = mealDetectionManager.hasMissedMeal(
            at: now,
            glucoseSamples: tooOldCalibratedGlucoseSamples,
            insulinCounteractionEffects: algorithmOutput.effects.insulinCounteraction,
            carbEffects: algorithmOutput.effects.carbs,
            sensitivitySchedule: insulinSensitivityScheduleApplyingOverrideHistory!,
            carbRatioSchedule: carbRatioSchedule!
        )

        XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 40))
    }
}

extension MealDetectionManagerTests: AlgorithmDisplayStateProvider {
    var algorithmState: AlgorithmDisplayState {
        get async {
            return mockAlgorithmState
        }
    }
}

extension MealDetectionManagerTests: BolusStateProvider { }

extension MealDetectionManagerTests: SettingsWithOverridesProvider { }

extension MealDetectionManagerTests {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }
}
