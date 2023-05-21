//
//  CriticalEventLogExportManager.swift
//  Loop
//
//  Created by Darin Krauss on 7/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import os.log
import UIKit
import LoopKit

public enum CriticalEventLogExportError: Error {
    case exportInProgress
    case archiveFailure
}

public protocol CriticalEventLogExporter {

    /// The delegate for the exporter to send progress updates.
    var delegate: CriticalEventLogExporterDelegate? { get set }

    /// The export progress.
    var progress: Progress { get }

    /// Export
    /// - Parameter now: The current time.
    /// - Parameter completion: Competion handler returning any error.
    func export(now: Date, completion: @escaping (Error?) -> Void)
}

public extension CriticalEventLogExporter {

    /// Has the export been cancelled?
    var isCancelled: Bool { progress.isCancelled }

    /// Cancel the export progress.
    func cancel() { progress.cancel() }

    /// Export using the current date.
    /// - Parameter completion: Competion handler returning any error.
    func export(completion: @escaping (Error?) -> Void) { export(now: Date(), completion: completion) }
}

public protocol CriticalEventLogExporterDelegate: AnyObject {

    /// Some progress was made towards the export.
    /// - Parameter progress: The current percent progress made (0.0 to 1.0) to complete the export.
    func exportDidProgress(_ progress: Double)
}

// MARK: - CriticalEventLogExportManager

fileprivate protocol CriticalEventLogSynchronizedExporter: CriticalEventLogExporter {
    func exportSynchronized(now: Date) -> Error?
}

public class CriticalEventLogExportManager {
    public let logs: [CriticalEventLog]
    public let directory: URL
    public let historicalDuration: TimeInterval
    public let fileManager: FileManager

    private var synchronizeSemaphore = DispatchSemaphore(value: 1)
    private let lockedActiveExporter = Locked<CriticalEventLogSynchronizedExporter?>(nil)

    private let log = OSLog(category: "CriticalEventLogExportManager")

    public init(logs: [CriticalEventLog], directory: URL, historicalDuration: TimeInterval, fileManager: FileManager = FileManager.default) {
        self.logs = logs
        self.directory = directory
        self.historicalDuration = historicalDuration
        self.fileManager = fileManager
    }

    public func nextExportHistoricalDate(now: Date = Date()) -> Date {
        switch latestExportDate() {
        case .failure(let error):
            log.error("Failure determining next export historical date: %{public}@", String(describing: error))
        case .success(let latestExportDate):
            if latestExportDate >= recentDate(from: now) {
                return exportDate(for: date(byAddingDays: 1, to: now))
            }
        }
        return now
    }

    private let retryExportHistoricalDuration: TimeInterval = .hours(1)

    public func retryExportHistoricalDate(now: Date = Date()) -> Date {
        return now.addingTimeInterval(retryExportHistoricalDuration)
    }

    // MARK: - Exporter

    public func createExporter(to url: URL) -> CriticalEventLogExporter {
        return CriticalEventLogFullExporter(manager: self, to: url)
    }

    public func createHistoricalExporter() -> CriticalEventLogExporter {
        return CriticalEventLogHistoricalExporter(manager: self)
    }

    // MARK: - Export synchronization

    private let synchronizeExportExpireDuration: TimeInterval = .seconds(5)
    private let synchronizeExportCancelDuration: TimeInterval = .seconds(0.1)

    fileprivate func synchronizeExport(for exporter: CriticalEventLogSynchronizedExporter, cancellingActive: Bool, now: Date) -> Error? {
        guard !exporter.isCancelled else {
            return CriticalEventLogError.cancelled
        }

        if cancellingActive {
            if let activeExporter = lockedActiveExporter.value {
                activeExporter.cancel()
            }

            let expireDate = Date(timeIntervalSinceNow: synchronizeExportExpireDuration)
            while !obtainSynchronizeSemaphore(waiting: synchronizeExportCancelDuration) {
                if exporter.isCancelled {
                    return CriticalEventLogError.cancelled
                }
                if Date() > expireDate {
                    log.error("Failure to cancel active exporter before expiration")
                    return CriticalEventLogExportError.exportInProgress
                }
            }
        } else {
            if !obtainSynchronizeSemaphore() {
                return CriticalEventLogExportError.exportInProgress
            }
        }
        defer { synchronizeSemaphore.signal() }

        assert(lockedActiveExporter.value == nil)
        lockedActiveExporter.value = exporter
        defer { lockedActiveExporter.value = nil }

        return exporter.exportSynchronized(now: now)
    }

