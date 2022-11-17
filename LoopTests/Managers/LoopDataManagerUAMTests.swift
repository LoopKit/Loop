//
//  LoopDataManagerUAMTests.swift
//  LoopTests
//
//  Created by Anna Quinlan on 10/19/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
@testable import LoopCore
@testable import Loop

class LoopDataManagerUAMTests: LoopDataManagerTests {
    // MARK: Testing Utilities
    override func tearDownWithError() throws {
        loopDataManager.lastUAMNotificationDeliveryTime = nil
        UserDefaults.standard.unannouncedMealNotificationsEnabled = false
        try super.tearDownWithError()
    }
    
    // MARK: Tests
    func testNoUnannouncedMealLastNotificationTime() {
        setUp(for: .highAndRisingWithCOB)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.noUnannouncedMeal
        loopDataManager.manageMealNotifications(for: status)
        
        XCTAssertNil(loopDataManager.lastUAMNotificationDeliveryTime)
    }

    func testUnannouncedMealUpdatesLastNotificationTime() {
        setUp(for: .highAndRisingWithCOB)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now)
        loopDataManager.manageMealNotifications(for: status)
        
        XCTAssertEqual(loopDataManager.lastUAMNotificationDeliveryTime, now)
    }
    
    func testUnannouncedMealWithoutNotificationsEnabled() {
        setUp(for: .highAndRisingWithCOB)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = false
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now)
        loopDataManager.manageMealNotifications(for: status)
        
        XCTAssertNil(loopDataManager.lastUAMNotificationDeliveryTime)
    }

    func testUnannouncedMealWithTooRecentNotificationTime() {
        setUp(for: .highAndRisingWithCOB)
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let oldTime = now.addingTimeInterval(.hours(1))
        loopDataManager.lastUAMNotificationDeliveryTime = oldTime
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now)
        loopDataManager.manageMealNotifications(for: status)
        
        XCTAssertEqual(loopDataManager.lastUAMNotificationDeliveryTime, oldTime)
    }
    
    func testUnannouncedMealNoPendingBolus() {
        setUp(for: .highAndRisingWithCOB)
        
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now)
        loopDataManager.manageMealNotifications(for: status, pendingAutobolusUnits: 0)
        
        /// The bolus units time delegate should never be called if there are 0 pending units
        XCTAssertNil(delegate.bolusUnits)
        XCTAssertEqual(loopDataManager.lastUAMNotificationDeliveryTime, now)
    }
    
    func testUnannouncedMealLongPendingBolus() {
        setUp(for: .highAndRisingWithCOB)
        
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now)
        loopDataManager.manageMealNotifications(for: status, pendingAutobolusUnits: 10)
        
        XCTAssertEqual(delegate.bolusUnits, 10)
        XCTAssertEqual(loopDataManager.lastUAMNotificationDeliveryTime, now)
    }
    
    func testNoUnannouncedMealShortPendingBolus_DelaysNotificationTime() {
        setUp(for: .highAndRisingWithCOB)
        
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate
        UserDefaults.standard.unannouncedMealNotificationsEnabled = true
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now)
        loopDataManager.manageMealNotifications(for: status, pendingAutobolusUnits: 2)
        
        let expectedDeliveryTime = now.addingTimeInterval(TimeInterval(80))
        XCTAssertEqual(delegate.bolusUnits, 2)
        XCTAssertEqual(loopDataManager.lastUAMNotificationDeliveryTime, expectedDeliveryTime)
        
        loopDataManager.lastUAMNotificationDeliveryTime = nil
        loopDataManager.manageMealNotifications(for: status, pendingAutobolusUnits: 4.5)
        
        let expectedDeliveryTime2 = now.addingTimeInterval(TimeInterval(minutes: 3))
        XCTAssertEqual(delegate.bolusUnits, 4.5)
        XCTAssertEqual(loopDataManager.lastUAMNotificationDeliveryTime, expectedDeliveryTime2)
    }
}

