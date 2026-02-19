//
//  LoopInsights_AlcoholTracker.swift
//  Loop
//
//  LoopInsights — Alcohol intake tracker with linear metabolism and hypo risk model.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine

/// Tracks alcohol intake with linear metabolism model and delayed hypoglycemia risk.
/// Entries are persisted to UserDefaults. Uses ~1 standard drink/hour linear metabolism.
/// No HealthKit integration — all entries are manual.
final class LoopInsights_AlcoholTracker: ObservableObject {

    static let shared = LoopInsights_AlcoholTracker()

    /// Linear metabolism rate: ~1 standard drink per hour
    private static let metabolismRate: Double = 1.0

    /// Delayed hypoglycemia risk window: up to 24 hours after last drink
    private static let hypoRiskWindowHours: Double = 24.0

    /// Peak hypo risk window: 8-12 hours after last intake
    private static let peakRiskStartHours: Double = 8.0
    private static let peakRiskEndHours: Double = 12.0

    /// UserDefaults key for persisted entries
    private static let storageKey = "LoopInsights_alcoholEntries"

    @Published private(set) var entries: [LoopInsightsAlcoholEntry] = []

    init() {
        loadEntries()
    }

    // MARK: - Public API

    /// Log an alcohol intake
    func logAlcohol(standardDrinks: Double, source: String, at timestamp: Date = Date()) {
        let entry = LoopInsightsAlcoholEntry(
            timestamp: timestamp,
            standardDrinks: standardDrinks,
            source: source
        )
        entries.append(entry)
        entries.sort { $0.timestamp > $1.timestamp }
        saveEntries()
    }

