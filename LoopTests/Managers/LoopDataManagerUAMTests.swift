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
    override func tearDownWithError() throws {
        loopDataManager.lastUAMNotificationDeliveryTime = nil
        try super.tearDownWithError()
    }
    
    func testNoUnannouncedMealLastNotificationTime() {
        setUp(for: .highAndRisingWithCOB)
        XCTAssertNil(loopDataManager.lastUAMNotificationDeliveryTime)
        
        let status = UnannouncedMealStatus.noUnannouncedMeal
        loopDataManager.manageMealNotifications(for: status)
        XCTAssertNil(loopDataManager.lastUAMNotificationDeliveryTime)
    }

    func testUnannouncedMealUpdatesLastNotificationTime() {
        setUp(for: .highAndRisingWithCOB)
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now)
        loopDataManager.manageMealNotifications(for: status)
        XCTAssertEqual(loopDataManager.lastUAMNotificationDeliveryTime, now)
    }

    func testUnannouncedMealWithTooRecentNotificationTime() {
        setUp(for: .highAndRisingWithCOB)
        
        let oldTime = now.addingTimeInterval(.hours(1))
        loopDataManager.lastUAMNotificationDeliveryTime = oldTime
        
        let status = UnannouncedMealStatus.hasUnannouncedMeal(startTime: now)
        loopDataManager.manageMealNotifications(for: status)
        XCTAssertEqual(loopDataManager.lastUAMNotificationDeliveryTime, oldTime)
    }
}

