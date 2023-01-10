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

enum UAMTestType {
    private static var dateFormatter = ISO8601DateFormatter.localTimeDate()
    
    /// No meal is present
    case noMeal
    /// No meal is present, but if the counteraction effects aren't clamped properly it will look like there's a UAM
    case noMealCounteractionEffectsNeedClamping
    // No meal is present and there is COB
    case noMealWithCOB
    /// UAM with no carbs on board
    case unannouncedMealNoCOB
    /// UAM with carbs logged prior to it
    case unannouncedMealWithCOB
    /// There is a meal, but it's announced and not unannounced
    case announcedMeal
    /// CGM data is noisy, but no meal is present
    case noisyCGM
    /// Realistic counteraction effects with multiple meals
    case manyMeals
    /// Test case to test dynamic computation of missed meal carb amount
    case dynamicCarbAutofill
    /// Test case for purely testing the notifications (not the algorithm)
    case notificationTest
}

extension UAMTestType {
    var counteractionEffectFixture: String {
        switch self {
        case .unannouncedMealNoCOB, .noMealWithCOB, .notificationTest:
            return "uam_counteraction_effect"
        case .noMeal, .announcedMeal:
            return "long_interval_counteraction_effect"
        case .noMealCounteractionEffectsNeedClamping:
            return "needs_clamping_counteraction_effect"
        case .noisyCGM:
            return "noisy_cgm_counteraction_effect"
        case .manyMeals, .unannouncedMealWithCOB:
            return "realistic_report_counteraction_effect"
        case .dynamicCarbAutofill:
            return "dynamic_autofill_counteraction_effect"
        }
    }
    
    var currentDate: Date {
        switch self {
        case .unannouncedMealNoCOB, .noMealWithCOB, .notificationTest:
            return Self.dateFormatter.date(from: "2022-10-17T23:28:45")!
        case .noMeal, .noMealCounteractionEffectsNeedClamping, .announcedMeal:
            return Self.dateFormatter.date(from: "2022-10-17T02:49:16")!
        case .noisyCGM:
            return Self.dateFormatter.date(from: "2022-10-19T20:46:23")!
        case .unannouncedMealWithCOB:
            return Self.dateFormatter.date(from: "2022-10-19T19:50:15")!
        case .manyMeals:
            return Self.dateFormatter.date(from: "2022-10-19T21:50:15")!
        case .dynamicCarbAutofill:
            return Self.dateFormatter.date(from: "2022-10-17T07:51:09")!
        }
    }
    
    var uamDate: Date? {
        switch self {
        case .unannouncedMealNoCOB:
            return Self.dateFormatter.date(from: "2022-10-17T22:10:00")
        case .unannouncedMealWithCOB:
            return Self.dateFormatter.date(from: "2022-10-19T19:15:00")
        case .dynamicCarbAutofill:
            return Self.dateFormatter.date(from: "2022-10-17T07:20:00")!
        default:
            return nil
        }
    }
    
