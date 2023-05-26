//
//  CriticalEventLogExportManagerTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 8/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import Foundation
import LoopKit
@testable import Loop

fileprivate let now = ISO8601DateFormatter().date(from: "2020-03-11T12:13:14-0700")!  // Explicitly chosen near DST change

class CriticalEventLogExportManagerTests: XCTestCase {
    var fileManager: FileManager!
    var logs: [MockCriticalEventLog]!
    var directory: URL!
    var historicalDuration: TimeInterval!
    var manager: CriticalEventLogExportManager!
    var delegate: MockCriticalEventLogExporterDelegate!
    var url: URL!

    override func setUp() {
        super.setUp()

        fileManager = FileManager.default
        logs = [MockCriticalEventLog(name: "One", progressUnitCount: 1),
                MockCriticalEventLog(name: "Two", progressUnitCount: 2),
                MockCriticalEventLog(name: "Three", progressUnitCount: 3)]
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        historicalDuration = .days(5)
        manager = CriticalEventLogExportManager(logs: logs, directory: directory, historicalDuration: historicalDuration, fileManager: fileManager)
        delegate = MockCriticalEventLogExporterDelegate()
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? fileManager.removeItem(atPath: url.path)
        try? fileManager.removeItem(atPath: directory.path)

        url = nil
        delegate = nil
        manager = nil
        historicalDuration = nil
        directory = nil
        logs = nil
        fileManager = nil

        super.tearDown()
    }

    func testNextExportHistoricalDateWhenUpToDate() {
        XCTAssertNoThrow(try fileManager.createDirectory(at: directory, withIntermediateDirectories: true))
        XCTAssertTrue(fileManager.createFile(atPath: directory.appendingPathComponent("20200310T000000Z.zip").path, contents: nil))

        XCTAssertEqual(manager.nextExportHistoricalDate(now: now), ISO8601DateFormatter().date(from: "2020-03-12T00:00:00Z"))
    }

    func testNextExportHistoricalDateWhenNotUpToDate() {
        XCTAssertNoThrow(try fileManager.createDirectory(at: directory, withIntermediateDirectories: true))
        XCTAssertTrue(fileManager.createFile(atPath: directory.appendingPathComponent("20200309T000000Z.zip").path, contents: nil))

        XCTAssertEqual(manager.nextExportHistoricalDate(now: now), ISO8601DateFormatter().date(from: "2020-03-11T19:13:14Z"))
    }

    func testRetryExportHistoricalDate() {
        XCTAssertEqual(manager.retryExportHistoricalDate(now: now), ISO8601DateFormatter().date(from: "2020-03-11T20:13:14Z"))
    }

