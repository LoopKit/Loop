//
//  DataLayer_SyncService.swift
//  Loop
//
//  DataLayer — Upload pipeline. Batches events and POSTs to GCP Cloud Run.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import UIKit

/// Handles uploading DataLayer events to the remote ingest endpoint.
/// Fire-and-forget semantics: all errors are silently caught and logged.
/// Uses exponential backoff on consecutive failures (15min → 24hr cap).
final class DataLayer_SyncService {

    static let shared = DataLayer_SyncService()

    // MARK: - Configuration

    private static let baseSyncInterval: TimeInterval = 900   // 15 minutes
    private static let maxSyncInterval: TimeInterval = 86400   // 24 hours
    private static let maxRetryAttempts = 10
    private static let batchSize = 100

    // MARK: - State

    private var syncTimer: Timer?
    private var currentInterval: TimeInterval = baseSyncInterval
    private var consecutiveFailures = 0
    private var isSyncing = false
    private var foregroundObserver: NSObjectProtocol?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {}

    // MARK: - Lifecycle

    /// Start the sync timer. Called from Coordinator.start().
    func start() {
        guard canSync else {
            DataLayer_FeatureFlags.log.info("SyncService: not starting (guards not met)")
            return
        }

        scheduleTimer()
        observeForeground()
        DataLayer_FeatureFlags.log.info("SyncService started (interval: \(Int(self.currentInterval))s)")
    }

    /// Stop the sync timer. Called from Coordinator.stop() and deleteAllData().
    func stop() {
        syncTimer?.invalidate()
        syncTimer = nil

        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }

        currentInterval = Self.baseSyncInterval
        consecutiveFailures = 0
        isSyncing = false

        DataLayer_FeatureFlags.log.info("SyncService stopped")
    }

    /// Trigger an immediate sync attempt (e.g., on foreground).
    func syncNow() {
        guard canSync, !isSyncing else { return }
        syncBatch()
    }

    // MARK: - Timer

    private func scheduleTimer() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: true) { [weak self] _ in
            self?.syncBatch()
        }
    }

    private func observeForeground() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncNow()
        }
    }

    // MARK: - Sync Logic

    private var canSync: Bool {
        DataLayer_FeatureFlags.isEnabled
            && DataLayer_FeatureFlags.researchEnabled
            && DataLayer_FeatureFlags.ingestEndpointURL != nil
    }

    private func syncBatch() {
        guard canSync, !isSyncing else { return }
        isSyncing = true

        let events = DataLayer_EventCollector.shared.eventStore.pendingUploadBatch(limit: Self.batchSize)
        guard !events.isEmpty else {
            isSyncing = false
            return
        }

        let uploadEvents = events.compactMap { toUploadEvent($0) }
        guard !uploadEvents.isEmpty else {
            isSyncing = false
            return
        }

        uploadBatch(uploadEvents) { [weak self] success in
            guard let self = self else { return }
            let ids = events.map { $0.id }

            if success {
                DataLayer_EventCollector.shared.eventStore.markUploaded(ids: ids)
                self.onSuccess()
                DataLayer_FeatureFlags.log.info("SyncService: uploaded \(ids.count) events")
            } else {
                DataLayer_EventCollector.shared.eventStore.markFailed(ids: ids)
                self.onFailure()
                DataLayer_FeatureFlags.log.info("SyncService: batch failed (\(self.consecutiveFailures) consecutive)")
            }

            self.isSyncing = false
        }
    }

    // MARK: - Upload

    private func uploadBatch(_ events: [DataLayer_UploadEvent], completion: @escaping (Bool) -> Void) {
        guard let url = DataLayer_FeatureFlags.ingestEndpointURL else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = DataLayer_FeatureFlags.ingestAPIKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try encoder.encode(events)
        } catch {
            DataLayer_FeatureFlags.log.error("SyncService: failed to encode batch — \(error.localizedDescription)")
            completion(false)
            return
        }

        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                DataLayer_FeatureFlags.log.error("SyncService: network error — \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false)
                return
            }

            // 2xx = success; 4xx = client error (don't retry endlessly); 5xx/403 = server/billing issue
            let success = (200...299).contains(httpResponse.statusCode)
            if !success {
                DataLayer_FeatureFlags.log.error("SyncService: HTTP \(httpResponse.statusCode)")
            }
            completion(success)
        }
        task.resume()
    }

    // MARK: - Backoff

    private func onSuccess() {
        consecutiveFailures = 0
        currentInterval = Self.baseSyncInterval
        scheduleTimer()
    }

    private func onFailure() {
        consecutiveFailures += 1
        // Exponential backoff: 15min, 30min, 1hr, 2hr, 4hr, 8hr, 24hr cap
        let backoff = Self.baseSyncInterval * pow(2.0, Double(min(consecutiveFailures, 7)))
        currentInterval = min(backoff, Self.maxSyncInterval)
        scheduleTimer()
    }

    // MARK: - Event Conversion

    /// Convert a stored DataLayer_Event to an upload-ready struct (strips local-only fields,
    /// decodes payload Data back to JSON).
    private func toUploadEvent(_ event: DataLayer_Event) -> DataLayer_UploadEvent? {
        // Decode the stored Data blob back to a JSON-compatible dictionary
        let payloadJSON: Any
        do {
            payloadJSON = try JSONSerialization.jsonObject(with: event.payload, options: [])
        } catch {
            DataLayer_FeatureFlags.log.error("SyncService: failed to decode payload for \(event.id)")
            return nil
        }

        // Re-serialize the payload as a JSON-compatible wrapper
        guard let payloadWrapper = payloadJSON as? [String: Any] else {
            return nil
        }

        return DataLayer_UploadEvent(
            id: event.id.uuidString,
            deviceID: event.deviceID,
            eventType: event.eventType.rawValue,
            timestamp: event.timestamp,
            sessionID: event.sessionID.uuidString,
            appVersion: event.appVersion,
            schemaVersion: event.schemaVersion,
            payload: payloadWrapper
        )
    }
}

// MARK: - Upload Event

/// Wire format for events sent to the ingest endpoint.
/// Strips local-only fields (uploadStatus, uploadAttempts, createdAt)
/// and sends payload as decoded JSON (not raw Data).
struct DataLayer_UploadEvent: Encodable {
    let id: String
    let deviceID: String
    let eventType: String
    let timestamp: Date
    let sessionID: String
    let appVersion: String
    let schemaVersion: Int
    let payload: [String: Any]

    enum CodingKeys: String, CodingKey {
        case id, deviceID, eventType, timestamp, sessionID, appVersion, schemaVersion, payload
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(eventType, forKey: .eventType)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(schemaVersion, forKey: .schemaVersion)

        // Encode the [String: Any] payload using JSONSerialization
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let payloadJSON = try JSONDecoder().decode(AnyCodable.self, from: payloadData)
        try container.encode(payloadJSON, forKey: .payload)
    }
}

// MARK: - AnyCodable Helper

/// Minimal type-erased Codable wrapper for encoding arbitrary JSON dictionaries.
private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(Any.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable(wrapping: $0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable(wrapping: $0) })
        default:
            try container.encodeNil()
        }
    }

    fileprivate init(wrapping value: Any) {
        self.value = value
    }
}
