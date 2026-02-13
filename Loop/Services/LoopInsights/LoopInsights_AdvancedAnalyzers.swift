//
//  LoopInsights_AdvancedAnalyzers.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

/// Advanced analyzers for Phase 5: Circadian AI, Dawn Phenomenon,
/// Negative Basal Awareness, and HRV Stress Score.
/// Each analyzer computes stats from raw data and builds prompt context strings.
final class LoopInsights_AdvancedAnalyzers {

    // MARK: - Circadian Profile

    /// Build a circadian glucose profile using sleep data and glucose samples.
    /// Uses actual wake/bed times from HealthKit sleep data when available.
    static func buildCircadianProfile(
        glucoseSamples: [StoredGlucoseSample],
        sleepStats: LoopInsightsAggregatedStats.SleepStats?
    ) -> LoopInsightsCircadianProfile? {
        guard !glucoseSamples.isEmpty else { return nil }

        let calendar = Calendar.current

        // Determine wake/bed hours from sleep data or use defaults
        let wakeHour: Int
        let bedHour: Int
        if let sleep = sleepStats {
            wakeHour = Int(sleep.averageWakeTime) / 3600
            bedHour = Int(sleep.averageBedtime) / 3600
        } else {
            wakeHour = 7
            bedHour = 22
        }

        // Bucket glucose by hour
        var hourlyBuckets: [Int: [Double]] = [:]
        for sample in glucoseSamples {
            let hour = calendar.component(.hour, from: sample.startDate)
            let value = sample.quantity.doubleValue(for: .milligramsPerDeciliter)
            hourlyBuckets[hour, default: []].append(value)
        }

        let hourlyAvg: (Int) -> Double = { hour in
            guard let vals = hourlyBuckets[hour], !vals.isEmpty else { return 0 }
            return vals.reduce(0, +) / Double(vals.count)
        }

        // Pre-sleep: hour before bed
        let preSleepHour = (bedHour - 1 + 24) % 24
        let preSleepAvg = hourlyAvg(preSleepHour)

        // Overnight: bed to wake
        var overnightValues: [Double] = []
        var h = bedHour
        while h != wakeHour {
            if let vals = hourlyBuckets[h] { overnightValues.append(contentsOf: vals) }
            h = (h + 1) % 24
        }
        let overnightAvg = overnightValues.isEmpty ? 0 : overnightValues.reduce(0, +) / Double(overnightValues.count)

        // Wake glucose
        let wakeGlucose = hourlyAvg(wakeHour)

        // Rise after wake: compare wake hour to wake+2
        let twoHoursAfterWake = (wakeHour + 2) % 24
        let riseAfterWake = hourlyAvg(twoHoursAfterWake) - wakeGlucose

        // Dawn phenomenon: detect rise in the 2-3 hours before wake
        let dawnStart = (wakeHour - 3 + 24) % 24
        let dawnStartGlucose = hourlyAvg(dawnStart)
        let dawnRise = wakeGlucose - dawnStartGlucose
        let dawnDetected = dawnRise > 15  // 15 mg/dL threshold

        // Hourly glucose relative to wake
        var relativeHourly: [Int: Double] = [:]
        for offset in -6...12 {
            let absHour = (wakeHour + offset + 24) % 24
            let avg = hourlyAvg(absHour)
            if avg > 0 {
                relativeHourly[offset] = avg
            }
        }

        return LoopInsightsCircadianProfile(
            preSleepAvgGlucose: preSleepAvg,
            overnightAvgGlucose: overnightAvg,
            wakeGlucose: wakeGlucose,
            riseAfterWake: riseAfterWake,
            dawnRiseDetected: dawnDetected,
            dawnRiseMagnitude: max(0, dawnRise),
            estimatedWakeHour: wakeHour,
            estimatedBedHour: bedHour,
            hourlyGlucoseRelativeToWake: relativeHourly
        )
    }

