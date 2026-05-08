//
//  BolusPro_BehaviorAnalyzer.swift
//  Loop
//
//  BolusPro — Captures snapshots from saved entries, derives behavior
//  patterns (slider drift, adoption rate, override rate, etc.) and feeds
//  them into LoopInsights' Behavior Insights view.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Persisted Snapshot

/// Persisted form of `BolusProAnalyticsSnapshot` for offline pattern
/// analysis. Includes a timestamp so we can window to recent meals.
struct BolusProSnapshotRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let enabled: Bool
    let autoDetected: Bool?
    let macrosSourceRaw: String?
    let fpuScore: Double
    let bonusGrams: Double
    let sliderPosition: Double?
    let coverageFactorPercent: Int
    let fatGramsInput: Double
    let proteinGramsInput: Double
    let primaryCarbGrams: Double

    init(snapshot: BolusProAnalyticsSnapshot, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.enabled = snapshot.enabled
        self.autoDetected = snapshot.autoDetected
        self.macrosSourceRaw = snapshot.macrosSource?.rawValue
        self.fpuScore = snapshot.fpuScore
        self.bonusGrams = snapshot.bonusGrams
        self.sliderPosition = snapshot.sliderPosition
        self.coverageFactorPercent = snapshot.coverageFactorPercent
        self.fatGramsInput = snapshot.fatGramsInput
        self.proteinGramsInput = snapshot.proteinGramsInput
        self.primaryCarbGrams = snapshot.primaryCarbGrams
    }
}

// MARK: - Behavior Pattern Output

/// A single piece of behavioral insight surfaced in the LoopInsights
/// Behavior Insights view. Multiple patterns are produced per analysis.
struct BolusProBehaviorPattern: Identifiable, Equatable {
    let id: UUID
    let kind: Kind
    let summary: String
    let detail: String
    let mealCount: Int

    enum Kind: String {
        case adoption
        case sliderDrift
        case autoDetectOverride
        case bonusDistribution
        case macrosSourceMix
    }

    var systemImage: String {
        switch kind {
        case .adoption:           return "checkmark.circle.fill"
        case .sliderDrift:        return "slider.horizontal.3"
        case .autoDetectOverride: return "wand.and.stars.inverse"
        case .bonusDistribution:  return "chart.bar.fill"
        case .macrosSourceMix:    return "tray.full"
        }
    }
}

// MARK: - Analyzer

/// Singleton observer + analyzer. Subscribes to the BolusPro save
/// notification, persists a rolling 30-day window of snapshots, and on
/// demand produces a list of `BolusProBehaviorPattern` for the
/// LoopInsights Behavior Insights view.
final class BolusPro_BehaviorAnalyzer {

    static let shared = BolusPro_BehaviorAnalyzer()

    /// Maximum number of snapshots to retain (across all meals). Older
    /// records are dropped on each write.
    private let maxRecords = 200

    /// Window for pattern analysis.
    private let analysisDays = 30

    private let storeKey = "com.loopkit.Loop.bolusProSnapshotStore"

    private var observer: NSObjectProtocol?

    private init() { }

    // MARK: - Lifecycle

