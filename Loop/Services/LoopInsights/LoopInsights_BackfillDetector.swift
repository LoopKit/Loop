//
//  LoopInsights_BackfillDetector.swift
//  Loop
//
//  LoopInsights — CGM signal gap detection and data quality tracking.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import LoopKit
import os.log

// MARK: - Models

/// A detected CGM signal gap event.
struct LoopInsightsBackfillEvent: Codable, Identifiable {
    let id: UUID
    let detectedAt: Date
    let sampleCount: Int
    let oldestSampleDate: Date
    let newestSampleDate: Date
    let maxStalenessSeconds: TimeInterval
    let gapDurationSeconds: TimeInterval

    var gapDurationMinutes: Int {
        Int(gapDurationSeconds / 60)
    }
}

/// Summary of CGM signal quality over a period.
struct LoopInsightsBackfillSummary {
    let totalEvents: Int
    let totalEstimatedSamples: Int
    let longestGapMinutes: Int
    let averageGapMinutes: Double
    let realTimeCoveragePercent: Double
    let periodDays: Int
    let longestGapEvent: LoopInsightsBackfillEvent?
}

// MARK: - BackfillDetector

/// Singleton service that detects CGM signal gaps by comparing sample timestamps
/// to wall-clock time. Surfaces banner state for the home screen and historical
/// summary for the dashboard. Persists events to JSON with 30-day retention.
final class LoopInsights_BackfillDetector: ObservableObject {

    static let shared = LoopInsights_BackfillDetector()

    private static let log = Logger(subsystem: "com.loopkit.Loop.LoopInsights", category: "BackfillDetector")

    /// Staleness threshold: if a sample's date is >6 minutes old when received, it's likely backfilled.
    private static let stalenessThreshold: TimeInterval = 360

    /// Batch span threshold: if 2+ samples span >5 minutes, the batch was likely backfilled.
    private static let batchSpanThreshold: TimeInterval = 300

    /// Auto-dismiss timer interval: 2 hours.
    private static let autoDismissInterval: TimeInterval = 7200

    /// Retention period: 30 days.
    private static let retentionDays = 30

    // MARK: - Published State

    /// Currently active gap event for the home screen banner.
    /// Set when a gap is detected, cleared after 2 hours or manual dismiss.
    @Published var recentGapEvent: LoopInsightsBackfillEvent?

    // MARK: - Private State

    private var events: [LoopInsightsBackfillEvent] = []
    private var autoDismissTimer: Timer?
    private let fileURL: URL