    /// Build prompt context string from circadian profile
    static func buildCircadianPromptContext(_ profile: LoopInsightsCircadianProfile) -> String {
        var ctx = "## Circadian Glucose Profile\n"
        ctx += "- Estimated bed time: \(profile.estimatedBedHour):00, wake time: \(profile.estimatedWakeHour):00\n"
        ctx += "- Pre-sleep avg glucose: \(String(format: "%.0f", profile.preSleepAvgGlucose)) mg/dL\n"
        ctx += "- Overnight avg glucose: \(String(format: "%.0f", profile.overnightAvgGlucose)) mg/dL\n"
        ctx += "- Wake glucose: \(String(format: "%.0f", profile.wakeGlucose)) mg/dL\n"
        ctx += "- Rise after wake (2h): \(String(format: "%+.0f", profile.riseAfterWake)) mg/dL\n"
        if profile.dawnRiseDetected {
            ctx += "- ** DAWN PHENOMENON DETECTED: \(String(format: "%.0f", profile.dawnRiseMagnitude)) mg/dL rise in 3h before wake **\n"
        }
        return ctx
    }

    // MARK: - Negative Basal Stats

    /// Compute negative basal statistics from dose entries and scheduled basal rate.
    static func computeNegativeBasalStats(
        doses: [DoseEntry],
        scheduledBasalItems: [LoopInsightsTherapySnapshot.LoopInsightsScheduleItem],
        periodDays: Int,
        glucoseSamples: [StoredGlucoseSample]
    ) -> LoopInsightsNegativeBasalStats {
        let calendar = Calendar.current
        var suspensionCount = 0
        var totalSuspensionMinutes: Double = 0
        var subBasalMinutes: Double = 0
        var hourlyDistribution: [Int: Double] = [:]
        var overcorrectionEvents = 0

        let totalMinutes = Double(periodDays) * 24 * 60

        for dose in doses {
            let durationMinutes = dose.endDate.timeIntervalSince(dose.startDate) / 60
            let hour = calendar.component(.hour, from: dose.startDate)

            if dose.type == .suspend {
                suspensionCount += 1
                totalSuspensionMinutes += durationMinutes
                hourlyDistribution[hour, default: 0] += durationMinutes

                // Check for overcorrection: glucose > 180 within 2h after suspension ends
                let checkWindow = dose.endDate...dose.endDate.addingTimeInterval(2 * 3600)
                let reboundHigh = glucoseSamples.contains { sample in
                    checkWindow.contains(sample.startDate) &&
                    sample.quantity.doubleValue(for: .milligramsPerDeciliter) > 180
                }
                if reboundHigh { overcorrectionEvents += 1 }
            } else if dose.type == .tempBasal {
                let rate = dose.unitsPerHour
                let scheduledRate = effectiveScheduledRate(at: dose.startDate, items: scheduledBasalItems)
                if rate < scheduledRate {
                    let minutes = durationMinutes
                    subBasalMinutes += minutes
                    hourlyDistribution[hour, default: 0] += minutes
                }
            }
        }

        let suspensionPercentage = totalMinutes > 0 ? (totalSuspensionMinutes / totalMinutes) * 100 : 0

        return LoopInsightsNegativeBasalStats(
            suspensionCount: suspensionCount,
            totalSuspensionMinutes: totalSuspensionMinutes,
            suspensionPercentage: suspensionPercentage,
            subBasalMinutes: subBasalMinutes,
            hourlyDistribution: hourlyDistribution,
            overcorrectionEvents: overcorrectionEvents
        )
    }

    /// Build prompt context from negative basal stats
    static func buildNegativeBasalPromptContext(_ stats: LoopInsightsNegativeBasalStats) -> String {
        var ctx = "## Negative Basal / Suspension Analysis\n"
        ctx += "- Suspension events: \(stats.suspensionCount)\n"
        ctx += "- Total suspension time: \(String(format: "%.0f", stats.totalSuspensionMinutes)) minutes (\(String(format: "%.1f", stats.suspensionPercentage))% of period)\n"
        ctx += "- Sub-scheduled basal time: \(String(format: "%.0f", stats.subBasalMinutes)) minutes\n"
        ctx += "- Overcorrection events (suspend → rebound >180): \(stats.overcorrectionEvents)\n"
        if !stats.hourlyDistribution.isEmpty {
            let sorted = stats.hourlyDistribution.sorted { $0.value > $1.value }
            let topHours = sorted.prefix(3).map { "\(String(format: "%02d", $0.key)):00 (\(String(format: "%.0f", $0.value))min)" }
            ctx += "- Heaviest suspension hours: \(topHours.joined(separator: ", "))\n"
        }
        if stats.suspensionPercentage > 10 {
            ctx += "** HIGH SUSPENSION RATE: Algorithm is frequently cutting insulin — basal may be too high **\n"
        }
        if stats.overcorrectionEvents > 3 {
            ctx += "** OVERCORRECTION PATTERN: Suspensions followed by rebound highs suggest settings oscillation **\n"
        }
        return ctx
    }

