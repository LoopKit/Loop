//
//  ZipArchiveTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 9/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import Loop
import LoopKit
import ZIPFoundation


class ZipArchiveTests: XCTestCase {
    var url: URL!
    var archive: ZipArchive!
    var outputStream: DataOutputStream?

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        archive = ZipArchive(url: url)
    }

    override func tearDown() {
        try? outputStream?.finish(sync: true)
        archive.close()
        try? FileManager.default.removeItem(at: url)
    }

    func testClose() {
        XCTAssertNil(archive.close())
    }

    func testCloseMultiple() {
        XCTAssertNil(archive.close())
        XCTAssertNil(archive.close())
    }

    func testCreateWriteCloseArchiveFile() {
        outputStream = archive.createArchiveFile(withPath: "testCreateWriteCloseArchiveFile")
        XCTAssertNotNil(outputStream)
        XCTAssertNil(outputStream?.streamError)
        XCTAssertNoThrow(try outputStream?.write("testCreateWriteCloseArchiveFile"))
        XCTAssertNoThrow(try outputStream?.finish(sync: true))
        XCTAssertNil(archive.close())
    }

    func testCreateWriteArchiveFileAfterClose() {
        outputStream = archive.createArchiveFile(withPath: "testCreateWriteArchiveFileAfterClose")
        XCTAssertNotNil(outputStream)
        XCTAssertNoThrow(try outputStream?.finish(sync: true))
        XCTAssertThrowsError(try outputStream?.write("testCreateWriteArchiveFileAfterClose"))
    }

    func testCreateArchiveFileWithContents() {
        let contentsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNoThrow(try "testCreateArchiveFileWithContents".data(using: .utf8)!.write(to: contentsURL))
        XCTAssertNil(archive.createArchiveFile(withPath: "testCreateArchiveFileWithContents", contentsOf: contentsURL))
        XCTAssertNil(archive.close())

        let archive = Archive(url: url, accessMode: .read)
        XCTAssertNotNil(archive)

        let entry = archive!["testCreateArchiveFileWithContents"]
        XCTAssertNotNil(entry)

        XCTAssertEqual(entry!.type, .file)
        XCTAssertEqual(entry!.path, "testCreateArchiveFileWithContents")

        var extractedData = Data()

        let _ = try? archive!.extract(entry!, consumer: { (data) in
            extractedData.append(data)
        })

        XCTAssertEqual(String(data: extractedData, encoding: .utf8), "testCreateArchiveFileWithContents")
    }

    func testCreateArchiveFileWithMultipleFiles() {
        let contentsURL1 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNoThrow(try "testCreateArchiveFileWithContents1".data(using: .utf8)!.write(to: contentsURL1))
        let contentsURL2 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNoThrow(try "testCreateArchiveFileWithContents2".data(using: .utf8)!.write(to: contentsURL2))

        XCTAssertNil(archive.createArchiveFile(withPath: "testCreateArchiveFileWithContents1", contentsOf: contentsURL1))
        XCTAssertNil(archive.createArchiveFile(withPath: "testCreateArchiveFileWithContents2", contentsOf: contentsURL2))
        XCTAssertNil(archive.close())

        let archive = Archive(url: url, accessMode: .read)
        XCTAssertNotNil(archive)

        let entry1 = archive!["testCreateArchiveFileWithContents1"]
        XCTAssertNotNil(entry1)
        XCTAssertEqual(entry1!.type, .file)
        XCTAssertEqual(entry1!.path, "testCreateArchiveFileWithContents1")
        var extractedData1 = Data()
        let _ = try? archive!.extract(entry1!, consumer: { (data) in
            extractedData1.append(data)
        })
        XCTAssertEqual(String(data: extractedData1, encoding: .utf8), "testCreateArchiveFileWithContents1")

        let entry2 = archive!["testCreateArchiveFileWithContents2"]
        XCTAssertNotNil(entry2)
        XCTAssertEqual(entry2!.type, .file)
        XCTAssertEqual(entry2!.path, "testCreateArchiveFileWithContents2")
        var extractedData2 = Data()
        let _ = try? archive!.extract(entry2!, consumer: { (data) in
            extractedData2.append(data)
        })
        XCTAssertEqual(String(data: extractedData2, encoding: .utf8), "testCreateArchiveFileWithContents2")
    }

}

fileprivate extension OutputStream {
    func write(_ string: String) throws {
        if let streamError = streamError {
            throw streamError
        }
        let bytes = [UInt8](string.utf8)
        write(bytes, maxLength: bytes.count)
        if let streamError = streamError {
            throw streamError
        }
    }
}
