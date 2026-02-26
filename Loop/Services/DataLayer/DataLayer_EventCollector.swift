//
//  DataLayer_EventCollector.swift
//  Loop
//
//  DataLayer — Singleton event bus. Features call .record() to emit events.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Central event collection point for the DataLayer.
/// Features call `DataLayer_EventCollector.shared.record(type:payload:)` to emit events.
/// Events are only persisted if the master toggle is ON and the user has consented
/// to the relevant data category.
final class DataLayer_EventCollector {

    static let shared = DataLayer_EventCollector()

    private let store = DataLayer_EventStore()
    private let consent = DataLayer_ConsentManager.shared
    private var sessionID = UUID()
    private let encoder = JSONEncoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Record Events

    /// Record a typed event. Guards on master toggle and per-category consent.
    /// Event writes are <1ms and dispatched to a background queue.
    func record<P: Encodable>(type: DataLayer_EventType, payload: P) {
        guard DataLayer_FeatureFlags.isEnabled else { return }
        guard consent.isGranted(for: type.consentCategory) else { return }

        guard let payloadData = try? encoder.encode(payload) else {
            DataLayer_FeatureFlags.log.error("Failed to encode payload for \(type.rawValue)")
            return
        }

        let event = DataLayer_Event(
            id: UUID(),
            deviceID: DataLayer_SecureStorage.anonymizedDeviceID,
            eventType: type,
            timestamp: Date(),
            sessionID: sessionID,
            appVersion: Self.appVersion,
            schemaVersion: type.currentSchemaVersion,
            payload: payloadData,
            uploadStatus: .pending,
            uploadAttempts: 0,
            createdAt: Date()
        )

        store.insert(event)
    }

    // MARK: - Session Management

    /// Start a new session (called on app launch).
    func startSession() {
        sessionID = UUID()
        record(type: .sessionStart, payload: DataLayer_SessionPayload(
            timezone: TimeZone.current.identifier,
            localeRegion: Locale.current.regionCode
        ))
    }

    /// End the current session (called on app background).
    func endSession() {
        record(type: .sessionEnd, payload: DataLayer_SessionPayload(
            timezone: TimeZone.current.identifier,
            localeRegion: Locale.current.regionCode
        ))
    }

    // MARK: - Store Access

    /// Direct access to the event store for querying and management.
    var eventStore: DataLayer_EventStore { store }

    // MARK: - Private

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
