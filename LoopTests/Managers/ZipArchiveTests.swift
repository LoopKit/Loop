//
//  ZipArchiveTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 9/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import Loop

class ZipArchiveTests: XCTestCase {
    var url: URL!
    var archive: ZipArchive!
    var outputStream: OutputStream?

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        archive = ZipArchive(url: url)
    }

    override func tearDown() {
        if outputStream?.streamStatus == .open {
           outputStream?.close()
        }
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
        XCTAssertEqual(outputStream?.streamStatus, .notOpen)
        XCTAssertNil(outputStream?.streamError)
        outputStream?.open()
        XCTAssertEqual(outputStream?.streamStatus, .open)
        XCTAssertEqual(outputStream?.hasSpaceAvailable, true)
        XCTAssertNoThrow(try outputStream?.write("testCreateWriteCloseArchiveFile"))
        outputStream?.close()
        XCTAssertEqual(outputStream?.streamStatus, .closed)
        XCTAssertNil(archive.close())
    }

    func testCreateWriteArchiveFileWithoutOpen() {
        outputStream = archive.createArchiveFile(withPath: "testCreateWriteArchiveFileWithoutOpen")
        XCTAssertNotNil(outputStream)
        XCTAssertThrowsError(try outputStream?.write("testCreateWriteArchiveFileWithoutOpen"))
        XCTAssertEqual(outputStream?.streamStatus, .error)
        XCTAssertEqual(outputStream?.streamError as? ZipArchiveError, ZipArchiveError.unexpectedStatus(.notOpen))
        XCTAssertEqual(archive.close() as? ZipArchiveError, ZipArchiveError.unexpectedStatus(.notOpen))
    }

    func testCreateWriteArchiveFileAfterClose() {
        outputStream = archive.createArchiveFile(withPath: "testCreateWriteArchiveFileAfterClose")
        XCTAssertNotNil(outputStream)
        outputStream?.open()
        outputStream?.close()
        XCTAssertThrowsError(try outputStream?.write("testCreateWriteArchiveFileAfterClose"))
        XCTAssertEqual(outputStream?.streamStatus, .error)
        XCTAssertEqual(outputStream?.streamError as? ZipArchiveError, ZipArchiveError.unexpectedStatus(.closed))
        XCTAssertEqual(archive.close() as? ZipArchiveError, ZipArchiveError.unexpectedStatus(.closed))
    }

    func testCreateWriteCloseArchiveFileWithCompressionNone() {
        outputStream = archive.createArchiveFile(withPath: "testCreateWriteCloseArchiveFileWithCompressionNone", compression: .bestSpeed)
        XCTAssertNotNil(outputStream)
        outputStream?.open()
        XCTAssertNoThrow(try outputStream?.write("testCreateWriteCloseArchiveFileWithCompressionNone"))
        outputStream?.close()
        XCTAssertNil(archive.close())
    }

    func testCreateWriteCloseArchiveFileWithCompressionBestSpeed() {
        outputStream = archive.createArchiveFile(withPath: "testCreateWriteCloseArchiveFileWithCompressionBestSpeed", compression: .bestSpeed)
        XCTAssertNotNil(outputStream)
        outputStream?.open()
        XCTAssertNoThrow(try outputStream?.write("testCreateWriteCloseArchiveFileWithCompressionBestSpeed"))
        outputStream?.close()
        XCTAssertNil(archive.close())
    }

    func testCreateWriteCloseArchiveFileWithCompressionBestCompression() {
        outputStream = archive.createArchiveFile(withPath: "testCreateWriteCloseArchiveFileWithCompressionBestCompression", compression: .bestCompression)
        XCTAssertNotNil(outputStream)
        outputStream?.open()
        XCTAssertNoThrow(try outputStream?.write("testCreateWriteCloseArchiveFileWithCompressionBestCompression"))
        outputStream?.close()
        XCTAssertNil(archive.close())
    }

    func testCreateArchiveFileWithContents() {
        let contentsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNoThrow(try "testCreateArchiveFileWithContents".data(using: .utf8)!.write(to: contentsURL))
        XCTAssertNil(archive.createArchiveFile(withPath: "testCreateArchiveFileWithContents", contentsOf: contentsURL))
        XCTAssertNil(archive.close())
    }

    func testCreateArchiveFileWithContentsCompressionNone() {
        let contentsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNoThrow(try "testCreateArchiveFileWithContentsCompressionNone".data(using: .utf8)!.write(to: contentsURL))
        XCTAssertNil(archive.createArchiveFile(withPath: "testCreateArchiveFileWithContentsCompressionNone", contentsOf: contentsURL, compression: .none))
        XCTAssertNil(archive.close())
    }

    func testCreateArchiveFileWithContentsCompressionBestSpeed() {
        let contentsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNoThrow(try "testCreateArchiveFileWithContentsCompressionBestSpeed".data(using: .utf8)!.write(to: contentsURL))
        XCTAssertNil(archive.createArchiveFile(withPath: "testCreateArchiveFileWithContentsCompressionBestSpeed", contentsOf: contentsURL, compression: .bestSpeed))
        XCTAssertNil(archive.close())
    }

    func testCreateArchiveFileWithContentsCompressionBestCompression() {
        let contentsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNoThrow(try "testCreateArchiveFileWithContents".data(using: .utf8)!.write(to: contentsURL))
        XCTAssertNil(archive.createArchiveFile(withPath: "testCreateArchiveFileWithContents", contentsOf: contentsURL, compression: .bestCompression))
        XCTAssertNil(archive.close())
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
