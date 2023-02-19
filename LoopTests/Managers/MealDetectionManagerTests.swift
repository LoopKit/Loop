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
@testable import Loop

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
        case .dynamicCarbAutofill:
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
        case .dynamicCarbAutofill:
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
        case .dynamicCarbAutofill:
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
        InsulinSensitivitySchedule(
            unit: HKUnit.milligramsPerDeciliter,
            dailyItems: [
                RepeatingScheduleValue(startTime: 0.0, value: 50.0)
            ],
            timeZone: .utcTimeZone
        )!
    }
}

class MealDetectionManagerTests: XCTestCase {
    let dateFormatter = ISO8601DateFormatter.localTimeDate()
    let pumpManager = MockPumpManager()

    var mealDetectionManager: MealDetectionManager!
    var carbStore: CarbStore!
    
    var now: Date {
        mealDetectionManager.test_currentDate!
    }
    
    var bolusUnits: Double?
    var bolusDurationEstimator: ((Double) -> TimeInterval?)!
    
    @discardableResult func setUp(for testType: MissedMealTestType) -> [GlucoseEffectVelocity] {
        let healthStore = HKHealthStoreMock()
        
        carbStore = CarbStore(
            healthStore: healthStore,
            cacheStore: PersistenceController(directoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)),
            cacheLength: .hours(24),
            defaultAbsorptionTimes: (fast: .minutes(30), medium: .hours(3), slow: .hours(5)),
            observationInterval: 0,
            overrideHistory: TemporaryScheduleOverrideHistory(),
            provenanceIdentifier: Bundle.main.bundleIdentifier!,
            test_currentDate: testType.currentDate)
        
        // Set up schedules
        carbStore.carbRatioSchedule = testType.carbSchedule
        carbStore.insulinSensitivitySchedule = testType.insulinSensitivitySchedule

        // Add any needed carb entries to the carb store
        let updateGroup = DispatchGroup()
        testType.carbEntries.forEach { carbEntry in
            updateGroup.enter()
            carbStore.addCarbEntry(carbEntry) { result in
                if case .failure(_) = result {
                    XCTFail("Failed to add carb entry to carb store")
                }

                updateGroup.leave()
            }
        }
        _ = updateGroup.wait(timeout: .now() + .seconds(5))
        
        mealDetectionManager = MealDetectionManager(
            carbRatioScheduleApplyingOverrideHistory: carbStore.carbRatioScheduleApplyingOverrideHistory,
            insulinSensitivityScheduleApplyingOverrideHistory: carbStore.insulinSensitivityScheduleApplyingOverrideHistory,
            maximumBolus: 5,
            test_currentDate: testType.currentDate
        )
        
        bolusDurationEstimator = { units in
            self.bolusUnits = units
            return self.pumpManager.estimatedDuration(toBolus: units)
        }
        
        // Fetch & return the counteraction effects for the test
        return counteractionEffects(for: testType)
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
    
    private func mealDetectionCarbEffects(using insulinCounteractionEffects: [GlucoseEffectVelocity]) -> [GlucoseEffect] {
        let carbEffectStart = now.addingTimeInterval(-MissedMealSettings.maxRecency)
        
        var carbEffects: [GlucoseEffect] = []
        
        let updateGroup = DispatchGroup()
        updateGroup.enter()
        carbStore.getGlucoseEffects(start: carbEffectStart, end: now, effectVelocities: insulinCounteractionEffects) { result in
            defer { updateGroup.leave() }
            
            guard case .success((_, let effects)) = result else {
                XCTFail("Failed to fetch glucose effects to check for missed meal")
                return
            }
            carbEffects = effects
        }
        _ = updateGroup.wait(timeout: .now() + .seconds(5))
        
        return carbEffects
    }
    
    override func tearDown() {
        mealDetectionManager.lastMissedMealNotification = nil
        mealDetectionManager = nil
        UserDefaults.standard.missedMealNotificationsEnabled = false
    }
    
