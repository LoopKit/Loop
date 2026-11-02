//
//  OutcomesPackageTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import ZIPFoundation
@testable import Loop

class OutcomesScrubberTests: XCTestCase {
    func testRemovesIdentifyingFields() throws {
        let settings: [String: Any] = [
            "date": "2026-10-01T00:00:00.000Z",
            "data": [
                "deviceToken": "abc",
                "controllerDevice": ["name": "Pete's iPhone", "model": "iPhone", "systemVersion": "26.1"],
                "pumpDevice": ["name": "Omnipod", "manufacturer": "Insulet", "localIdentifier": "1F0A", "udiDeviceIdentifier": "0123"],
                "overridePresets": [["name": "Running", "symbol": "🏃"]],
            ] as [String: Any],
        ]
        let scrubbed = try XCTUnwrap(OutcomesScrubber.scrub(settings, in: "Settings.json") as? [String: Any])
        let data = try XCTUnwrap(scrubbed["data"] as? [String: Any])
        XCTAssertNil(data["deviceToken"])
        XCTAssertEqual(data["controllerDevice"] as? [String: String], ["model": "iPhone", "systemVersion": "26.1"])
        XCTAssertEqual(data["pumpDevice"] as? [String: String], ["manufacturer": "Insulet"])
        XCTAssertEqual(data["overridePresets"] as? [[String: String]], [["name": "Running", "symbol": "🏃"]])
        XCTAssertEqual(scrubbed["date"] as? String, "2026-10-01T00:00:00.000Z")
    }

    func testRemovesPumpEventDetailsAndFoodTypes() throws {
        let dose: [String: Any] = ["raw": "AQID", "title": "BolusPumpEvent(...)", "type": "bolus"]
        XCTAssertEqual(OutcomesScrubber.scrub(dose, in: "Doses.json") as? [String: String], ["type": "bolus"])
        let carb: [String: Any] = ["foodType": "Pizza at Joe's", "grams": 40]
        XCTAssertEqual((OutcomesScrubber.scrub(carb, in: "Carbs.json") as? [String: Any])?.keys.sorted(), ["grams"])
    }

    func testDosingDecisions() throws {
        let remote: [String: Any] = ["data": ["reason": "updateRemoteRecommendation"]]
        XCTAssertNil(OutcomesScrubber.scrub(remote, in: "DosingDecisions.json"))

        let loop: [String: Any] = ["data": [
            "reason": "loop",
            "historicalGlucose": [["quantity": 100]],
            "pumpManagerStatus": ["device": ["name": "Omnipod", "localIdentifier": "1F0A", "model": "Dash"]],
        ] as [String: Any]]
        let data = try XCTUnwrap((OutcomesScrubber.scrub(loop, in: "DosingDecisions.json") as? [String: Any])?["data"] as? [String: Any])
        XCTAssertNil(data["historicalGlucose"])
        XCTAssertEqual((data["pumpManagerStatus"] as? [String: Any])?["device"] as? [String: String], ["model": "Dash"])
    }

    func testSkipsEncoderErrorPlaceholders() {
        XCTAssertNil(OutcomesScrubber.scrub(["error": "Failed to encode value: Pete's iPhone"], in: "Settings.json"))
    }
}

class OutcomesPackageBuilderTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-28T12:00:00Z")!

    private func record(_ date: Date, _ extra: [String: Any] = [:]) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return extra.merging(["date": formatter.string(from: date)]) { a, _ in a }
    }

    func testBuild() throws {
        let start = now.addingTimeInterval(-OutcomesPackageBuilder.duration)
        let settings = FakeLog(exportName: "Settings.json", records: [
            (start - .days(30), record(start - .days(30), ["value": "old"])),
            (start - .days(2), record(start - .days(2), ["value": "inEffect", "deviceToken": "abc"])),
            (now - .days(3), record(now - .days(3), ["value": "recent"])),
        ])
        let glucose = FakeLog(exportName: "Glucose.json", records: [
            (start - .hours(1), record(start - .hours(1))),
            (now - .hours(1), record(now - .hours(1), ["quantity": 120])),
        ])
        let deviceLog = FakeLog(exportName: "DeviceLog.json", records: [(now - .hours(1), record(now - .hours(1)))])
        let builder = OutcomesPackageBuilder(logs: [settings, glucose, deviceLog])
        let change = SetupChange(date: now - .days(15), isLowerBound: false, items: [.therapySetting(.carbRatio), .experiment(.guardAndRunway, enabled: true)])

        let package = try builder.build(change: change, installID: "install", now: now, progress: Progress())
        defer { try? FileManager.default.removeItem(at: package.url) }

        let archive = try XCTUnwrap(Archive(url: package.url, accessMode: .read))
        func json(_ path: String) throws -> [[String: Any]] {
            var data = Data()
            _ = try archive.extract(try XCTUnwrap(archive[path], path)) { data.append($0) }
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        }

        // 42 days that don't start at midnight touch 43 UTC days
        XCTAssertEqual(package.manifest.days, 43)
        XCTAssertNil(archive.first { $0.path.contains("DeviceLog") })
        XCTAssertEqual(Array(archive).count, 1 + 43 * 2 + 1)

        let inEffect = try json("start/Settings.json")
        XCTAssertEqual(inEffect.map { $0["value"] as? String }, ["inEffect"])
        XCTAssertNil(inEffect.first?["deviceToken"])
        XCTAssertEqual(try json("2026-10-25/Settings.json").map { $0["value"] as? String }, ["recent"])
        XCTAssertEqual(try json("2026-10-28/Glucose.json").map { $0["quantity"] as? Int }, [120])
        XCTAssertEqual(try json("2026-09-16/Glucose.json").count, 0)

        var manifestData = Data()
        _ = try archive.extract(try XCTUnwrap(archive["manifest.json"])) { manifestData.append($0) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(OutcomesManifest.self, from: manifestData)
        XCTAssertEqual(manifest, package.manifest)
        XCTAssertEqual(manifest.installID, "install")
        XCTAssertEqual(manifest.setup.changes, ["carbRatio", "experiment.guardAndRunway.on"])
        XCTAssertEqual(manifest.range.start, start)
        XCTAssertEqual(manifest.files.count, 1 + 43 * 2)
    }

    func testBuildCancelled() {
        let builder = OutcomesPackageBuilder(logs: [FakeLog(exportName: "Glucose.json", records: [])])
        let progress = Progress()
        progress.cancel()
        let change = SetupChange(date: now - .days(15), isLowerBound: true, items: [])
        XCTAssertThrowsError(try builder.build(change: change, installID: "install", now: now, progress: progress)) { error in
            XCTAssertEqual(error as? CriticalEventLogError, .cancelled)
        }
    }
}

private struct FakeLog: CriticalEventLog {
    let exportName: String
    let records: [(Date, [String: Any])]

    func exportProgressTotalUnitCount(startDate: Date, endDate: Date?) -> Result<Int64, Error> {
        .success(Int64(records.count))
    }

    func export(startDate: Date, endDate: Date, to stream: DataOutputStream, progress: Progress) -> Error? {
        let objects = records.filter { $0.0 >= startDate && $0.0 < endDate }.map(\.1)
        do {
            try stream.write(try JSONSerialization.data(withJSONObject: objects))
            return nil
        } catch {
            return error
        }
    }
}
