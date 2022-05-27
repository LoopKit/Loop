//
//  DiagnosticLogTests.swift
//  LoopKitTests
//
//  Created by Darin Krauss on 8/23/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import XCTest
import os.log
import LoopKit
@testable import Loop

class DiagnosticLogTests: XCTestCase {
    
    fileprivate var testLogging: TestLogging!
    
    override func setUp() {
        testLogging = TestLogging()
        SharedLogging.instance = testLogging
    }
    
    override func tearDown() {
        SharedLogging.instance = nil
        testLogging = nil
    }
    
    func testInitializer() {
        XCTAssertNotNil(DiagnosticLog(subsystem: "subsystem", category: "category"))
    }
    
    func testDebugWithoutArguments() {
        let diagnosticLog = DiagnosticLog(subsystem: "debug subsystem", category: "debug category")
        
        diagnosticLog.debug("debug message without arguments")
        
        XCTAssertEqual(testLogging.message.description, "debug message without arguments")
        XCTAssertEqual(testLogging.subsystem, "debug subsystem")
        XCTAssertEqual(testLogging.category, "debug category")
        XCTAssertEqual(testLogging.type, .debug)
        XCTAssertEqual(testLogging.args.count, 0)
    }
    
    func testDebugWithArguments() {
        let diagnosticLog = DiagnosticLog(subsystem: "debug subsystem", category: "debug category")
        
        diagnosticLog.debug("debug message with arguments", "a")
        
        XCTAssertEqual(testLogging.message.description, "debug message with arguments")
        XCTAssertEqual(testLogging.subsystem, "debug subsystem")
        XCTAssertEqual(testLogging.category, "debug category")
        XCTAssertEqual(testLogging.type, .debug)
        XCTAssertEqual(testLogging.args.count, 1)
    }
    
    func testInfoWithoutArguments() {
        let diagnosticLog = DiagnosticLog(subsystem: "info subsystem", category: "info category")
        
        diagnosticLog.info("info message without arguments")
        
        XCTAssertEqual(testLogging.message.description, "info message without arguments")
        XCTAssertEqual(testLogging.subsystem, "info subsystem")
        XCTAssertEqual(testLogging.category, "info category")
        XCTAssertEqual(testLogging.type, .info)
        XCTAssertEqual(testLogging.args.count, 0)
    }
    
    func testInfoWithArguments() {
        let diagnosticLog = DiagnosticLog(subsystem: "info subsystem", category: "info category")
        
        diagnosticLog.info("info message with arguments", "a", "b")
        
        XCTAssertEqual(testLogging.message.description, "info message with arguments")
        XCTAssertEqual(testLogging.subsystem, "info subsystem")
        XCTAssertEqual(testLogging.category, "info category")
        XCTAssertEqual(testLogging.type, .info)
        XCTAssertEqual(testLogging.args.count, 2)
    }
    
    func testDefaultWithoutArguments() {
        let diagnosticLog = DiagnosticLog(subsystem: "default subsystem", category: "default category")
        
        diagnosticLog.default("default message without arguments")
        
        XCTAssertEqual(testLogging.message.description, "default message without arguments")
        XCTAssertEqual(testLogging.subsystem, "default subsystem")
        XCTAssertEqual(testLogging.category, "default category")
        XCTAssertEqual(testLogging.type, .default)
        XCTAssertEqual(testLogging.args.count, 0)
    }
    
    func testDefaultWithArguments() {
        let diagnosticLog = DiagnosticLog(subsystem: "default subsystem", category: "default category")
        
        diagnosticLog.default("default message with arguments", "a", "b", "c")
        
        XCTAssertEqual(testLogging.message.description, "default message with arguments")
        XCTAssertEqual(testLogging.subsystem, "default subsystem")
        XCTAssertEqual(testLogging.category, "default category")
        XCTAssertEqual(testLogging.type, .default)
        XCTAssertEqual(testLogging.args.count, 3)
    }
    
    func testErrorWithoutArguments() {
        let diagnosticLog = DiagnosticLog(subsystem: "error subsystem", category: "error category")
        
        diagnosticLog.error("error message without arguments")
        
        XCTAssertEqual(testLogging.message.description, "error message without arguments")
        XCTAssertEqual(testLogging.subsystem, "error subsystem")
        XCTAssertEqual(testLogging.category, "error category")
        XCTAssertEqual(testLogging.type, .error)
        XCTAssertEqual(testLogging.args.count, 0)
    }
    
    func testErrorWithArguments() {
        let diagnosticLog = DiagnosticLog(subsystem: "error subsystem", category: "error category")
        
        diagnosticLog.error("error message with arguments", "a", "b", "c", "d")
        
        XCTAssertEqual(testLogging.message.description, "error message with arguments")
        XCTAssertEqual(testLogging.subsystem, "error subsystem")
        XCTAssertEqual(testLogging.category, "error category")
        XCTAssertEqual(testLogging.type, .error)
        XCTAssertEqual(testLogging.args.count, 4)
    }
    
}

fileprivate class TestLogging: Logging {

    var message: StaticString!
    
    var subsystem: String!
    
    var category: String!
    
    var type: OSLogType!
    
    var args: [CVarArg]!
    
    init() {}
    
    func log (_ message: StaticString, subsystem: String, category: String, type: OSLogType, _ args: [CVarArg]) {
        self.message = message
        self.subsystem = subsystem
        self.category = category
        self.type = type
        self.args = args
    }
}