    /// Begin observing BolusPro save notifications. Idempotent — safe to
    /// call from `DataLayer_Coordinator.init()` or any app-launch site.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: BolusPro_DataLayerHook.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let snapshot = note.userInfo?["snapshot"] as? BolusProAnalyticsSnapshot else { return }
            self?.append(snapshot)
        }
    }

    // MARK: - Storage

    private func loadRecords() -> [BolusProSnapshotRecord] {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return [] }
        return (try? JSONDecoder().decode([BolusProSnapshotRecord].self, from: data)) ?? []
    }

    private func saveRecords(_ records: [BolusProSnapshotRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    private func append(_ snapshot: BolusProAnalyticsSnapshot) {
        var records = loadRecords()
        records.append(BolusProSnapshotRecord(snapshot: snapshot))
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }
        saveRecords(records)
    }

    // MARK: - Pattern Analysis

    /// Generate behavior patterns over the analysis window. Returns an
    /// empty array when there isn't enough data to be meaningful (≥3
    /// snapshots, with at least 1 BolusPro-enabled).
    func analyzePatterns() -> [BolusProBehaviorPattern] {
        let cutoff = Date().addingTimeInterval(-Double(analysisDays * 24 * 3600))
        let recent = loadRecords().filter { $0.timestamp >= cutoff }
        guard recent.count >= 3 else { return [] }

        var patterns: [BolusProBehaviorPattern] = []

        if let p = adoptionPattern(in: recent) { patterns.append(p) }
        if let p = sliderDriftPattern(in: recent) { patterns.append(p) }
        if let p = autoDetectOverridePattern(in: recent) { patterns.append(p) }
        if let p = bonusDistributionPattern(in: recent) { patterns.append(p) }
        if let p = macrosSourceMixPattern(in: recent) { patterns.append(p) }

        return patterns
    }

    // MARK: - Pattern Builders

    private func adoptionPattern(in records: [BolusProSnapshotRecord]) -> BolusProBehaviorPattern? {
        let total = records.count
        guard total >= 3 else { return nil }
        let enabled = records.filter { $0.enabled }.count
        let percent = Int((Double(enabled) / Double(total) * 100).rounded())
        return BolusProBehaviorPattern(
            id: UUID(),
            kind: .adoption,
            summary: "BolusPro used on \(percent)% of meals",
            detail: "\(enabled) of \(total) meals in the last \(analysisDays) days had BolusPro enabled at submit.",
            mealCount: total
        )
    }

    private func sliderDriftPattern(in records: [BolusProSnapshotRecord]) -> BolusProBehaviorPattern? {
        let usedRecords = records.compactMap { rec -> Double? in
            guard rec.enabled, let pos = rec.sliderPosition else { return nil }
            return pos
        }
        guard usedRecords.count >= 3 else { return nil }
        let avg = usedRecords.reduce(0, +) / Double(usedRecords.count)
        let avgPct = Int((avg * 100).rounded())
        let driftFromDefault = avgPct - 100  // slider 1.0 = 100% of computed bonus
        let driftDescription: String
        if abs(driftFromDefault) <= 10 {
            driftDescription = "close to the default"
        } else if driftFromDefault < 0 {
            driftDescription = "lighter than the default"
        } else {
            driftDescription = "heavier than the default"
        }
        return BolusProBehaviorPattern(
            id: UUID(),
            kind: .sliderDrift,
            summary: "Your typical slider sits at \(avgPct)%",
            detail: "Across \(usedRecords.count) BolusPro meals you've averaged \(avgPct)% of the computed FPU bonus — \(driftDescription).",
            mealCount: usedRecords.count
        )
    }

    private func autoDetectOverridePattern(in records: [BolusProSnapshotRecord]) -> BolusProBehaviorPattern? {
        // For each meal where auto-detect WOULD have triggered (FPU ≥ trigger),
        // count how often the user kept it on vs turned it off.
        let threshold = BolusPro_FeatureFlags.triggerThresholdFPU
        let candidates = records.filter { $0.fpuScore >= threshold }
        guard candidates.count >= 3 else { return nil }
        let kept = candidates.filter { $0.enabled }.count
        let percent = Int((Double(kept) / Double(candidates.count) * 100).rounded())
        return BolusProBehaviorPattern(
            id: UUID(),
            kind: .autoDetectOverride,
            summary: "Kept BolusPro on for \(percent)% of high-FPU meals",
            detail: "Of \(candidates.count) meals over the auto-trigger threshold of \(String(format: "%.1f", threshold)) FPU, you kept BolusPro enabled \(kept) times.",
            mealCount: candidates.count
        )
    }

    private func bonusDistributionPattern(in records: [BolusProSnapshotRecord]) -> BolusProBehaviorPattern? {
        let bonusValues = records.compactMap { rec -> Double? in
            rec.enabled && rec.bonusGrams > 0 ? rec.bonusGrams : nil
        }
        guard bonusValues.count >= 3 else { return nil }
        let avg = bonusValues.reduce(0, +) / Double(bonusValues.count)
        let max = bonusValues.max() ?? 0
        return BolusProBehaviorPattern(
            id: UUID(),
            kind: .bonusDistribution,
            summary: String(format: "Average BolusPro bonus is %.0fg", avg),
            detail: String(format: "Across %d meals your protein/fat tail averaged %.0fg, peaking at %.0fg.", bonusValues.count, avg, max),
            mealCount: bonusValues.count
        )
    }

    private func macrosSourceMixPattern(in records: [BolusProSnapshotRecord]) -> BolusProBehaviorPattern? {
        let sourced = records.filter { $0.enabled && $0.macrosSourceRaw != nil }
        guard sourced.count >= 3 else { return nil }
        var counts: [String: Int] = [:]
        for rec in sourced {
            if let src = rec.macrosSourceRaw { counts[src, default: 0] += 1 }
        }
        let topPair = counts.max { $0.value < $1.value }
        guard let dominant = topPair else { return nil }
        let percent = Int((Double(dominant.value) / Double(sourced.count) * 100).rounded())
        let label: String
        switch dominant.key {
        case "ai":       label = "FoodFinder AI"
        case "product":  label = "barcode/text-search products"
        case "favorite": label = "favorite foods"
        case "manual":   label = "manual entry"
        default:         label = dominant.key
        }
        return BolusProBehaviorPattern(
            id: UUID(),
            kind: .macrosSourceMix,
            summary: "Macros come from \(label) most often",
            detail: "\(percent)% of your BolusPro meals derive fat/protein from \(label).",
            mealCount: sourced.count
        )
    }

    // MARK: - Test Hooks

    #if DEBUG
    /// Wipe stored snapshots — useful for QA / development.
    func _resetForTesting() {
        UserDefaults.standard.removeObject(forKey: storeKey)
    }
    #endif
}