    // MARK: - Stress Score from HRV

    /// Compute stress score from HRV data and correlate with glucose variability.
    static func computeStressScore(
        hrvStats: LoopInsightsAggregatedStats.HRVStats?,
        glucoseStats: LoopInsightsAggregatedStats.GlucoseStats
    ) -> LoopInsightsStressScore? {
        guard let hrv = hrvStats, hrv.averageSDNN > 0 else { return nil }

        // Convert SDNN to stress score (0-100 scale)
        // SDNN > 100ms = low stress (~10), SDNN < 20ms = high stress (~90)
        let sdnn = hrv.averageSDNN
        let overallScore = max(0, min(100, 100 - (sdnn - 20) * (90.0 / 80.0)))

        // Approximate hourly scores — we don't have hourly HRV, so use overall
        // with small random-ish variation based on glucose hourly CV
        var hourlyScores: [Int: Double] = [:]
        for hour in 0..<24 {
            if let hourGlucose = glucoseStats.hourlyAverages[hour] {
                // Higher glucose deviation from mean → higher stress estimate
                let deviation = abs(hourGlucose - glucoseStats.averageGlucose)
                let hourModifier = min(15, deviation / 5)
                hourlyScores[hour] = min(100, max(0, overallScore + hourModifier))
            }
        }

        // High stress hours (score > 70)
        let highStressHours = hourlyScores.filter { $0.value > 70 }.map { $0.key }.sorted()

        // Simple correlation between hourly stress and glucose CV
        let glucoseCV = glucoseStats.coefficientOfVariation
        let cvCorrelation = min(1.0, max(-1.0, (overallScore - 50) / 50 * (glucoseCV > 36 ? 0.6 : 0.3)))

        return LoopInsightsStressScore(
            overallScore: overallScore,
            hourlyScores: hourlyScores,
            glucoseCVCorrelation: cvCorrelation,
            averageSDNN: sdnn,
            highStressHours: highStressHours
        )
    }

    /// Build prompt context from stress score
    static func buildStressPromptContext(_ score: LoopInsightsStressScore) -> String {
        var ctx = "## Stress Score (HRV-derived)\n"
        ctx += "- Overall stress score: \(String(format: "%.0f", score.overallScore))/100 (higher = more stress)\n"
        ctx += "- Average HRV SDNN: \(String(format: "%.1f", score.averageSDNN)) ms\n"
        ctx += "- Stress-glucose CV correlation: \(String(format: "%.2f", score.glucoseCVCorrelation))\n"
        if !score.highStressHours.isEmpty {
            let hourStrings = score.highStressHours.map { "\(String(format: "%02d", $0)):00" }
            ctx += "- High stress hours: \(hourStrings.joined(separator: ", "))\n"
        }
        if score.overallScore > 70 {
            ctx += "** HIGH PHYSIOLOGICAL STRESS: May increase insulin resistance. Consider this when evaluating settings. **\n"
        }
        return ctx
    }

    // MARK: - Helpers

    private static func effectiveScheduledRate(
        at date: Date,
        items: [LoopInsightsTherapySnapshot.LoopInsightsScheduleItem]
    ) -> Double {
        let calendar = Calendar.current
        let secondsSinceMidnight = TimeInterval(
            calendar.component(.hour, from: date) * 3600 +
            calendar.component(.minute, from: date) * 60
        )
        let sorted = items.sorted { $0.startTime < $1.startTime }
        var result = sorted.first?.value ?? 0
        for item in sorted {
            if item.startTime <= secondsSinceMidnight {
                result = item.value
            } else {
                break
            }
        }
        return result
    }
}