    private func obtainSynchronizeSemaphore(waiting timeInterval: TimeInterval = 0) -> Bool {
        switch synchronizeSemaphore.wait(timeout: .now() + timeInterval) {
        case .timedOut:
            return false
        case .success:
            return true
        }
    }

    // MARK: - Utilities

    fileprivate func latestExportDate() -> Result<Date, Error> {
        var exportDate: Date = .distantPast

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            for fileURL in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                if fileURL.pathExtension == archiveExtension, let fileDate = date(from: fileURL.deletingPathExtension().lastPathComponent) {
                    if fileDate > exportDate {
                        exportDate = fileDate
                    }
                }
            }
            return .success(exportDate)
        } catch let error {
            return .failure(error)
        }
    }

    var archiveExtension: String { "zip" }

    func recentDate(from now: Date) -> Date { exportDate(for: date(byAddingDays: -1, to: now)) }

    func exportDate(for date: Date) -> Date { calendar.startOfDay(for: date) }

    func date(byAddingDays days: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date)! }

    func date(from timestamp: String) -> Date? { timestampFormatter.date(from: timestamp) }

    func timestamp(from date: Date) -> String { timestampFormatter.string(from: date) }

    fileprivate var timestampFormatter: ISO8601DateFormatter { Self.timestampFormatter }

    fileprivate var calendar: Calendar { Self.calendar }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.timeZone = calendar.timeZone
        timestampFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        return timestampFormatter
    }()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

// MARK: - CriticalEventLogBaseExporter

public class CriticalEventLogBaseExporter {
    public weak var delegate: CriticalEventLogExporterDelegate?

    public let progress: Progress

    fileprivate let manager: CriticalEventLogExportManager

    fileprivate init(manager: CriticalEventLogExportManager) {
        self.progress = Progress.discreteProgress(totalUnitCount: 0)
        self.manager = manager
    }

    fileprivate func exportSynchronized(now: Date) -> Error? {
        guard !progress.isCancelled else {
            return CriticalEventLogError.cancelled
        }

        switch exportProgressTotalUnitCount(now: now) {
        case .failure(let error):
            return error
        case .success(let progressTotalUnitCount):
            progress.totalUnitCount = progressTotalUnitCount
            return nil
        }
    }

    fileprivate func exportProgressTotalUnitCount(now: Date) -> Result<Int64, Error> {
        return exportProgressTotalUnitCount(through: nil, now: now)
    }

    fileprivate func exportProgressTotalUnitCount(through endDate: Date?, now: Date) -> Result<Int64, Error> {
        switch manager.latestExportDate() {
        case .failure(let error):
            return .failure(error)
        case .success(let latestExportDate):
            let startDate = max(historicalDate(from: now), latestExportDate)
            var progressTotalUnitCount: Int64 = 0
            for log in manager.logs {
                switch log.exportProgressTotalUnitCount(startDate: startDate, endDate: endDate) {
                case .failure(let error):
                    return .failure(error)
                case .success(let logProgressTotalUnitCount):
                    progressTotalUnitCount += logProgressTotalUnitCount
                }
            }
            return .success(progressTotalUnitCount)
        }
    }

    fileprivate func export(startDate: Date, endDate: Date, to url: URL, progress: Progress) -> Error? {
        guard !progress.isCancelled else {
            return CriticalEventLogError.cancelled
        }

        guard let archive = ZipArchive(url: url) else {
            return CriticalEventLogExportError.archiveFailure
        }
        defer { archive.close() }

        for log in manager.logs {
            if let error = export(startDate: startDate, endDate: endDate, from: log, to: archive, progress: progress) {
                return error
            }
        }

        return archive.close()
    }

    private func export(startDate: Date, endDate: Date, from log: CriticalEventLog, to archive: ZipArchive, progress: Progress) -> Error? {
        guard !progress.isCancelled else {
            return CriticalEventLogError.cancelled
        }

        let stream = archive.createArchiveFile(withPath: log.exportName)

        if let error = log.export(startDate: startDate, endDate: endDate, to: stream, progress: progress) {
            return error
        }

        do {
            try stream.finish(sync: true)
        } catch {
            return error
        }

        return nil
    }

    fileprivate func historicalDate(from now: Date) -> Date { manager.exportDate(for: manager.date(byAddingDays: -Int(manager.historicalDuration.days), to: now)) }

