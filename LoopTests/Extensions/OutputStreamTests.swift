//
//  OutputStreamTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 9/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import Foundation
@testable import LoopKit

class OutputStreamTests: XCTestCase {
    private let string = "The quick brown fox jumps over the lazy dog"

    func testWriteString() {
        let outputStream = MockOutputStream()
        XCTAssertNoThrow(try outputStream.write(string))
        XCTAssertEqual(outputStream.string, string)
    }

    func testWriteStringThrowsError() {
        let outputStream = MockOutputStream()
        outputStream.error = MockError()
        XCTAssertThrowsError(try outputStream.write(string)) { error in
            XCTAssertEqual(error as! MockError, outputStream.error as! MockError)
        }
    }

    func testWriteData() {
        let data = string.data(using: .utf8)!
        let outputStream = MockOutputStream()
        XCTAssertNoThrow(try outputStream.write(data))
        XCTAssertEqual(outputStream.data, data)
    }

    func testWriteDataThrowsError() {
        let data = string.data(using: .utf8)!
        let outputStream = MockOutputStream()
        outputStream.error = MockError()
        XCTAssertThrowsError(try outputStream.write(data)) { error in
            XCTAssertEqual(error as! MockError, outputStream.error as! MockError)
        }
    }
}

fileprivate struct MockError: Error, Equatable {}
