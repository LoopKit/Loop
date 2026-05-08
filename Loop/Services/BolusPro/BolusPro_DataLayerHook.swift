//
//  BolusPro_DataLayerHook.swift
//  Loop
//
//  BolusPro — Captures per-meal analytics snapshot at submit time and
//  posts to DataLayer once the carb entries land. Also broadcasts a
//  Notification consumed by LoopInsights' BehaviorInsightsAnalyzer.
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
/// primary (and optional secondary) carb entries are saved. Posts the
/// DataLayer event AND the LoopInsights notification — single seam, both
/// consumers wire onto it without BolusEntryViewModel knowing about either.
enum BolusPro_DataLayerHook {

    /// Notification name observed by LoopInsights_BehaviorInsightsAnalyzer.
    /// `userInfo["snapshot"]` carries the `BolusProAnalyticsSnapshot`.
    static let notificationName = Notification.Name("com.loopkit.Loop.bolusProEntrySaved")

    static func recordSavedEntry(_ snapshot: BolusProAnalyticsSnapshot) {
        // 1) DataLayer event (gated by feature flag + consent inside the
        //    collector — we don't need to check here).
        let payload = DataLayer_BolusProPayload(
            enabled: snapshot.enabled,
            autoDetected: snapshot.autoDetected,
            macrosSource: snapshot.macrosSource?.rawValue,
            fpuScore: snapshot.fpuScore,
            bonusGrams: snapshot.bonusGrams,
            sliderPosition: snapshot.sliderPosition,
            coverageFactorPercent: snapshot.coverageFactorPercent,
            fpuDelayMinutes: snapshot.fpuDelayMinutes,
            fpuAbsorptionHours: snapshot.fpuAbsorptionHours,
            fatGramsInput: snapshot.fatGramsInput,
            proteinGramsInput: snapshot.proteinGramsInput,
            primaryCarbGrams: snapshot.primaryCarbGrams
        )
        DataLayer_EventCollector.shared.record(type: .bolusProEntry, payload: payload)

        // 2) Local broadcast for LoopInsights BehaviorInsights to learn
        //    user adoption / slider drift / FPU distribution patterns.
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: ["snapshot": snapshot]
        )
    }
}
