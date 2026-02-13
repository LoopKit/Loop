//
//  LoopInsights_Phase5Models.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Circadian Profile

/// 24-hour circadian glucose profile derived from sleep/wake data and glucose patterns
struct LoopInsightsCircadianProfile: Codable {
    let preSleepAvgGlucose: Double       // mg/dL — avg glucose in hour before bed
    let overnightAvgGlucose: Double      // mg/dL — avg glucose during sleep
    let wakeGlucose: Double              // mg/dL — avg glucose at wake time
    let riseAfterWake: Double            // mg/dL — glucose rise in first 2h after wake
    let dawnRiseDetected: Bool           // True if significant rise before wake
    let dawnRiseMagnitude: Double        // mg/dL — magnitude of pre-wake rise
    let estimatedWakeHour: Int           // Hour (0-23) from sleep data or fallback
    let estimatedBedHour: Int            // Hour (0-23) from sleep data or fallback
    let hourlyGlucoseRelativeToWake: [Int: Double]  // hours-from-wake → avg glucose
}

// MARK: - Food Response Pattern

/// Per-food-type glucose response statistics
struct LoopInsightsFoodResponsePattern: Identifiable, Codable {
    let id: UUID
    let foodType: String                 // e.g. "Pizza", "Rice", "Bread"
    let mealCount: Int                   // Number of meals analyzed
    let averageCarbsPerMeal: Double      // grams
    let peakGlucoseRise: Double          // mg/dL — avg max rise above pre-meal
    let timeToPeakMinutes: Double        // Minutes from meal to peak
    let averageResponseAUC: Double       // Area under the curve (mg/dL * hours)
    let twoHourPostMealAvg: Double       // mg/dL — avg glucose 2h post-meal
    let fourHourPostMealAvg: Double      // mg/dL — avg glucose 4h post-meal

    init(foodType: String, mealCount: Int, averageCarbsPerMeal: Double,
         peakGlucoseRise: Double, timeToPeakMinutes: Double,
         averageResponseAUC: Double, twoHourPostMealAvg: Double,
         fourHourPostMealAvg: Double) {
        self.id = UUID()
        self.foodType = foodType
        self.mealCount = mealCount
        self.averageCarbsPerMeal = averageCarbsPerMeal
        self.peakGlucoseRise = peakGlucoseRise
        self.timeToPeakMinutes = timeToPeakMinutes
        self.averageResponseAUC = averageResponseAUC
        self.twoHourPostMealAvg = twoHourPostMealAvg
        self.fourHourPostMealAvg = fourHourPostMealAvg
    }
}

/// A single meal event with matched glucose response for debrief
struct LoopInsightsMealEvent: Identifiable {
    let id: UUID
    let date: Date
    let foodType: String
    let carbs: Double                    // grams
    let preMealGlucose: Double           // mg/dL
    let peakGlucose: Double              // mg/dL
    let twoHourGlucose: Double           // mg/dL
    let glucoseTimeline: [(minutesAfter: Int, glucose: Double)]

    init(date: Date, foodType: String, carbs: Double, preMealGlucose: Double,
         peakGlucose: Double, twoHourGlucose: Double,
         glucoseTimeline: [(minutesAfter: Int, glucose: Double)]) {
        self.id = UUID()
        self.date = date
        self.foodType = foodType
        self.carbs = carbs
        self.preMealGlucose = preMealGlucose
        self.peakGlucose = peakGlucose
        self.twoHourGlucose = twoHourGlucose
        self.glucoseTimeline = glucoseTimeline
    }
}

// MARK: - Negative Basal Stats

/// Statistics about insulin suspension and sub-scheduled-rate delivery
struct LoopInsightsNegativeBasalStats: Codable {
    let suspensionCount: Int             // Number of suspend events
    let totalSuspensionMinutes: Double   // Total minutes of zero delivery
    let suspensionPercentage: Double     // % of total time spent suspended
    let subBasalMinutes: Double          // Minutes at rate < scheduled
    let hourlyDistribution: [Int: Double] // hour → minutes of neg basal at that hour
    let overcorrectionEvents: Int        // Suspensions followed by rebound high >180
}

// MARK: - Stress Score

/// HRV-derived stress score with glucose correlation
struct LoopInsightsStressScore: Codable {
    let overallScore: Double             // 0-100 (0=relaxed, 100=high stress)
    let hourlyScores: [Int: Double]      // hour → stress score
    let glucoseCVCorrelation: Double     // Correlation coefficient with glucose CV
    let averageSDNN: Double              // ms — average HRV SDNN for reference
    let highStressHours: [Int]           // Hours where stress > 70
}