    fileprivate func exportsFileURL(for date: Date) -> URL { manager.directory.appendingPathComponent(exportsFileName(for: date)).appendingPathExtension(manager.archiveExtension) }

    fileprivate func exportsFileName(for date: Date) -> String { manager.timestamp(from: date) }
}

// MARK: - CriticalEventLogHistoricalExporter

public class CriticalEventLogHistoricalExporter: CriticalEventLogBaseExporter, CriticalEventLogSynchronizedExporter {
    private let log = OSLog(category: "CriticalEventLogHistoricalExporter")

    public func export(now: Date, completion: @escaping (Error?) -> Void) {
        completion(manager.synchronizeExport(for: self, cancellingActive: false, now: now))
    }

    fileprivate override func exportSynchronized(now: Date) -> Error? {
        if let error = super.exportSynchronized(now: now) {
            return error
        }

        let observation = progress.observe(\.fractionCompleted, options: []) { [weak self] object, _ in
            self?.delegate?.exportDidProgress(object.fractionCompleted)
        }
        defer { observation.invalidate() }

        return exportSynchronized(progress: progress, now: now)
    }

    fileprivate func exportSynchronized(progress: Progress, now: Date) -> Error? {
        guard !isCancelled else {
            return CriticalEventLogError.cancelled
        }

        purge(now: now) // Purge first to reduce disk space

        do {
            try manager.fileManager.createDirectory(at: manager.directory, withIntermediateDirectories: true, attributes: nil)

            var startDate = historicalDate(from: now)
            while startDate < manager.recentDate(from: now) {
                guard !isCancelled else {
                    return CriticalEventLogError.cancelled
                }

                let endDate = manager.date(byAddingDays: 1, to: startDate)
                let exportFileURL = exportsFileURL(for: endDate)
                if !manager.fileManager.fileExists(atPath: exportFileURL.path) {
                    log.default("Exporting %{public}@...", exportFileURL.lastPathComponent)

                    let temporaryFileURL = manager.fileManager.temporaryFileURL
                    defer { try? manager.fileManager.removeItem(at: temporaryFileURL) }

                    if let error = export(startDate: startDate, endDate: endDate, to: temporaryFileURL, progress: progress) {
                        return error
                    }

                    try manager.fileManager.moveItem(at: temporaryFileURL, to: exportFileURL)

                    log.default("Exported %{public}@", exportFileURL.lastPathComponent)
                }

                startDate = endDate
            }
            return nil
        } catch let error {
            return error
        }
    }

    fileprivate override func exportProgressTotalUnitCount(now: Date) -> Result<Int64, Error> {
        return exportProgressTotalUnitCount(through: manager.recentDate(from: now), now: now)
    }

    private func purge(now: Date) {
        do {
            try manager.fileManager.createDirectory(at: manager.directory, withIntermediateDirectories: true, attributes: nil)
            for fileURL in try manager.fileManager.contentsOfDirectory(at: manager.directory, includingPropertiesForKeys: nil) {
                if fileURL.pathExtension == manager.archiveExtension, let fileDate = manager.date(from: fileURL.deletingPathExtension().lastPathComponent) {
                    if fileDate <= historicalDate(from: now) {
                        log.default("Purging %{public}@...", fileURL.lastPathComponent)
                        try manager.fileManager.removeItem(at: fileURL)
                        log.default("Purged %{public}@", fileURL.lastPathComponent)
                    }
                }
            }
        } catch let error {
            log.error("Failure purging historical export with error: %{public}@", String(describing: error))
        }
    }
}

// MARK: - CriticalEventLogFullExporter

public class CriticalEventLogFullExporter: CriticalEventLogBaseExporter, CriticalEventLogSynchronizedExporter {
    private let historicalExporter: CriticalEventLogHistoricalExporter
    private let url: URL
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier?

    private let log = OSLog(category: "CriticalEventLogFullExporter")

    fileprivate init(manager: CriticalEventLogExportManager, to url: URL) {
        self.historicalExporter = CriticalEventLogHistoricalExporter(manager: manager)
        self.url = url
        super.init(manager: manager)
    }

    public func export(now: Date, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            NotificationCenter.default.addObserver(self, selector: #selector(self.willEnterForegroundNotificationReceived(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
            self.beginBackgroundTask()
        }

        DispatchQueue.global(qos: .utility).async {
            completion(self.manager.synchronizeExport(for: self, cancellingActive: true, now: now))

            DispatchQueue.main.async {
                self.endBackgroundTask()
                NotificationCenter.default.removeObserver(self)
            }
        }
    }

