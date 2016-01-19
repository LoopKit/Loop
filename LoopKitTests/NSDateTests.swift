//
//  NSDateTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/18/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import LoopKit

class NSDateTests: XCTestCase {

    func testDateCeiledToInterval() {
        let calendar = NSCalendar.currentCalendar()

        let five01 = calendar.nextDateAfterDate(NSDate(), matchingHour: 5, minute: 0, second: 1, options: .MatchNextTime)!

        let five05 = calendar.nextDateAfterDate(five01, matchingHour: 5, minute: 5, second: 0, options: .MatchNextTime)!

        XCTAssertEqual(five05, five01.dateCeiledToTimeInterval(NSTimeInterval(minutes: 5)))

        let six = calendar.nextDateAfterDate(five01, matchingHour: 6, minute: 0, second: 0, options: .MatchNextTime)!

        XCTAssertEqual(six, five01.dateCeiledToTimeInterval(NSTimeInterval(minutes: 60)))

        XCTAssertEqual(five05, five05.dateCeiledToTimeInterval(NSTimeInterval(minutes: 5)))

        let five47 = calendar.nextDateAfterDate(five01, matchingHour: 5, minute: 47, second: 58, options: .MatchNextTime)!

        let five50 = calendar.nextDateAfterDate(five01, matchingHour: 5, minute: 50, second: 0, options: .MatchNextTime)!

        XCTAssertEqual(five50, five47.dateCeiledToTimeInterval(NSTimeInterval(minutes: 5)))

        let twentyThree59 = calendar.nextDateAfterDate(five01, matchingHour: 23, minute: 59, second: 0, options: .MatchNextTime)!

        let tomorrowMidnight = calendar.nextDateAfterDate(five01, matchingHour: 0, minute: 0, second: 0, options: .MatchNextTime)!

        XCTAssertEqual(tomorrowMidnight, twentyThree59.dateCeiledToTimeInterval(NSTimeInterval(minutes: 5)))

        XCTAssertEqual(five01, five01.dateCeiledToTimeInterval(NSTimeInterval(0)))
    }

    func testDateFlooredToInterval() {
        let calendar = NSCalendar.currentCalendar()

        let five01 = calendar.nextDateAfterDate(NSDate(), matchingHour: 5, minute: 0, second: 1, options: .MatchNextTime)!

        let five = calendar.nextDateAfterDate(five01, matchingHour: 5, minute: 0, second: 0, options: [.SearchBackwards, .MatchNextTime])!

        XCTAssertEqual(five, five01.dateFlooredToTimeInterval(NSTimeInterval(minutes: 5)))

        let five59 = calendar.nextDateAfterDate(five01, matchingHour: 5, minute: 59, second: 0, options: .MatchNextTime)!

        XCTAssertEqual(five, five59.dateFlooredToTimeInterval(NSTimeInterval(minutes: 60)))

        let five55 = calendar.nextDateAfterDate(five01, matchingHour: 5, minute: 55, second: 0, options: .MatchNextTime)!

        XCTAssertEqual(five55, five59.dateFlooredToTimeInterval(NSTimeInterval(minutes: 5)))


        XCTAssertEqual(five, five.dateFlooredToTimeInterval(NSTimeInterval(minutes: 5)))
        
        XCTAssertEqual(five01, five01.dateFlooredToTimeInterval(NSTimeInterval(0)))
    }
}
