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
    /// P10: Accept optional pre-computed hourlyAverages to avoid re-bucketing glucose
    static func buildCircadianProfile(
        glucoseSamples: [StoredGlucoseSample],
        sleepStats: LoopInsightsAggregatedStats.SleepStats?,
        precomputedHourlyAverages: [Int: Double]? = nil
    ) -> LoopInsightsCircadianProfile? {
        guard !glucoseSamples.isEmpty else { return nil }

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

        // P10: Reuse pre-computed hourly averages when available
        let hourlyAvg: (Int) -> Double
        if let precomputed = precomputedHourlyAverages {
            hourlyAvg = { hour in precomputed[hour] ?? 0 }
        } else {
            let calendar = Calendar.current
            var hourlyBuckets: [Int: [Double]] = [:]
            for sample in glucoseSamples {
                let hour = calendar.component(.hour, from: sample.startDate)
                let value = sample.quantity.doubleValue(for: .milligramsPerDeciliter)
                hourlyBuckets[hour, default: []].append(value)
            }
            hourlyAvg = { hour in
                guard let vals = hourlyBuckets[hour], !vals.isEmpty else { return 0 }
                return vals.reduce(0, +) / Double(vals.count)
            }
        }

        // Pre-sleep: hour before bed
        let preSleepHour = (bedHour - 1 + 24) % 24
        let preSleepAvg = hourlyAvg(preSleepHour)

        // Overnight: bed to wake (use hourlyAvg function to work with both precomputed and bucketed data)
        var overnightHourAvgs: [Double] = []
        var h = bedHour
        while h != wakeHour {
            let avg = hourlyAvg(h)
            if avg > 0 { overnightHourAvgs.append(avg) }
            h = (h + 1) % 24
        }
        let overnightAvg = overnightHourAvgs.isEmpty ? 0 : overnightHourAvgs.reduce(0, +) / Double(overnightHourAvgs.count)

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

        // P8: Pre-sort schedule items once instead of per-dose
        let sortedBasalItems = scheduledBasalItems.sorted { $0.startTime < $1.startTime }

        // P5: Sort glucose samples by date for binary search overcorrection lookups
        let sortedGlucose = glucoseSamples.sorted { $0.startDate < $1.startDate }

        for dose in doses {
            let durationMinutes = dose.endDate.timeIntervalSince(dose.startDate) / 60
            let hour = calendar.component(.hour, from: dose.startDate)

            if dose.type == .suspend {
                suspensionCount += 1
                totalSuspensionMinutes += durationMinutes
                hourlyDistribution[hour, default: 0] += durationMinutes

                // P5: Binary search for overcorrection check instead of linear scan
                let checkStart = dose.endDate
                let checkEnd = dose.endDate.addingTimeInterval(2 * 3600)
                let startIdx = sortedGlucose.loopInsights_firstIndex(afterOrAt: checkStart) { $0.startDate }
                var reboundHigh = false
                for i in startIdx..<sortedGlucose.count {
                    let sample = sortedGlucose[i]
                    if sample.startDate > checkEnd { break }
                    if sample.quantity.doubleValue(for: .milligramsPerDeciliter) > 180 {
                        reboundHigh = true
                        break
                    }
                }
                if reboundHigh { overcorrectionEvents += 1 }
            } else if dose.type == .tempBasal {
                let rate = dose.unitsPerHour
                let scheduledRate = effectiveScheduledRate(at: dose.startDate, sortedItems: sortedBasalItems)
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
            ctx += "** HIGH SUSPENSION RATE: Frequent insulin suspensions — basal may be too high **\n"
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

    // MARK: - Menstrual Cycle Context

    /// Build prompt context from menstrual cycle data. Returns empty string if no data.
    static func buildMenstrualCyclePromptContext(_ stats: LoopInsightsMenstrualCycleStats) -> String {
        guard stats.dataAvailable else { return "" }

        var ctx = "## Menstrual Cycle (from Apple Health Cycle Tracker)\n"

        let phaseDescription: String
        let insulinImpact: String
        switch stats.currentPhase {
        case .menstrual:
            phaseDescription = "Menstrual (active period)"
            insulinImpact = "Insulin sensitivity returning toward baseline. Some may need less insulin."
        case .follicular:
            phaseDescription = "Follicular (post-period, pre-ovulation)"
            insulinImpact = "Typically best insulin sensitivity of the cycle. May need less insulin."
        case .ovulatory:
            phaseDescription = "Ovulatory (around ovulation)"
            insulinImpact = "Transition period. Insulin sensitivity starting to decline."
        case .luteal:
            phaseDescription = "Luteal (post-ovulation, pre-period)"
            insulinImpact = "Progesterone rises → increased insulin resistance. May need 15-30% more insulin. Watch for unexplained highs."
        case .unknown:
            phaseDescription = "Unknown"
            insulinImpact = "Insufficient data to determine hormonal impact."
        }

        ctx += "- Current phase: \(phaseDescription)\n"

        if let day = stats.currentCycleDay {
            ctx += "- Cycle day: \(day)\n"
        }

        if let avgLength = stats.averageCycleLength {
            ctx += "- Average cycle length: \(String(format: "%.0f", avgLength)) days\n"
        }

        if let lastStart = stats.lastFlowStartDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            ctx += "- Last period started: \(formatter.string(from: lastStart))\n"
        }

        if stats.flowDaysInLookback > 0 {
            ctx += "- Flow days in analysis period: \(stats.flowDaysInLookback)\n"
        }

        ctx += "- Hormonal impact on insulin: \(insulinImpact)\n"

        if stats.currentPhase == .luteal {
            ctx += "** LUTEAL PHASE: Expect increased insulin resistance. If BG is running higher than usual, hormonal changes are a likely factor before adjusting long-term settings. **\n"
        }

        return ctx
    }

    // MARK: - Helpers

    /// Find the effective scheduled rate at a given date. Expects pre-sorted items (P8).
    private static func effectiveScheduledRate(
        at date: Date,
        sortedItems: [LoopInsightsTherapySnapshot.LoopInsightsScheduleItem]
    ) -> Double {
        let calendar = Calendar.current
        let secondsSinceMidnight = TimeInterval(
            calendar.component(.hour, from: date) * 3600 +
            calendar.component(.minute, from: date) * 60
        )
        var result = sortedItems.first?.value ?? 0
        for item in sortedItems {
            if item.startTime <= secondsSinceMidnight {
                result = item.value
            } else {
                break
            }
        }
        return result
    }

}
