//
//  BolusPro_DataLayerHook.swift
//  Loop
//
//  BolusPro — Broadcasts a per-meal analytics snapshot via
//  NotificationCenter every time a BolusPro-aware carb entry is saved.
//  Standalone — no external dependencies. Observers (DataLayer event
//  recorder, LoopInsights BehaviorInsights, third-party plugins) wire
//  onto `notificationName` from their own modules.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Source of the macro values that drove the FPU calculation.
/// Recorded for data-quality stratification in DataLayer.
enum BolusProMacrosSource: String, Codable {
    case ai
    case product
    case favorite
    case manual
}

/// Frozen snapshot of every BolusPro-relevant value at carb-entry submit
/// time. Built by `CarbEntryViewModel`, attached to `BolusEntryViewModel`,
/// and consumed by the DataLayer hook + BehaviorInsights observer once the
/// secondary entry persists successfully.
struct BolusProAnalyticsSnapshot {
    let enabled: Bool
    let autoDetected: Bool?
    let macrosSource: BolusProMacrosSource?
    let fpuScore: Double
    let bonusGrams: Double
    let sliderPosition: Double?
    let coverageFactorPercent: Int
    let fpuDelayMinutes: Int
    let fpuAbsorptionHours: Int
    let fatGramsInput: Double
    let proteinGramsInput: Double
    let primaryCarbGrams: Double
}

/// Static hook called by `BolusEntryViewModel` immediately after the
/// primary (and optional secondary) carb entries are saved. Broadcasts
/// the snapshot via `NotificationCenter` so any observer — analytics
/// pipelines, behavior analyzers, third-party plugins — can consume
/// without BolusEntryViewModel knowing about them.
///
/// **No external dependencies.** This file is safe to ship standalone
/// in upstream Loop. Fork-only consumers (DataLayer event recording,
/// LoopInsights BehaviorInsights, etc.) subscribe to `notificationName`
/// in their own modules.
enum BolusPro_DataLayerHook {

    /// Posted whenever a BolusPro-aware carb entry is saved. UserInfo
    /// carries the `BolusProAnalyticsSnapshot` under the `"snapshot"` key.
    static let notificationName = Notification.Name("com.loopkit.Loop.bolusProEntrySaved")

    /// UserInfo key for the snapshot payload.
    static let snapshotUserInfoKey = "snapshot"

    static func recordSavedEntry(_ snapshot: BolusProAnalyticsSnapshot) {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [snapshotUserInfoKey: snapshot]
        )
    }
}
