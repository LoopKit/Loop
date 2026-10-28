//
//  OutcomesPackage.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

struct OutcomesManifest: Codable, Equatable {
    struct App: Codable, Equatable {
        var version: String
        var build: String
        var workspaceBranch: String?
        var workspaceRevision: String?
        var loopRevision: String?
    }

    struct Setup: Codable, Equatable {
        var changeDate: Date
        var changeDateIsLowerBound: Bool
        var changes: [String]
    }

    struct Range: Codable, Equatable {
        var start: Date
        var end: Date
    }

    struct File: Codable, Equatable {
        var name: String
        var bytes: Int64
    }

    var format = 1
    var installID: String
    var app: App
    var setup: Setup
    var range: Range
    var days: Int
    var files: [File] = []
}

struct OutcomesPackage {
    let url: URL
    let manifest: OutcomesManifest
    let bytes: Int64
}

enum OutcomesPackageError: Error {
    case archiveFailure
    case unexpectedFormat(String)
}

struct OutcomesPackageBuilder {
    static let duration = TimeInterval.days(42)
    static let exportNames: Set<String> = ["Settings.json", "Glucose.json", "Carbs.json", "DosingDecisions.json", "Doses.json", "Overrides.json"]

    private static let sliceDuration = TimeInterval.hours(6)
    private static let inEffectAtStartNames: Set<String> = ["Settings.json", "Overrides.json"]
    private static let inEffectLookback = TimeInterval.days(90)

    let logs: [CriticalEventLog]
    var fileManager: FileManager = .default

    init(logs: [CriticalEventLog], fileManager: FileManager = .default) {
        self.logs = logs.filter { Self.exportNames.contains($0.exportName) }
        self.fileManager = fileManager
    }

    /// Writes the share for the setup since `change`, covering up to `duration` before `now`.
    func build(change: SetupChange, installID: String, now: Date, progress: Progress) throws -> OutcomesPackage {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = now.addingTimeInterval(-Self.duration)
        var dayStarts: [Date] = []
        var day = calendar.startOfDay(for: start)
        while day < now {
            dayStarts.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        progress.totalUnitCount = Int64(dayStarts.count * logs.count)

        let url = fileManager.temporaryDirectory.appendingPathComponent("Outcomes-\(UUID().uuidString).zip")
        guard let archive = ZipArchive(url: url) else {
            throw OutcomesPackageError.archiveFailure
        }
        var succeeded = false
        defer {
            archive.close()
            if !succeeded {
                try? fileManager.removeItem(at: url)
            }
        }

        let dayFormatter = ISO8601DateFormatter()
        dayFormatter.formatOptions = [.withFullDate]
        var files: [OutcomesManifest.File] = []
        // The settings and override in effect when the range starts
        for log in logs where Self.inEffectAtStartNames.contains(log.exportName) {
            let name = "start/\(log.exportName)"
            let bytes = try export(log, from: start.addingTimeInterval(-Self.inEffectLookback), to: start, lastOnly: true, into: archive.createArchiveFile(withPath: name), progress: progress)
            files.append(OutcomesManifest.File(name: name, bytes: bytes))
        }
        for dayStart in dayStarts {
            let dayEnd = min(calendar.date(byAdding: .day, value: 1, to: dayStart)!, now)
            for log in logs {
                guard !progress.isCancelled else {
                    throw CriticalEventLogError.cancelled
                }
                let name = "\(dayFormatter.string(from: dayStart))/\(log.exportName)"
                let bytes = try export(log, from: max(dayStart, start), to: dayEnd, into: archive.createArchiveFile(withPath: name), progress: progress)
                files.append(OutcomesManifest.File(name: name, bytes: bytes))
                progress.completedUnitCount += 1
            }
        }

        let manifest = OutcomesManifest(
            installID: installID,
            app: OutcomesManifest.App(
                version: Bundle.main.shortVersionString,
                build: Bundle.main.version,
                workspaceBranch: BuildDetails.default.workspaceGitBranch,
                workspaceRevision: BuildDetails.default.workspaceGitRevision,
                loopRevision: BuildDetails.default.gitRevision),
            setup: OutcomesManifest.Setup(changeDate: change.date, changeDateIsLowerBound: change.isLowerBound, changes: change.items.map(\.identifier)),
            range: OutcomesManifest.Range(start: start, end: now),
            days: dayStarts.count,
            files: files)

        let manifestStream = archive.createArchiveFile(withPath: "manifest.json")
        try manifestStream.write(try Self.manifestEncoder.encode(manifest))
        try manifestStream.finish(sync: true)
        if let error = archive.close() {
            throw error
        }
        succeeded = true
        let bytes = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return OutcomesPackage(url: url, manifest: manifest, bytes: bytes)
    }

    static func latest(_ objects: [Any]) -> Any? {
        func date(_ object: Any) -> String {
            let dictionary = object as? [String: Any]
            return dictionary?["date"] as? String ?? dictionary?["startDate"] as? String ?? ""
        }
        return objects.max { date($0) < date($1) }
    }

    static let manifestEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    // Exported in slices so a day of dosing decisions isn't parsed all at once
    private func export(_ log: CriticalEventLog, from start: Date, to end: Date, lastOnly: Bool = false, into stream: DataOutputStream, progress: Progress) throws -> Int64 {
        var written: Int64 = 0
        func write(_ data: Data) throws {
            try stream.write(data)
            written += Int64(data.count)
        }
        try write(Data("[".utf8))
        var first = true
        if lastOnly {
            let buffer = MemoryOutputStream()
            if let error = log.export(startDate: start, endDate: end, to: buffer, progress: Progress(totalUnitCount: 0)) {
                throw error
            }
            guard let objects = try JSONSerialization.jsonObject(with: buffer.data) as? [Any] else {
                throw OutcomesPackageError.unexpectedFormat(log.exportName)
            }
            if let last = Self.latest(objects).flatMap({ OutcomesScrubber.scrub($0, in: log.exportName) }) {
                try write(Data("\n".utf8))
                try write(try JSONSerialization.data(withJSONObject: last, options: [.sortedKeys]))
                first = false
            }
        }
        var sliceStart = lastOnly ? end : start
        while sliceStart < end {
            let sliceEnd = min(sliceStart.addingTimeInterval(Self.sliceDuration), end)
            try autoreleasepool {
                let buffer = MemoryOutputStream()
                if let error = log.export(startDate: sliceStart, endDate: sliceEnd, to: buffer, progress: Progress(totalUnitCount: 0)) {
                    throw error
                }
                guard let objects = try JSONSerialization.jsonObject(with: buffer.data) as? [Any] else {
                    throw OutcomesPackageError.unexpectedFormat(log.exportName)
                }
                for object in objects {
                    guard !progress.isCancelled else {
                        throw CriticalEventLogError.cancelled
                    }
                    guard let scrubbed = OutcomesScrubber.scrub(object, in: log.exportName) else {
                        continue
                    }
                    try write(Data((first ? "\n" : ",\n").utf8))
                    try write(try JSONSerialization.data(withJSONObject: scrubbed, options: [.sortedKeys]))
                    first = false
                }
            }
            sliceStart = sliceEnd
        }
        try write(Data((first ? "]" : "\n]").utf8))
        try stream.finish(sync: true)
        return written
    }
}

/// Removes what could identify the person or their devices, and records the share doesn't need.
enum OutcomesScrubber {
    static let removedKeys: Set<String> = [
        "deviceToken",         // push token for remote commands
        "raw",                 // pump event bytes
        "title",               // pump event descriptions
        "foodType",            // free text
        "historicalGlucose",   // repeats Glucose.json
        "localIdentifier",     // device serial numbers
        "udiDeviceIdentifier",
    ]