    // MARK: - Init

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("LoopInsights_BackfillEvents.json")
        loadEvents()
        pruneStaleEvents()
    }

    // MARK: - Detection

    /// Evaluate incoming CGM samples for backfill characteristics.
    /// Called from DeviceDataManager.processCGMReadingResult on each `.newData` batch.
    /// This method is purely observational — it does not modify the samples.
    func evaluateSamples(_ samples: [NewGlucoseSample], receivedAt: Date = Date()) {
        guard LoopInsights_FeatureFlags.cgmBackfillDetectionEnabled else { return }
        guard !samples.isEmpty else { return }

        let now = receivedAt

        // Check individual sample staleness
        let staleSamples = samples.filter { now.timeIntervalSince($0.date) > Self.stalenessThreshold }

        // Check batch span (oldest to newest)
        let sortedByDate = samples.sorted { $0.date < $1.date }
        let batchSpan = sortedByDate.last!.date.timeIntervalSince(sortedByDate.first!.date)
        let isBatchBackfill = samples.count >= 2 && batchSpan > Self.batchSpanThreshold

        guard !staleSamples.isEmpty || isBatchBackfill else { return }

        // Determine gap characteristics
        let oldestDate = sortedByDate.first!.date
        let newestDate = sortedByDate.last!.date
        let maxStaleness = now.timeIntervalSince(oldestDate)
        let gapDuration = max(maxStaleness, batchSpan)
        let affectedCount = staleSamples.isEmpty ? samples.count : staleSamples.count

        let event = LoopInsightsBackfillEvent(
            id: UUID(),
            detectedAt: now,
            sampleCount: affectedCount,
            oldestSampleDate: oldestDate,
            newestSampleDate: newestDate,
            maxStalenessSeconds: maxStaleness,
            gapDurationSeconds: gapDuration
        )

        Self.log.info("CGM signal gap detected: \(event.gapDurationMinutes) min, \(affectedCount) estimated readings")

        events.append(event)
        saveEventsAsync()

        DispatchQueue.main.async { [weak self] in
            self?.recentGapEvent = event
            self?.scheduleAutoDismiss()
        }
    }

    // MARK: - Banner

    /// Dismiss the home screen banner.
    func dismissBanner() {
        DispatchQueue.main.async { [weak self] in
            self?.recentGapEvent = nil
            self?.autoDismissTimer?.invalidate()
            self?.autoDismissTimer = nil
        }
    }

    private func scheduleAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: Self.autoDismissInterval, repeats: false) { [weak self] _ in
            self?.dismissBanner()
        }
    }

    // MARK: - Summary

    /// Build a summary of CGM signal quality for the given period.
    func buildSummary(days: Int) -> LoopInsightsBackfillSummary {
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 86400)
        let periodEvents = events.filter { $0.detectedAt >= cutoff }

        let totalSamples = periodEvents.reduce(0) { $0 + $1.sampleCount }
        let longestEvent = periodEvents.max(by: { $0.gapDurationSeconds < $1.gapDurationSeconds })
        let longestMinutes = longestEvent?.gapDurationMinutes ?? 0
        let avgMinutes = periodEvents.isEmpty ? 0.0 :
            periodEvents.reduce(0.0) { $0 + $1.gapDurationSeconds / 60 } / Double(periodEvents.count)

        // Calculate real-time coverage: (total minutes in period - total gap minutes) / total minutes
        let totalMinutesInPeriod = Double(days) * 24 * 60
        let totalGapMinutes = periodEvents.reduce(0.0) { $0 + $1.gapDurationSeconds / 60 }
        let coverage = totalMinutesInPeriod > 0
            ? max(0, min(100, ((totalMinutesInPeriod - totalGapMinutes) / totalMinutesInPeriod) * 100))
            : 100

        return LoopInsightsBackfillSummary(
            totalEvents: periodEvents.count,
            totalEstimatedSamples: totalSamples,
            longestGapMinutes: longestMinutes,
            averageGapMinutes: avgMinutes,
            realTimeCoveragePercent: coverage,
            periodDays: days,
            longestGapEvent: longestEvent
        )
    }

    /// Build prompt context string for AI chatbot enrichment.
    func buildBackfillPromptContext(days: Int) -> String {
        let summary = buildSummary(days: days)
        guard summary.totalEvents > 0 else { return "" }

        var lines: [String] = ["CGM SIGNAL QUALITY (\(days)-day):"]
        lines.append("  Signal gaps detected: \(summary.totalEvents)")
        lines.append("  Total estimated readings: \(summary.totalEstimatedSamples)")
        lines.append("  Longest gap: \(summary.longestGapMinutes) min")
        if summary.totalEvents > 1 {
            lines.append("  Average gap: \(String(format: "%.0f", summary.averageGapMinutes)) min")
        }
        lines.append("  Real-time coverage: \(String(format: "%.1f", summary.realTimeCoveragePercent))%")

        // Detail recent events (last 5) with timestamps
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 86400)
        let recentEvents = events
            .filter { $0.detectedAt >= cutoff }
            .sorted { $0.detectedAt > $1.detectedAt }
            .prefix(5)

        if !recentEvents.isEmpty {
            lines.append("  Recent gaps:")
            for event in recentEvents {
                lines.append("    \(formatter.string(from: event.detectedAt)): \(event.gapDurationMinutes) min gap, \(event.sampleCount) estimated readings")
            }
        }

        lines.append("  Note: During signal gaps, CGM readings may be estimated/interpolated by the sensor and less reliable than real-time data. Apparent flatlines or smooth curves during gaps may not reflect actual glucose movement.")

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func loadEvents() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            events = try JSONDecoder().decode([LoopInsightsBackfillEvent].self, from: data)
        } catch {
            Self.log.error("Failed to load backfill events: \(error)")
        }
    }

    private func saveEventsAsync() {
        let eventsToSave = self.events
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(eventsToSave)
                try data.write(to: url, options: .atomic)
            } catch {
                Self.log.error("Failed to save backfill events: \(error)")
            }
        }
    }

    private func pruneStaleEvents() {
        let cutoff = Date().addingTimeInterval(-TimeInterval(Self.retentionDays) * 86400)
        let before = self.events.count
        self.events.removeAll { $0.detectedAt < cutoff }
        if self.events.count != before {
            Self.log.info("Pruned \(before - self.events.count) stale backfill events")
            saveEventsAsync()
        }
    }
}