    private let progressUnitCountArchivePerDay: Int64 = 10
    private let progressUnitCountMove: Int64 = 10

    fileprivate override func exportSynchronized(now: Date) -> Error? {
        if let error = super.exportSynchronized(now: now) {
            return error
        }

        let observation = progress.observe(\.fractionCompleted, options: []) { [weak self] object, _ in
            self?.delegate?.exportDidProgress(object.fractionCompleted)
        }
        defer { observation.invalidate() }

        if let error = historicalExporter.exportSynchronized(progress: progress, now: now) {
            return error
        }

        guard !isCancelled else {
            return CriticalEventLogError.cancelled
        }

        let recentFileURL = exportsFileURL(for: now)
        let recentTemporaryFileURL = manager.fileManager.temporaryFileURL
        defer { try? manager.fileManager.removeItem(at: recentTemporaryFileURL) }

        log.default("Exporting %{public}@...", recentFileURL.lastPathComponent)

        if let error = export(startDate: manager.recentDate(from: now), endDate: now, to: recentTemporaryFileURL, progress: progress) {
            return error
        }

        log.default("Exported %{public}@", recentFileURL.lastPathComponent)

        guard !isCancelled else {
            return CriticalEventLogError.cancelled
        }

        log.default("Exporting final archive %{public}@", url.lastPathComponent)

        let archiveTemporaryFileURL = manager.fileManager.temporaryFileURL
        defer { try? manager.fileManager.removeItem(at: archiveTemporaryFileURL) }

        guard let archive = ZipArchive(url: archiveTemporaryFileURL) else {
            return CriticalEventLogExportError.archiveFailure
        }
        defer { archive.close() }

        var date = historicalDate(from: now)
        while date < manager.recentDate(from: now) {
            guard !isCancelled else {
                return CriticalEventLogError.cancelled
            }

            date = manager.date(byAddingDays: 1, to: date)

            let exportFileURL = exportsFileURL(for: date)
            log.default("Bundling %{public}@", exportFileURL.lastPathComponent)
            if let error = archive.createArchiveFile(withPath: exportFileURL.lastPathComponent, contentsOf: exportFileURL, compressionMethod: .none) {
                return error
            }

            progress.completedUnitCount += progressUnitCountArchivePerDay
        }

        guard !isCancelled else {
            return CriticalEventLogError.cancelled
        }

        log.default("Bundling %{public}@", recentFileURL.lastPathComponent)
        if let error = archive.createArchiveFile(withPath: recentFileURL.lastPathComponent, contentsOf: recentTemporaryFileURL, compressionMethod: .none) {
            return error
        }

        progress.completedUnitCount += progressUnitCountArchivePerDay

        if let error = archive.close() {
            return error
        }

        guard !isCancelled else {
            return CriticalEventLogError.cancelled
        }

        do {
            try manager.fileManager.moveItem(at: archiveTemporaryFileURL, to: url)
        } catch let error {
            return error
        }

        progress.completedUnitCount += progressUnitCountMove

        log.default("Exported final archive %{public}@", url.lastPathComponent)
        return nil
    }

    fileprivate override func exportProgressTotalUnitCount(now: Date) -> Result<Int64, Error> {
        switch super.exportProgressTotalUnitCount(now: now) {
        case .failure(let error):
            return .failure(error)
        case .success(let progressTotalUnitCount):
            return .success(progressTotalUnitCount + Int64(manager.historicalDuration.days) * progressUnitCountArchivePerDay + progressUnitCountMove)
        }
    }

    private func beginBackgroundTask() {
        dispatchPrecondition(condition: .onQueue(.main))

        self.endBackgroundTask()

        self.backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask {
            self.log.default("Invoked critical event log full export background task expiration handler")
            self.endBackgroundTask()
        }

        self.log.default("Begin critical event log full export background task")
    }

    private func endBackgroundTask() {
        dispatchPrecondition(condition: .onQueue(.main))

        if let backgroundTaskIdentifier = self.backgroundTaskIdentifier {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            self.backgroundTaskIdentifier = nil
            self.log.default("End critical event log full export background task")
        }
    }

    @objc private func willEnterForegroundNotificationReceived(_ notification: Notification) {
        beginBackgroundTask()
    }
}

// MARK: - FileManager

fileprivate extension FileManager {
    var temporaryFileURL: URL {
        return temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}