// MARK: - Caffeine

/// A single caffeine intake entry
struct LoopInsightsCaffeineEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let milligrams: Double
    let source: String                   // e.g. "Espresso", "Coffee (Medium)"
    let isFromHealthKit: Bool

    init(id: UUID = UUID(), timestamp: Date, milligrams: Double, source: String, isFromHealthKit: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.milligrams = milligrams
        self.source = source
        self.isFromHealthKit = isFromHealthKit
    }
}

/// Current caffeine state computed from entries with half-life decay
struct LoopInsightsCaffeineState: Codable {
    let currentLevelMg: Double           // Current caffeine level in mg
    let peakLevelToday: Double           // Highest level today
    let lastIntakeTime: Date?            // When the last caffeine was consumed
    let entriesLast24h: Int              // Number of entries in last 24h
    let totalMgLast24h: Double           // Total mg consumed in last 24h
}

/// Caffeine preset for quick-add
struct LoopInsightsCaffeinePreset: Identifiable {
    let id = UUID()
    let name: String
    let milligrams: Double
    let icon: String                     // SF Symbol name

    static let defaults: [LoopInsightsCaffeinePreset] = [
        LoopInsightsCaffeinePreset(name: "Espresso", milligrams: 63, icon: "cup.and.saucer.fill"),
        LoopInsightsCaffeinePreset(name: "Coffee (Small)", milligrams: 95, icon: "cup.and.saucer.fill"),
        LoopInsightsCaffeinePreset(name: "Coffee (Medium)", milligrams: 142, icon: "cup.and.saucer.fill"),
        LoopInsightsCaffeinePreset(name: "Coffee (Large)", milligrams: 190, icon: "cup.and.saucer.fill"),
        LoopInsightsCaffeinePreset(name: "Tea (Green)", milligrams: 28, icon: "leaf.fill"),
        LoopInsightsCaffeinePreset(name: "Tea (Black)", milligrams: 47, icon: "leaf.fill"),
        LoopInsightsCaffeinePreset(name: "Energy Drink", milligrams: 80, icon: "bolt.fill"),
        LoopInsightsCaffeinePreset(name: "Cola", milligrams: 34, icon: "drop.fill"),
    ]
}

// MARK: - Nightscout

/// Nightscout server configuration
struct LoopInsightsNightscoutConfig: Codable, Equatable {
    var siteURL: String
    var apiSecret: String
    var isConnected: Bool

    init(siteURL: String = "", apiSecret: String = "", isConnected: Bool = false) {
        self.siteURL = siteURL
        self.apiSecret = apiSecret
        self.isConnected = isConnected
    }

    static let storageKey = "LoopInsights_nightscoutConfig"

    static func load() -> LoopInsightsNightscoutConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(LoopInsightsNightscoutConfig.self, from: data) else {
            return LoopInsightsNightscoutConfig()
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// A single Nightscout SGV entry (from /api/v1/entries.json)
struct LoopInsightsNightscoutEntry: Codable {
    let sgv: Double          // mg/dL
    let dateString: String?  // ISO date
    let date: Double?        // epoch ms
    let direction: String?   // Trend direction

    var sampleDate: Date? {
        if let dateStr = dateString {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: dateStr) { return d }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateStr)
        }
        if let epoch = date {
            return Date(timeIntervalSince1970: epoch / 1000)
        }
        return nil
    }
}

/// A single Nightscout treatment (from /api/v1/treatments.json)
struct LoopInsightsNightscoutTreatment: Codable {
    let eventType: String?
    let created_at: String?
    let carbs: Double?
    let insulin: Double?
    let rate: Double?        // Temp basal rate
    let duration: Double?    // Duration in minutes

    var treatmentDate: Date? {
        guard let dateStr = created_at else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: dateStr) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateStr)
    }
}

// MARK: - AGP Data Point

/// A single time point in an Ambulatory Glucose Profile
struct LoopInsightsAGPDataPoint {
    let minuteOfDay: Int     // 0-1439
    let p10: Double          // 10th percentile mg/dL
    let p25: Double          // 25th percentile mg/dL
    let p50: Double          // 50th (median) mg/dL
    let p75: Double          // 75th percentile mg/dL
    let p90: Double          // 90th percentile mg/dL
}