    /// Device names, such as "Pete's iPhone", are dropped from these.
    static let deviceKeys: Set<String> = ["device", "controllerDevice", "cgmDevice", "pumpDevice"]

    /// These decisions repeat the loop's own after each cycle, for remote displays.
    static let skippedDosingDecisionReasons: Set<String> = ["updateRemoteRecommendation"]

    static func scrub(_ object: Any, in exportName: String) -> Any? {
        // JSONStreamEncoder's placeholder for a record it couldn't encode quotes the record's description
        if let dictionary = object as? [String: Any], dictionary.keys.elementsEqual(["error"]) {
            return nil
        }
        if exportName == "DosingDecisions.json",
           let reason = ((object as? [String: Any])?["data"] as? [String: Any])?["reason"] as? String,
           skippedDosingDecisionReasons.contains(reason) {
            return nil
        }
        return scrub(object, isDevice: false)
    }

    private static func scrub(_ object: Any, isDevice: Bool) -> Any {
        switch object {
        case let dictionary as [String: Any]:
            var result: [String: Any] = [:]
            for (key, value) in dictionary where !removedKeys.contains(key) && !(isDevice && key == "name") {
                result[key] = scrub(value, isDevice: deviceKeys.contains(key))
            }
            return result
        case let array as [Any]:
            return array.map { scrub($0, isDevice: false) }
        default:
            return object
        }
    }
}

final class MemoryOutputStream: DataOutputStream {
    private(set) var data = Data()

    func write(_ data: Data) throws {
        self.data.append(data)
    }

    func finish(sync: Bool) throws {}

    var streamError: Error? { nil }
}

extension SetupChange.Item {
    /// Stable, unlocalized name for the shared manifest.
    var identifier: String {
        switch self {
        case .therapySetting(let setting):
            switch setting {
            case .glucoseTargetRange: return "glucoseTargetRange"
            case .preMealCorrectionRangeOverride: return "preMealCorrectionRange"
            case .suspendThreshold: return "glucoseSafetyLimit"
            case .basalRate: return "basalRate"
            case .deliveryLimits: return "deliveryLimits"
            case .carbRatio: return "carbRatio"
            case .insulinSensitivity: return "insulinSensitivity"
            case .none: return "none"
            }
        case .insulinType:
            return "insulinType"
        case .insulinModel:
            return "insulinModel"
        case .dosingStrategy:
            return "dosingStrategy"
        case .experiment(let experiment, let enabled):
            return "experiment.\(experiment.rawValue).\(enabled ? "on" : "off")"
        }
    }
}
