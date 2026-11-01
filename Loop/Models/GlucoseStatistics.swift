//
//  GlucoseStatistics.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Glucose ranges for the time-in-range breakdown, using the international
/// consensus thresholds (mg/dL) shared by the AGP report:
/// very low < 54, low 54–69, target 70–180, high 181–250, very high > 250.
enum GlucoseBand: Int, CaseIterable, Comparable {
    case veryLow
    case low
    case target
    case high
    case veryHigh

    static func < (lhs: GlucoseBand, rhs: GlucoseBand) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Classify a glucose value in mg/dL into its consensus band.
    static func classify(mgdl: Double) -> GlucoseBand {
        switch mgdl {
        case ..<54:  return .veryLow
        case ..<70:  return .low
        case ..<181: return .target
        case ..<251: return .high
        default:     return .veryHigh
        }
    }
}

/// One time-of-day bucket of the ambulatory glucose profile: the 5/25/50/75/95
/// percentiles (mg/dL) of every reading that fell in this slice of the day,
/// pooled across all days in the window.
struct AGPBand: Equatable {
    /// Midpoint of the bucket, in seconds since midnight (0 ..< 86400).
    let timeOfDay: TimeInterval
    let p05: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p95: Double
}

/// Summary statistics computed over a window of glucose, modelled after the
/// standard Ambulatory Glucose Profile report. Pure value type — callers pass
/// already-filtered samples (e.g. excluding display-only / manually entered).
struct GlucoseStatistics: Equatable {
    let start: Date
    let end: Date
    let sampleCount: Int

    /// Mean glucose in mg/dL, or nil if there are no samples.
    let averageGlucose: Double?
    /// Glucose Management Indicator (estimated A1C), percent. Nil if no samples.
    let gmi: Double?
    /// Coefficient of variation (sample SD / mean × 100), percent. Nil if < 2 samples.
    let coefficientOfVariation: Double?
    /// Fraction of time (0…1) spent in each band. Time-weighted, gap-capped.
    let timeInRange: [GlucoseBand: Double]
    /// Fraction (0…1) of the window for which CGM data is present.
    let percentActive: Double
    /// Per-time-of-day percentile bands for the AGP chart, ordered by time of day.
    let agpProfile: [AGPBand]

    /// Expected CGM cadence; used for gap-capping and percent-active.
    static let assumedCadence: TimeInterval = .minutes(5)

    init(
        samples: [StoredGlucoseSample],
        start: Date,
        end: Date,
        bucketDuration: TimeInterval = .minutes(30),
        calendar: Calendar = .current
    ) {
        self.start = start
        self.end = end

        let sorted = samples
            .filter { $0.startDate >= start && $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }
        let values = sorted.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }
        self.sampleCount = values.count

        // Mean, GMI, CV
        if values.isEmpty {
            averageGlucose = nil
            gmi = nil
            coefficientOfVariation = nil
        } else {
            let mean = values.reduce(0, +) / Double(values.count)
            averageGlucose = mean
            // Consensus GMI formula (Bergenstal et al.), mean in mg/dL.
            gmi = 3.31 + 0.02392 * mean
            if values.count >= 2, mean > 0 {
                let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
                coefficientOfVariation = variance.squareRoot() / mean * 100
            } else {
                coefficientOfVariation = nil
            }
        }

        // Time-in-range: weight each reading by the time until the next reading,
        // capping each interval so an offline gap can't dominate the breakdown.
        let maxInterval = Self.assumedCadence * 2
        var durations: [GlucoseBand: TimeInterval] = [:]
        for (index, sample) in sorted.enumerated() {
            let nextDate = index + 1 < sorted.count ? sorted[index + 1].startDate : end
            let duration = min(nextDate.timeIntervalSince(sample.startDate), maxInterval)
            guard duration > 0 else { continue }
            let band = GlucoseBand.classify(mgdl: values[index])
            durations[band, default: 0] += duration
        }
        let totalDuration = durations.values.reduce(0, +)
        if totalDuration > 0 {
            timeInRange = durations.mapValues { $0 / totalDuration }
        } else {
            timeInRange = [:]
        }

        // Percent active: covered time (gap-capped) over the window length.
        let windowDuration = end.timeIntervalSince(start)
        if windowDuration > 0 {
            let covered = Double(values.count) * Self.assumedCadence
            percentActive = min(1, covered / windowDuration)
        } else {
            percentActive = 0
        }

        // AGP: pool readings into time-of-day buckets across all days, then take
        // percentiles per bucket. Skip buckets with too few readings to be useful.
        let bucketCount = max(1, Int((TimeInterval.hours(24) / bucketDuration).rounded()))
        var buckets: [[Double]] = Array(repeating: [], count: bucketCount)
        for (index, sample) in sorted.enumerated() {
            let secondsOfDay = sample.startDate.timeIntervalSince(calendar.startOfDay(for: sample.startDate))
            let bucket = min(bucketCount - 1, max(0, Int(secondsOfDay / bucketDuration)))
            buckets[bucket].append(values[index])
        }
        let minReadingsPerBucket = 3
        agpProfile = buckets.enumerated().compactMap { bucketIndex, bucketValues in
            guard bucketValues.count >= minReadingsPerBucket else { return nil }
            let v = bucketValues.sorted()
            return AGPBand(
                timeOfDay: (Double(bucketIndex) + 0.5) * bucketDuration,
                p05: Self.percentile(v, 0.05),
                p25: Self.percentile(v, 0.25),
                p50: Self.percentile(v, 0.50),
                p75: Self.percentile(v, 0.75),
                p95: Self.percentile(v, 0.95)
            )
        }
    }

    /// Linear-interpolation percentile (`quantile` in 0…1) of a pre-sorted array.
    static func percentile(_ sorted: [Double], _ quantile: Double) -> Double {
        guard let first = sorted.first else { return .nan }
        guard sorted.count > 1 else { return first }
        let position = quantile * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