    /// Remove an entry
    func removeEntry(_ entry: LoopInsightsAlcoholEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    /// Remove all entries
    func clearAllEntries() {
        entries.removeAll()
        saveEntries()
    }

    /// Update an existing entry
    func updateEntry(id: UUID, standardDrinks: Double, source: String, timestamp: Date) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx] = LoopInsightsAlcoholEntry(
            id: id,
            timestamp: timestamp,
            standardDrinks: standardDrinks,
            source: source
        )
        entries.sort { $0.timestamp > $1.timestamp }
        saveEntries()
    }

    /// Current alcohol state computed from all entries using linear metabolism
    func currentState(at now: Date = Date()) -> LoopInsightsAlcoholState {
        var currentLevel: Double = 0
        var peakToday: Double = 0
        var totalLast24h: Double = 0
        var entriesLast24h = 0
        var lastIntake: Date?

        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 3600)
        let startOfToday = Calendar.current.startOfDay(for: now)

        // Sort entries chronologically for sequential metabolism simulation
        let chronological = entries.sorted { $0.timestamp < $1.timestamp }
            .filter { $0.timestamp <= now }

        // Simulate alcohol pool over time: the liver metabolizes ~1 drink/hour,
        // but only while there's alcohol in the system (pool > 0). Between each
        // entry we apply metabolism, then add the new drink to the pool.
        var pool: Double = 0
        var lastEventTime: Date?

        for entry in chronological {
            // Metabolize since last event (liver is idle when pool is empty)
            if let lastTime = lastEventTime {
                let elapsed = entry.timestamp.timeIntervalSince(lastTime) / 3600
                pool = max(0, pool - elapsed * Self.metabolismRate)
            }

            // Add this drink to the pool
            pool += entry.standardDrinks
            lastEventTime = entry.timestamp

            // Track peak today (pool is highest right after adding a drink)
            if entry.timestamp >= startOfToday {
                peakToday = max(peakToday, pool)
            }

            if entry.timestamp >= twentyFourHoursAgo {
                totalLast24h += entry.standardDrinks
                entriesLast24h += 1
            }

            if lastIntake == nil || entry.timestamp > (lastIntake ?? .distantPast) {
                lastIntake = entry.timestamp
            }
        }

        // Metabolize from last event to now
        if let lastTime = lastEventTime {
            let elapsed = now.timeIntervalSince(lastTime) / 3600
            pool = max(0, pool - elapsed * Self.metabolismRate)
        }

        currentLevel = pool

        // Estimated clear time
        var clearTime: Date?
        if currentLevel > 0 {
            let hoursToClear = currentLevel / Self.metabolismRate
            clearTime = now.addingTimeInterval(hoursToClear * 3600)
        }

        // Compute hypo risk (factors in peak level and time decay)
        let hypoRisk = computeHypoRisk(totalDrinksLast24h: totalLast24h, peakLevelToday: peakToday, currentAlcoholLevel: currentLevel, lastIntakeTime: lastIntake, at: now)

        // Hypo risk window end: 24 hours after last intake
        var riskWindowEnd: Date?
        if let lastTime = lastIntake, hypoRisk != .none {
            riskWindowEnd = lastTime.addingTimeInterval(Self.hypoRiskWindowHours * 3600)
        }

        return LoopInsightsAlcoholState(
            currentAlcoholLevel: currentLevel,
            peakLevelToday: peakToday,
            estimatedClearTime: clearTime,
            hypoRiskLevel: hypoRisk,
            hypoRiskWindowEnd: riskWindowEnd,
            totalDrinksLast24h: totalLast24h,
            entriesLast24h: entriesLast24h,
            lastIntakeTime: lastIntake
        )
    }

    // MARK: - Hypo Risk Model

    /// Compute delayed hypoglycemia risk level based on alcohol intake with time decay.
    /// Risk follows a natural arc based on hours since last drink and current alcohol level:
    ///   0–4h (active drinking/early):  base risk from amount consumed
    ///   4–8h (building):               base risk (gluconeogenesis suppression building)
    ///   8–12h (peak danger zone):      risk elevated one level
    ///   12h+ (recovery):               risk decays — faster when alcohol is fully metabolized
    private func computeHypoRisk(totalDrinksLast24h: Double, peakLevelToday: Double, currentAlcoholLevel: Double, lastIntakeTime: Date?, at now: Date) -> LoopInsightsAlcoholHypoRisk {
        guard totalDrinksLast24h > 0, let lastTime = lastIntakeTime else { return .none }

        let hoursSinceLastDrink = now.timeIntervalSince(lastTime) / 3600

        // Outside the 24-hour risk window
        guard hoursSinceLastDrink < Self.hypoRiskWindowHours else { return .none }

        let inPeakWindow = hoursSinceLastDrink >= Self.peakRiskStartHours &&
                           hoursSinceLastDrink <= Self.peakRiskEndHours
        let pastPeakWindow = hoursSinceLastDrink > Self.peakRiskEndHours
        let fullyMetabolized = currentAlcoholLevel <= 0

        // Base severity from what's actually in your system and today's session peak.
        // NOT totalDrinksLast24h — a rolling sum double-counts old metabolized sessions.
        let drinkMetric = max(currentAlcoholLevel, peakLevelToday)

        // Base risk from consumption amount
        let baseRisk: LoopInsightsAlcoholHypoRisk
        if drinkMetric >= 5 {
            baseRisk = .high
        } else if drinkMetric >= 3 {
            baseRisk = .moderate
        } else {
            baseRisk = .low
        }

        // During peak window (8-12h): elevate risk by one level
        if inPeakWindow {
            switch baseRisk {
            case .low: return .moderate
            case .moderate: return .high
            case .high: return .high
            case .none: return .none
            }
        }

        // After peak window (12h+): decay risk based on metabolism state
        if pastPeakWindow {
            // Fully metabolized + past the peak danger zone = risk cleared
            if fullyMetabolized {
                return .none
            }
            // Still metabolizing past peak — step down one level
            switch baseRisk {
            case .high: return .moderate
            case .moderate: return .low
            case .low: return .none
            case .none: return .none
            }
        }

        // Before peak window (0-8h): base risk, but if fully metabolized + low → none
        if fullyMetabolized && baseRisk == .low {
            return .none
        }

        return baseRisk
    }

    // MARK: - Prompt Context

    /// Build prompt context string for AI analysis
    func buildAlcoholPromptContext(at now: Date = Date()) -> String {
        let state = currentState(at: now)
        guard state.entriesLast24h > 0 else { return "" }

        var ctx = "## Alcohol Intake\n"
        ctx += "- Current estimated alcohol level: \(String(format: "%.1f", state.currentAlcoholLevel)) standard drinks\n"
        ctx += "- Total drinks last 24h: \(String(format: "%.1f", state.totalDrinksLast24h)) (\(state.entriesLast24h) intake(s))\n"

        if let lastTime = state.lastIntakeTime {
            let minutesAgo = Int(now.timeIntervalSince(lastTime) / 60)
            if minutesAgo < 60 {
                ctx += "- Last drink: \(minutesAgo) minutes ago\n"
            } else {
                ctx += "- Last drink: \(minutesAgo / 60)h \(minutesAgo % 60)m ago\n"
            }
        }

        if let clearTime = state.estimatedClearTime {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            ctx += "- Estimated alcohol clearance: \(formatter.string(from: clearTime))\n"
        }

        ctx += "- Delayed hypoglycemia risk: \(state.hypoRiskLevel.rawValue.uppercased())\n"

        if let riskEnd = state.hypoRiskWindowEnd {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            ctx += "- Risk window ends: \(formatter.string(from: riskEnd))\n"
        }

        if state.hypoRiskLevel == .high {
            ctx += "** HIGH ALCOHOL HYPO RISK: Significant delayed hypoglycemia risk. Gluconeogenesis suppressed. Do NOT recommend basal increases. **\n"
        } else if state.hypoRiskLevel == .moderate {
            ctx += "** MODERATE ALCOHOL HYPO RISK: Delayed hypoglycemia risk present. Consider reduced confidence in settings changes. **\n"
        }

        // List recent entries
        let recentEntries = entries.filter { $0.timestamp >= now.addingTimeInterval(-24 * 3600) }
        if !recentEntries.isEmpty {
            ctx += "- Recent entries: "
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            ctx += recentEntries.prefix(5).map { "\(formatter.string(from: $0.timestamp)) \($0.source) (\(String(format: "%.1f", $0.standardDrinks)) drinks)" }.joined(separator: "; ")
            ctx += "\n"
        }

        return ctx
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([LoopInsightsAlcoholEntry].self, from: data) else {
            entries = []
            return
        }
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        entries = decoded.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }
    }

    private func saveEntries() {
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        let pruned = entries.filter { $0.timestamp >= cutoff }
        if let data = try? JSONEncoder().encode(pruned) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