    // MARK: - Algorithm Tests
    func testNoMissedMeal() {
        let counteractionEffects = setUp(for: .noMeal)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasMissedMeal(insulinCounteractionEffects: counteractionEffects, carbEffects: mealDetectionCarbEffects(using: counteractionEffects)) { status in
            XCTAssertEqual(status, .noMissedMeal)
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testNoMissedMeal_WithCOB() {
        let counteractionEffects = setUp(for: .noMealWithCOB)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasMissedMeal(insulinCounteractionEffects: counteractionEffects, carbEffects: mealDetectionCarbEffects(using: counteractionEffects)) { status in
            XCTAssertEqual(status, .noMissedMeal)
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testMissedMeal_NoCarbEntry() {
        let testType = MissedMealTestType.missedMealNoCOB
        let counteractionEffects = setUp(for: testType)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasMissedMeal(insulinCounteractionEffects: counteractionEffects, carbEffects: mealDetectionCarbEffects(using: counteractionEffects)) { status in
            XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 55))
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testDynamicCarbAutofill() {
        let testType = MissedMealTestType.dynamicCarbAutofill
        let counteractionEffects = setUp(for: testType)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasMissedMeal(insulinCounteractionEffects: counteractionEffects, carbEffects: mealDetectionCarbEffects(using: counteractionEffects)) { status in
            XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 25))
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testMissedMeal_MissedMealAndCOB() {
        let testType = MissedMealTestType.missedMealWithCOB
        let counteractionEffects = setUp(for: testType)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasMissedMeal(insulinCounteractionEffects: counteractionEffects, carbEffects: mealDetectionCarbEffects(using: counteractionEffects)) { status in
            XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 50))
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testNoisyCGM() {
        let counteractionEffects = setUp(for: .noisyCGM)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasMissedMeal(insulinCounteractionEffects: counteractionEffects, carbEffects: mealDetectionCarbEffects(using: counteractionEffects)) { status in
            XCTAssertEqual(status, .noMissedMeal)
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testManyMeals() {
        let testType = MissedMealTestType.manyMeals
        let counteractionEffects = setUp(for: testType)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasMissedMeal(insulinCounteractionEffects: counteractionEffects, carbEffects: mealDetectionCarbEffects(using: counteractionEffects)) { status in
            XCTAssertEqual(status, .hasMissedMeal(startTime: testType.missedMealDate!, carbAmount: 40))
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    // MARK: - Notification Tests
    func testNoMissedMealLastNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let status = MissedMealStatus.noMissedMeal
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertNil(mealDetectionManager.lastMissedMealNotification)
    }

    func testMissedMealUpdatesLastNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.carbAmount, 40)
    }
    
    func testMissedMealWithoutNotificationsEnabled() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = false
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertNil(mealDetectionManager.lastMissedMealNotification)
    }

    func testMissedMealWithTooRecentNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let oldTime = now.addingTimeInterval(.hours(1))
        let oldNotification = MissedMealNotification(deliveryTime: oldTime, carbAmount: 40)
        mealDetectionManager.lastMissedMealNotification = oldNotification
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: MissedMealSettings.minCarbThreshold)
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification, oldNotification)
    }
    
    func testMissedMealCarbClamping() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true

        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 120)
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.carbAmount, 75)
    }
    
    func testMissedMealNoPendingBolus() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(for: status, pendingAutobolusUnits: 0, bolusDurationEstimator: bolusDurationEstimator)
        
        /// The bolus units time delegate should never be called if there are 0 pending units
        XCTAssertNil(bolusUnits)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.carbAmount, 40)
    }
    
    func testMissedMealLongPendingBolus() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(for: status, pendingAutobolusUnits: 10, bolusDurationEstimator: bolusDurationEstimator)
        
        XCTAssertEqual(bolusUnits, 10)
        /// There shouldn't be a delay in delivering notification, since the autobolus will take the length of the notification window to deliver
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.carbAmount, 40)
    }
    
    func testNoMissedMealShortPendingBolus_DelaysNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.missedMealNotificationsEnabled = true
        
        let status = MissedMealStatus.hasMissedMeal(startTime: now, carbAmount: 30)
        mealDetectionManager.manageMealNotifications(for: status, pendingAutobolusUnits: 2, bolusDurationEstimator: bolusDurationEstimator)
        
        let expectedDeliveryTime = now.addingTimeInterval(TimeInterval(80))
        XCTAssertEqual(bolusUnits, 2)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, expectedDeliveryTime)
        
        mealDetectionManager.lastMissedMealNotification = nil
        mealDetectionManager.manageMealNotifications(for: status, pendingAutobolusUnits: 4.5, bolusDurationEstimator: bolusDurationEstimator)
        
        let expectedDeliveryTime2 = now.addingTimeInterval(TimeInterval(minutes: 3))
        XCTAssertEqual(bolusUnits, 4.5)
        XCTAssertEqual(mealDetectionManager.lastMissedMealNotification?.deliveryTime, expectedDeliveryTime2)
    }
}

extension MealDetectionManagerTests {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }
}
