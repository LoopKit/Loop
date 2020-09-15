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
    
    func waitOnMain() {
        let exp = expectation(description: "waitOnMain")
        DispatchQueue.main.async {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

}