    func testExport() {
        let completionExpectation = expectation(description: "Export completion")

        logs.forEach { $0.exportExpectation = self.expectation(description: $0.name, expectedFulfillmentCount: 5) }

        var exporter = manager.createExporter(to: url)
        exporter.delegate = delegate

        exporter.export(now: now) { error in
            XCTAssertNil(error)
            XCTAssertFalse(exporter.isCancelled)
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.url.path))
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200306T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200307T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200308T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200309T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200310T000000Z.zip").path))
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200311T000000Z.zip").path))
            XCTAssertEqual(exporter.progress.fractionCompleted, 1.0)
            XCTAssertTrue(exporter.progress.isFinished)
            XCTAssertEqual(self.delegate.progress!, 1.0)

            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation] + logs.map { $0.exportExpectation! }, timeout: 10)
    }

    func testExportPartial() {
        let completionExpectation = expectation(description: "Export completion")

        logs.forEach { $0.exportExpectation = self.expectation(description: $0.name, expectedFulfillmentCount: 3) }

        XCTAssertNoThrow(try fileManager.createDirectory(at: directory, withIntermediateDirectories: true))
        XCTAssertTrue(fileManager.createFile(atPath: directory.appendingPathComponent("20200307T000000Z.zip").path, contents: nil))
        XCTAssertTrue(fileManager.createFile(atPath: directory.appendingPathComponent("20200308T000000Z.zip").path, contents: nil))

        var exporter = manager.createExporter(to: url)
        exporter.delegate = delegate

        exporter.export(now: now) { error in
            XCTAssertNil(error)
            XCTAssertFalse(exporter.isCancelled)
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.url.path))
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200306T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200309T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200310T000000Z.zip").path))
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200311T000000Z.zip").path))
            XCTAssertEqual(exporter.progress.fractionCompleted, 1.0)
            XCTAssertTrue(exporter.progress.isFinished)
            XCTAssertEqual(self.delegate.progress!, 1.0)

            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation] + logs.map { $0.exportExpectation! }, timeout: 10)
    }

    func testExportCancelled() {
        let completionExpectation = expectation(description: "Export completion")

        let exporter = manager.createExporter(to: url)
        exporter.cancel()

        exporter.export(now: now) { error in
            XCTAssertEqual(error as? CriticalEventLogError, CriticalEventLogError.cancelled)
            XCTAssertTrue(exporter.isCancelled)
            XCTAssertFalse(self.fileManager.fileExists(atPath: self.url.path))

            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 10)
    }

    func testExportHistorical() {
        let completionExpectation = expectation(description: "Export completion")

        logs.forEach { $0.exportExpectation = self.expectation(description: $0.name, expectedFulfillmentCount: 4) }

        var exporter = manager.createHistoricalExporter()
        exporter.delegate = delegate

        exporter.export(now: now) { error in
            XCTAssertNil(error)
            XCTAssertFalse(exporter.isCancelled)
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200306T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200307T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200308T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200309T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200310T000000Z.zip").path))
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200311T000000Z.zip").path))
            XCTAssertEqual(exporter.progress.fractionCompleted, 1.0)
            XCTAssertTrue(exporter.progress.isFinished)
            XCTAssertEqual(self.delegate.progress!, 1.0)

            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation] + logs.map { $0.exportExpectation! }, timeout: 10)
    }

    func testExportHistoricalPartial() {
        let completionExpectation = expectation(description: "Export completion")

        logs.forEach { $0.exportExpectation = self.expectation(description: $0.name, expectedFulfillmentCount: 2) }

        XCTAssertNoThrow(try fileManager.createDirectory(at: directory, withIntermediateDirectories: true))
        XCTAssertTrue(fileManager.createFile(atPath: directory.appendingPathComponent("20200307T000000Z.zip").path, contents: nil))
        XCTAssertTrue(fileManager.createFile(atPath: directory.appendingPathComponent("20200308T000000Z.zip").path, contents: nil))

        var exporter = manager.createHistoricalExporter()
        exporter.delegate = delegate

        exporter.export(now: now) { error in
            XCTAssertNil(error)
            XCTAssertFalse(exporter.isCancelled)
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200306T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200309T000000Z.zip").path))
            XCTAssertTrue(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200310T000000Z.zip").path))
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200311T000000Z.zip").path))
            XCTAssertEqual(exporter.progress.fractionCompleted, 1.0)
            XCTAssertTrue(exporter.progress.isFinished)
            XCTAssertEqual(self.delegate.progress!, 1.0)

            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation] + logs.map { $0.exportExpectation! }, timeout: 10)
    }

    func testExportHistoricalPurge() {
        let completionExpectation = expectation(description: "Export completion")

        XCTAssertNoThrow(try fileManager.createDirectory(at: directory, withIntermediateDirectories: true))
        XCTAssertTrue(fileManager.createFile(atPath: directory.appendingPathComponent("20200305T000000Z.zip").path, contents: nil))
        XCTAssertTrue(fileManager.createFile(atPath: directory.appendingPathComponent("20200306T000000Z.zip").path, contents: nil))

        var exporter = manager.createHistoricalExporter()
        exporter.delegate = delegate

        exporter.export(now: now) { error in
            XCTAssertNil(error)
            XCTAssertFalse(exporter.isCancelled)
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200305T000000Z.zip").path))
            XCTAssertFalse(self.fileManager.isReadableFile(atPath: self.directory.appendingPathComponent("20200306T000000Z.zip").path))
            XCTAssertEqual(self.delegate.progress!, 1.0)

            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 10)
    }

    func testExportHistoricalCancelled() {
        let completionExpectation = expectation(description: "Export completion")

        let exporter = manager.createHistoricalExporter()
        exporter.cancel()

        exporter.export(now: now) { error in
            XCTAssertEqual(error as? CriticalEventLogError, CriticalEventLogError.cancelled)
            XCTAssertTrue(exporter.isCancelled)

            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 10)
    }
}

class MockCriticalEventLog: CriticalEventLog {
    var name: String
    var progressUnitCount: Int64
    var error: Error?
    var exportProgressTotalUnitCountExpectation: XCTestExpectation?
    var exportExpectation: XCTestExpectation?

    init(name: String, progressUnitCount: Int64) {
        self.name = name
        self.progressUnitCount = progressUnitCount
    }

    var exportName: String { name }

    func exportProgressTotalUnitCount(startDate: Date, endDate: Date?) -> Result<Int64, Error> {
        exportProgressTotalUnitCountExpectation?.fulfill()

        if let error = error {
            return .failure(error)
        }

        let days = (endDate ?? now).timeIntervalSince(startDate).days.rounded(.down)
        return .success(Int64(days) * progressUnitCount)
    }

    func export(startDate: Date, endDate: Date, to stream: DataOutputStream, progress: Progress) -> Error? {
        exportExpectation?.fulfill()

        guard !progress.isCancelled else {
            return CriticalEventLogError.cancelled
        }

        if let error = error {
            return error
        }

        do {
            try stream.write(name)
        } catch let error {
            return error
        }

        progress.completedUnitCount += progressUnitCount
        return nil
    }
}

class MockCriticalEventLogExporterDelegate: CriticalEventLogExporterDelegate {
    var progress: Double?

    func exportDidProgress(_ progress: Double) {
        self.progress = progress
    }
}

fileprivate struct MockError: Error, Equatable {}

fileprivate extension XCTestCase {
    func expectation(description: String, expectedFulfillmentCount: Int) -> XCTestExpectation {
        let expectation = self.expectation(description: description)
        expectation.expectedFulfillmentCount = expectedFulfillmentCount
        return expectation
    }
}
