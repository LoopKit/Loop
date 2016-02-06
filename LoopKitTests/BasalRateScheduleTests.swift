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
    
    var items: [RepeatingScheduleValue]!

    override func setUp() {
        super.setUp()

        let path = NSBundle(forClass: self.dynamicType).pathForResource("basal", ofType: "json")!
        let fixture = try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! [JSONDictionary]

        items = fixture.map {
            return RepeatingScheduleValue(startTime: NSTimeInterval(minutes: $0["minutes"] as! Double), value: $0["rate"] as! Double)
        }
    }

    func testBasalScheduleRanges() {
        let schedule = BasalRateSchedule(dailyItems: items)!
        let calendar = NSCalendar.currentCalendar()

        let midnight = calendar.startOfDayForDate(NSDate())

        var absoluteItems: [AbsoluteScheduleValue] = items[0..<items.count].map {
            AbsoluteScheduleValue(startDate: midnight.dateByAddingTimeInterval($0.startTime), value: $0.value)
        }

        absoluteItems += items[0..<items.count].map {
            AbsoluteScheduleValue(startDate: midnight.dateByAddingTimeInterval($0.startTime + NSTimeInterval(hours: 24)), value: $0.value)
        }

        XCTAssertEqual(
            absoluteItems[0..<items.count],
            schedule.between(
                midnight,
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 24))
            )[0..<items.count]
        )

        let twentyThree30 = midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 23)).dateByAddingTimeInterval(NSTimeInterval(minutes: 30))

        XCTAssertEqual(
            absoluteItems[0..<items.count],
            schedule.between(
                midnight,
                twentyThree30
            )[0..<items.count]
        )

        XCTAssertEqual(
            absoluteItems[0..<items.count + 1],
            schedule.between(
                midnight,
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 24) + NSTimeInterval(1))
            )[0..<items.count + 1]
        )

        XCTAssertEqual(
            absoluteItems[items.count - 1..<items.count * 2],
            schedule.between(
                twentyThree30,
                twentyThree30.dateByAddingTimeInterval(NSTimeInterval(hours: 24))
            )[0..<items.count + 1]
        )

        XCTAssertEqual(
            absoluteItems[0..<1],
            schedule.between(
                midnight,
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 1))
            )[0..<1]
        )

        XCTAssertEqual(
            absoluteItems[1..<3],
            schedule.between(
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 4)),
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 9))
            )[0..<2]
        )

        XCTAssertEqual(
            absoluteItems[5..<6],
            schedule.between(
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 16)),
                midnight.dateByAddingTimeInterval(NSTimeInterval(hours: 20))
            )[0..<1]
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
