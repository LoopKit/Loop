//
//  DataLayer_EventStore.swift
//  Loop
//
//  DataLayer — SQLite-backed event persistence with indexed queries.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import SQLite3

/// SQLite-backed event store for the DataLayer.
/// Uses raw SQLite3 C API (no external dependencies, matching Loop's approach).
/// Auto-prunes events older than the configured retention period on init.
final class DataLayer_EventStore {

    // MARK: - Properties

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.loopkit.Loop.DataLayer.EventStore", qos: .utility)

    // MARK: - Initialization

    init() {
        openDatabase()
        createTableIfNeeded()
        pruneExpired()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private var databaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("DataLayer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.sqlite")
    }

    private func openDatabase() {
        let path = databaseURL.path
        if sqlite3_open(path, &db) != SQLITE_OK {
            DataLayer_FeatureFlags.log.error("Failed to open DataLayer database at \(path)")
            db = nil
        }

        // Enable WAL mode for better concurrent read performance
        execute("PRAGMA journal_mode=WAL")
    }

    private func createTableIfNeeded() {
        let createSQL = """
            CREATE TABLE IF NOT EXISTS events (
                id TEXT PRIMARY KEY,
                deviceID TEXT NOT NULL,
                eventType TEXT NOT NULL,
                timestamp REAL NOT NULL,
                sessionID TEXT NOT NULL,
                appVersion TEXT NOT NULL,
                schemaVersion INTEGER NOT NULL,
                payload BLOB NOT NULL,
                uploadStatus TEXT NOT NULL DEFAULT 'pending',
                uploadAttempts INTEGER NOT NULL DEFAULT 0,
                createdAt REAL NOT NULL
            )
            """
        execute(createSQL)

        // Index for batch upload queries
        execute("CREATE INDEX IF NOT EXISTS idx_events_upload ON events (uploadStatus, createdAt)")

        // Index for local querying by type and time
        execute("CREATE INDEX IF NOT EXISTS idx_events_type_time ON events (eventType, timestamp)")
    }

    // MARK: - Insert

    /// Insert a single event. Thread-safe.
    func insert(_ event: DataLayer_Event) {
        queue.async { [weak self] in
            self?.insertSync(event)
        }
    }