    var carbEntries: [NewCarbEntry] {
        switch self {
        case .unannouncedMealWithCOB:
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
        case .announcedMeal:
            return [
                NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 40),
                             startDate: Self.dateFormatter.date(from: "2022-10-17T01:06:52")!,
                             foodType: nil,
                             absorptionTime: nil),
                NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 1),
                             startDate: Self.dateFormatter.date(from: "2022-10-17T02:15:00")!,
                             foodType: nil,
                             absorptionTime: nil),
                NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 30),
                             startDate: Self.dateFormatter.date(from: "2022-10-17T02:35:00")!,
                             foodType: nil,
                             absorptionTime: nil),
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
    
    var now: Date {
        mealDetectionManager.test_currentDate!
    }
    
    var bolusUnits: Double?
    var bolusDurationEstimator: ((Double) -> TimeInterval?)!
    
    @discardableResult func setUp(for testType: UAMTestType) -> [GlucoseEffectVelocity] {
        let healthStore = HKHealthStoreMock()
        
        let carbStore = CarbStore(
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
            carbStore: carbStore,
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
    
    private func counteractionEffects(for testType: UAMTestType) -> [GlucoseEffectVelocity] {
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
        mealDetectionManager.lastUAMNotification = nil
        mealDetectionManager = nil
        UserDefaults.standard.unannouncedMealNotificationsEnabled = false
    }
    
    // MARK: - Algorithm Tests
    func testNoUnannouncedMeal() {
        let counteractionEffects = setUp(for: .noMeal)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasUnannouncedMeal(insulinCounteractionEffects: counteractionEffects) { status in
            XCTAssertEqual(status, .noUnannouncedMeal)
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testNoUnannouncedMeal_WithCOB() {
        let counteractionEffects = setUp(for: .noMealWithCOB)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasUnannouncedMeal(insulinCounteractionEffects: counteractionEffects) { status in
            XCTAssertEqual(status, .noUnannouncedMeal)
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testUnannouncedMeal_NoCarbEntry() {
        let testType = UAMTestType.unannouncedMealNoCOB
        let counteractionEffects = setUp(for: testType)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasUnannouncedMeal(insulinCounteractionEffects: counteractionEffects) { status in
            XCTAssertEqual(status, .hasUnannouncedMeal(startTime: testType.uamDate!, carbAmount: 55))
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testDynamicCarbAutofill() {
        let testType = UAMTestType.dynamicCarbAutofill
        let counteractionEffects = setUp(for: testType)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasUnannouncedMeal(insulinCounteractionEffects: counteractionEffects) { status in
            XCTAssertEqual(status, .hasUnannouncedMeal(startTime: testType.uamDate!, carbAmount: 25))
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testUnannouncedMeal_UAMAndCOB() {
        let testType = UAMTestType.unannouncedMealWithCOB
        let counteractionEffects = setUp(for: testType)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasUnannouncedMeal(insulinCounteractionEffects: counteractionEffects) { status in
            XCTAssertEqual(status, .hasUnannouncedMeal(startTime: testType.uamDate!, carbAmount: 50))
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testNoUnannouncedMeal_AnnouncedMealPresent() {
        let counteractionEffects = setUp(for: .announcedMeal)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasUnannouncedMeal(insulinCounteractionEffects: counteractionEffects) { status in
            XCTAssertEqual(status, .noUnannouncedMeal)
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testNoisyCGM() {
        let counteractionEffects = setUp(for: .noisyCGM)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasUnannouncedMeal(insulinCounteractionEffects: counteractionEffects) { status in
            XCTAssertEqual(status, .noUnannouncedMeal)
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    func testManyMeals() {
        let counteractionEffects = setUp(for: .manyMeals)

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        mealDetectionManager.hasUnannouncedMeal(insulinCounteractionEffects: counteractionEffects) { status in
            XCTAssertEqual(status, .noUnannouncedMeal)
            updateGroup.leave()
        }
        updateGroup.wait()
    }
    
    // MARK: - Notification Tests
    func testNoUnannouncedMealLastNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.noUnannouncedMeal
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertNil(mealDetectionManager.lastUAMNotification)
    }

    func testUnannouncedMealUpdatesLastNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.carbAmount, 40)
    }
    
    func testUnannouncedMealWithoutNotificationsEnabled() {
        setUp(for: .notificationTest)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = false
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertNil(mealDetectionManager.lastUAMNotification)
    }

    func testUnannouncedMealWithTooRecentNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let oldTime = now.addingTimeInterval(.hours(1))
        let oldNotification = UAMNotification(deliveryTime: oldTime, carbAmount: 40)
        mealDetectionManager.lastUAMNotification = oldNotification
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now, carbAmount: UAMSettings.minCarbThreshold)
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertEqual(mealDetectionManager.lastUAMNotification, oldNotification)
    }
    
    func testUnannouncedMealCarbClamping() {
        setUp(for: .notificationTest)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true

        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now, carbAmount: 120)
        mealDetectionManager.manageMealNotifications(for: status, bolusDurationEstimator: { _ in nil })
        
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.carbAmount, 75)
    }
    
    func testUnannouncedMealNoPendingBolus() {
        setUp(for: .notificationTest)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(for: status, pendingAutobolusUnits: 0, bolusDurationEstimator: bolusDurationEstimator)
        
        /// The bolus units time delegate should never be called if there are 0 pending units
        XCTAssertNil(bolusUnits)
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.carbAmount, 40)
    }
    
    func testUnannouncedMealLongPendingBolus() {
        setUp(for: .notificationTest)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now, carbAmount: 40)
        mealDetectionManager.manageMealNotifications(for: status, pendingAutobolusUnits: 10, bolusDurationEstimator: bolusDurationEstimator)
        
        XCTAssertEqual(bolusUnits, 10)
        /// There shouldn't be a delay in delivering notification, since the autobolus will take the length of the notification window to deliver
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.deliveryTime, now)
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.carbAmount, 40)
    }
    
    func testNoUnannouncedMealShortPendingBolus_DelaysNotificationTime() {
        setUp(for: .notificationTest)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now, carbAmount: 30)
        mealDetectionManager.manageMealNotifications(for: status, pendingAutobolusUnits: 2, bolusDurationEstimator: bolusDurationEstimator)
        
        let expectedDeliveryTime = now.addingTimeInterval(TimeInterval(80))
        XCTAssertEqual(bolusUnits, 2)
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.deliveryTime, expectedDeliveryTime)
        
        mealDetectionManager.lastUAMNotification = nil
        mealDetectionManager.manageMealNotifications(for: status, pendingAutobolusUnits: 4.5, bolusDurationEstimator: bolusDurationEstimator)
        
        let expectedDeliveryTime2 = now.addingTimeInterval(TimeInterval(minutes: 3))
        XCTAssertEqual(bolusUnits, 4.5)
        XCTAssertEqual(mealDetectionManager.lastUAMNotification?.deliveryTime, expectedDeliveryTime2)
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
