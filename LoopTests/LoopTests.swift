//
//  LoopTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 9/18/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import XCTest

@testable import Loop

class LoopTests: XCTestCase {}

extension XCTestCase {
    
    func waitOnMain(timeout: TimeInterval = 1.0, file: StaticString = #file, function: String = #function, line: UInt = #line) {
        let exp = expectation(description: function)
        var fulfilled = false
        DispatchQueue.main.async {
            fulfilled = true
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
        XCTAssertTrue(fulfilled, "Failed to wait on main in \(function)", file: file, line: line)
    }

}