    private func insertSync(_ event: DataLayer_Event) {
        guard let db = db else { return }

        let sql = """
            INSERT OR IGNORE INTO events
                (id, deviceID, eventType, timestamp, sessionID, appVersion, schemaVersion, payload, uploadStatus, uploadAttempts, createdAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            DataLayer_FeatureFlags.log.error("Failed to prepare insert statement")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, event.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, event.deviceID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, event.eventType.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(stmt, 4, event.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 5, event.sessionID.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 6, event.appVersion, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 7, Int32(event.schemaVersion))
        event.payload.withUnsafeBytes { bytes in
            sqlite3_bind_blob(stmt, 8, bytes.baseAddress, Int32(event.payload.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        sqlite3_bind_text(stmt, 9, event.uploadStatus.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 10, Int32(event.uploadAttempts))
        sqlite3_bind_double(stmt, 11, event.createdAt.timeIntervalSince1970)

        if sqlite3_step(stmt) != SQLITE_DONE {
            DataLayer_FeatureFlags.log.error("Failed to insert event: \(event.eventType.rawValue)")
        }
    }

    // MARK: - Query

    /// Get a batch of pending upload events.
    func pendingUploadBatch(limit: Int = 100) -> [DataLayer_Event] {
        return queue.sync { pendingUploadBatchSync(limit: limit) }
    }

    private func pendingUploadBatchSync(limit: Int) -> [DataLayer_Event] {
        guard let db = db else { return [] }

        let sql = """
            SELECT * FROM events
            WHERE uploadStatus = 'pending'
               OR (uploadStatus = 'failed' AND uploadAttempts < 10)
            ORDER BY createdAt ASC LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))
        return readEvents(from: stmt)
    }

    /// Count events of a specific type.
    func eventCount(type: DataLayer_EventType? = nil) -> Int {
        return queue.sync { eventCountSync(type: type) }
    }

    private func eventCountSync(type: DataLayer_EventType?) -> Int {
        guard let db = db else { return 0 }

        let sql: String
        if let type = type {
            sql = "SELECT COUNT(*) FROM events WHERE eventType = '\(type.rawValue)'"
        } else {
            sql = "SELECT COUNT(*) FROM events"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    /// Get all events within a date range.
    func events(from start: Date, to end: Date) -> [DataLayer_Event] {
        return queue.sync { eventsInRangeSync(from: start, to: end) }
    }

    private func eventsInRangeSync(from start: Date, to end: Date) -> [DataLayer_Event] {
        guard let db = db else { return [] }

        let sql = "SELECT * FROM events WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, end.timeIntervalSince1970)
        return readEvents(from: stmt)
    }

    /// Event counts grouped by event type.
    func eventCountsByType() -> [(String, Int)] {
        return queue.sync { eventCountsByTypeSync() }
    }

    private func eventCountsByTypeSync() -> [(String, Int)] {
        guard let db = db else { return [] }

        let sql = "SELECT eventType, COUNT(*) FROM events GROUP BY eventType ORDER BY COUNT(*) DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [(String, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let typeStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) else { continue }
            let count = Int(sqlite3_column_int(stmt, 1))
            results.append((typeStr, count))
        }
        return results
    }

    /// Event counts grouped by upload status.
    func uploadStatusCounts() -> [(String, Int)] {
        return queue.sync { uploadStatusCountsSync() }
    }

    private func uploadStatusCountsSync() -> [(String, Int)] {
        guard let db = db else { return [] }

        let sql = "SELECT uploadStatus, COUNT(*) FROM events GROUP BY uploadStatus ORDER BY COUNT(*) DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [(String, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let status = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) else { continue }
            let count = Int(sqlite3_column_int(stmt, 1))
            results.append((status, count))
        }
        return results
    }

    /// Daily event counts for the last N days.
    func dailyEventCounts(days: Int = 14) -> [(String, Int)] {
        return queue.sync { dailyEventCountsSync(days: days) }
    }

    private func dailyEventCountsSync(days: Int) -> [(String, Int)] {
        guard let db = db else { return [] }

        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let sql = """
            SELECT date(timestamp, 'unixepoch', 'localtime') AS day, COUNT(*)
            FROM events WHERE timestamp >= \(cutoff)
            GROUP BY day ORDER BY day ASC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [(String, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let day = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) else { continue }
            let count = Int(sqlite3_column_int(stmt, 1))
            results.append((day, count))
        }
        return results
    }

    /// Most recent events.
    func recentEvents(limit: Int = 25) -> [DataLayer_Event] {
        return queue.sync { recentEventsSync(limit: limit) }
    }

    private func recentEventsSync(limit: Int) -> [DataLayer_Event] {
        guard let db = db else { return [] }

        let sql = "SELECT * FROM events ORDER BY timestamp DESC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))
        return readEvents(from: stmt)
    }

    // MARK: - Update Status

    /// Mark events as uploaded.
    func markUploaded(ids: [UUID]) {
        queue.async { [weak self] in
            self?.updateStatus(.uploaded, for: ids)
        }
    }

    /// Mark events as failed.
    func markFailed(ids: [UUID]) {
        queue.async { [weak self] in
            self?.updateStatus(.failed, for: ids)
        }
    }

    private func updateStatus(_ status: DataLayer_UploadStatus, for ids: [UUID]) {
        guard let db = db, !ids.isEmpty else { return }

        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "UPDATE events SET uploadStatus = ?, uploadAttempts = uploadAttempts + 1 WHERE id IN (\(placeholders))"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, status.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        for (index, id) in ids.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 2), id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        sqlite3_step(stmt)
    }

    // MARK: - Delete

    /// Delete all events older than the retention period.
    func pruneExpired() {
        queue.async { [weak self] in
            self?.pruneExpiredSync()
        }
    }

    private func pruneExpiredSync() {
        let retentionDays = DataLayer_FeatureFlags.retentionDays
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        execute("DELETE FROM events WHERE createdAt < \(cutoff.timeIntervalSince1970)")
    }

    /// Delete all events (for "Delete All My Data").
    func deleteAll() {
        queue.async { [weak self] in
            self?.execute("DELETE FROM events")
        }
    }

    /// Delete events before a specific date.
    func deleteAll(before date: Date) {
        queue.async { [weak self] in
            self?.execute("DELETE FROM events WHERE timestamp < \(date.timeIntervalSince1970)")
        }
    }

    // MARK: - Private Helpers

    private func execute(_ sql: String) {
        guard let db = db else { return }
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            if let msg = errmsg {
                DataLayer_FeatureFlags.log.error("SQL error: \(String(cString: msg))")
                sqlite3_free(msg)
            }
        }
    }

    private func readEvents(from stmt: OpaquePointer?) -> [DataLayer_Event] {
        var events: [DataLayer_Event] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                  let id = UUID(uuidString: idStr),
                  let deviceID = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
                  let eventTypeStr = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }),
                  let eventType = DataLayer_EventType(rawValue: eventTypeStr),
                  let sessionIDStr = sqlite3_column_text(stmt, 4).map({ String(cString: $0) }),
                  let sessionID = UUID(uuidString: sessionIDStr),
                  let appVersion = sqlite3_column_text(stmt, 5).map({ String(cString: $0) }),
                  let uploadStatusStr = sqlite3_column_text(stmt, 8).map({ String(cString: $0) }),
                  let uploadStatus = DataLayer_UploadStatus(rawValue: uploadStatusStr)
            else { continue }

            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            let schemaVersion = Int(sqlite3_column_int(stmt, 6))
            let payloadBytes = sqlite3_column_bytes(stmt, 7)
            let payload: Data
            if payloadBytes > 0, let blob = sqlite3_column_blob(stmt, 7) {
                payload = Data(bytes: blob, count: Int(payloadBytes))
            } else {
                payload = Data()
            }
            let uploadAttempts = Int(sqlite3_column_int(stmt, 9))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))

            events.append(DataLayer_Event(
                id: id,
                deviceID: deviceID,
                eventType: eventType,
                timestamp: timestamp,
                sessionID: sessionID,
                appVersion: appVersion,
                schemaVersion: schemaVersion,
                payload: payload,
                uploadStatus: uploadStatus,
                uploadAttempts: uploadAttempts,
                createdAt: createdAt
            ))
        }
        return events
    }
}
