//
//  BasalRateScheduleTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import LoopKit


class BasalRateScheduleTests: XCTestCase {
    
    var items: [ScheduleItem]!

    override func setUp() {
        super.setUp()

        let path = NSBundle(forClass: self.dynamicType).pathForResource("basal", ofType: "json")!
        let fixture = try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! [JSONDictionary]

        items = fixture.map {
            return ScheduleItem(startTime: NSTimeInterval(minutes: $0["minutes"] as! Double), value: $0["rate"] as! Double)
        }
    }

    func testBasalScheduleRanges() {
        let schedule = BasalRateSchedule(dailyItems: items)!
        let calendar = NSCalendar.currentCalendar()

        let midnight = calendar.startOfDayForDate(NSDate())

        XCTAssertEqual(
            items[0..<items.count],
            schedule.between(
                midnight,
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 24))
            )
        )

        let twentyThree30 = midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 23)).dateByAddingTimeInterval(NSTimeInterval(minutes: 30))

        XCTAssertEqual(
            items[0..<items.count],
            schedule.between(
                midnight,
                twentyThree30
            )
        )

        XCTAssertEqual(
            items[0..<items.count] + items[0...0],
            schedule.between(
                midnight,
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 24) + NSTimeInterval(1))
            )
        )

        XCTAssertEqual(
            items[items.count - 1..<items.count] + items[0..<items.count],
            schedule.between(
                twentyThree30,
                twentyThree30.dateByAddingTimeInterval(NSTimeInterval(hours: 24))
            )
        )

        XCTAssertEqual(
            items[0..<1],
            schedule.between(
                midnight,
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 1))
            )
        )

        XCTAssertEqual(
            items[1..<3],
            schedule.between(
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 4)),
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 9))
            )
        )

        XCTAssertEqual(
            items[5..<6],
            schedule.between(
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 16)),
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 20))
            )
        )

        XCTAssertEqual(
            [],
            schedule.between(
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 4)),
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 3))
            )
        )
    }

}
