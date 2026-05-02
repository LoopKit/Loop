//
//  LoopInsights_CaregiverDigestService.swift
//  Loop
//
//  LoopInsights — Caregiver / Family Digest generator and scheduler.
//  Generates shareable daily or weekly summaries for caregivers and family members.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine

/// Manages caregiver digest generation, scheduling, and delivery.
final class LoopInsights_CaregiverDigestService: ObservableObject {

    // MARK: - Published State

    @Published var isGenerating = false
    @Published var lastGeneratedDigest: DigestContent?
    @Published var lastSentDate: Date?

    // MARK: - Types

    enum DigestFrequency: String, CaseIterable, Identifiable {
        case daily = "daily"
        case weekly = "weekly"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .daily: return NSLocalizedString("Daily", comment: "Caregiver digest frequency: daily")
            case .weekly: return NSLocalizedString("Weekly", comment: "Caregiver digest frequency: weekly")
            }
        }

        var period: LoopInsightsAnalysisPeriod {
            switch self {
            case .daily: return .threeDays
            case .weekly: return .sevenDays
            }
        }

        var periodLabel: String {
            switch self {
            case .daily: return NSLocalizedString("Last 24 Hours", comment: "Caregiver digest daily period")
            case .weekly: return NSLocalizedString("Last 7 Days", comment: "Caregiver digest weekly period")
            }
        }
    }

    struct DigestContent {
        let subject: String
        let plainText: String
        let htmlBody: String
        let generatedAt: Date
        let frequency: DigestFrequency
    }

    enum DeliveryMethod: String, CaseIterable, Identifiable {
        case email = "email"
        case iMessage = "imessage"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .email: return NSLocalizedString("Email", comment: "Caregiver digest delivery: email")
            case .iMessage: return NSLocalizedString("iMessage / SMS", comment: "Caregiver digest delivery: iMessage")
            }
        }

        var iconName: String {
            switch self {
            case .email: return "envelope.fill"
            case .iMessage: return "message.fill"
            }
        }
    }

    // MARK: - UserDefaults Keys

    private static let enabledKey = "LoopInsights_caregiverDigestEnabled"
    private static let frequencyKey = "LoopInsights_caregiverDigestFrequency"
    private static let recipientNameKey = "LoopInsights_caregiverRecipientName"
    private static let recipientContactKey = "LoopInsights_caregiverRecipientContact"
    private static let deliveryMethodKey = "LoopInsights_caregiverDeliveryMethod"
    private static let lastSentKey = "LoopInsights_caregiverLastSent"

    // MARK: - Settings

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var frequency: DigestFrequency {
        get {
            guard let raw = UserDefaults.standard.string(forKey: frequencyKey),
                  let freq = DigestFrequency(rawValue: raw) else { return .daily }
            return freq
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: frequencyKey) }
    }

    static var recipientName: String {
        get { UserDefaults.standard.string(forKey: recipientNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: recipientNameKey) }
    }

    /// Email address or phone number for the recipient.
    static var recipientContact: String {
        get { UserDefaults.standard.string(forKey: recipientContactKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: recipientContactKey) }
    }

    static var deliveryMethod: DeliveryMethod {
        get {
            guard let raw = UserDefaults.standard.string(forKey: deliveryMethodKey),
                  let method = DeliveryMethod(rawValue: raw) else { return .email }
            return method
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: deliveryMethodKey) }
    }

    static var lastSentDate: Date? {
        get { UserDefaults.standard.object(forKey: lastSentKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSentKey) }
    }

    // MARK: - Digest Generation

    /// Generate a digest from current LoopInsights data.
    func generateDigest(
        using aggregator: LoopInsights_DataAggregator,
        frequency: DigestFrequency
    ) async -> DigestContent? {
        await MainActor.run { isGenerating = true }

        do {
            let stats = try await aggregator.aggregateData(period: frequency.period)
            let content = Self.buildDigest(from: stats, frequency: frequency)

            await MainActor.run {
                self.lastGeneratedDigest = content
                self.isGenerating = false
            }
            return content
        } catch {
            LoopInsights_FeatureFlags.log.error("Caregiver digest generation failed: \(error)")
            await MainActor.run { self.isGenerating = false }
            return nil
        }
    }

    /// Mark that a digest was sent.
    func markSent() {
        let now = Date()
        Self.lastSentDate = now
        lastSentDate = now
    }

    // MARK: - Content Builder

    static func buildDigest(
        from stats: LoopInsightsAggregatedStats,
        frequency: DigestFrequency
    ) -> DigestContent {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let shortDate = DateFormatter()
        shortDate.dateStyle = .medium

        let now = Date()
        let recipientName = Self.recipientName
        let greeting = recipientName.isEmpty
            ? NSLocalizedString("Hi there", comment: "Caregiver digest default greeting")
            : String(format: NSLocalizedString("Hi %@", comment: "Caregiver digest greeting with name"), recipientName)

        let g = stats.glucoseStats
        let i = stats.insulinStats
        let c = stats.carbStats

        // Determine status emoji/sentiment
        let statusEmoji: String
        let statusSummary: String
        if g.timeInRange >= 80 && g.timeBelowRange < 4 {
            statusEmoji = "🟢"
            statusSummary = NSLocalizedString("Things are looking great!", comment: "Caregiver digest: great status")
        } else if g.timeInRange >= 65 && g.timeBelowRange < 6 {
            statusEmoji = "🟡"
            statusSummary = NSLocalizedString("Doing okay overall, with some room for improvement.", comment: "Caregiver digest: okay status")
        } else {
            statusEmoji = "🔴"
            statusSummary = NSLocalizedString("There are some areas that could use attention.", comment: "Caregiver digest: attention status")
        }

        // Low events description
        let lowDesc: String
        if g.timeBelowRange < 1 {
            lowDesc = NSLocalizedString("No significant lows", comment: "Caregiver digest: no lows")
        } else if g.timeBelowRange < 4 {
            lowDesc = String(format: NSLocalizedString("Minor low time (%.1f%% below 70)", comment: "Caregiver digest: minor lows"), g.timeBelowRange)
        } else {
            lowDesc = String(format: NSLocalizedString("⚠️ Notable low time (%.1f%% below 70)", comment: "Caregiver digest: notable lows"), g.timeBelowRange)
        }

        // High events description
        let highDesc: String
        if g.timeAboveRange < 10 {
            highDesc = NSLocalizedString("Minimal time high", comment: "Caregiver digest: minimal highs")
        } else if g.timeAboveRange < 25 {
            highDesc = String(format: NSLocalizedString("Some high time (%.0f%% above 180)", comment: "Caregiver digest: some highs"), g.timeAboveRange)
        } else {
            highDesc = String(format: NSLocalizedString("⚠️ Significant high time (%.0f%% above 180)", comment: "Caregiver digest: significant highs"), g.timeAboveRange)
        }

        let subject = "\(statusEmoji) LoopInsights Digest — \(shortDate.string(from: now))"

        // Plain text version
        let plainText = """
        \(greeting),

        Here's the \(frequency.periodLabel.lowercased()) LoopInsights summary.

        \(statusEmoji) Overall: \(statusSummary)

        📊 GLUCOSE
        • Time in Range (70-180): \(String(format: "%.0f", g.timeInRange))%
        • Average Glucose: \(String(format: "%.0f", g.averageGlucose)) mg/dL
        • GMI (est. A1C): \(String(format: "%.1f", g.gmi))%
        • \(lowDesc)
        • \(highDesc)

        💉 INSULIN
        • Total Daily Dose: \(String(format: "%.1f", i.totalDailyDose)) U/day
        • Basal/Bolus Split: \(String(format: "%.0f", i.basalPercentage))% / \(String(format: "%.0f", i.bolusPercentage))%

        🍽️ MEALS
        • \(c.mealCount) meals logged
        • Average daily carbs: \(String(format: "%.0f", c.averageDailyCarbs))g

        —
        Sent from LoopInsights • \(dateFormatter.string(from: now))
        This is an automated summary for informational purposes only.
        """

        // HTML version
        let htmlBody = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body {
                font-family: -apple-system, 'SF Pro Display', Helvetica Neue, Arial, sans-serif;
                margin: 0; padding: 0;
                color: #1a1a1a; font-size: 14px; line-height: 1.6;
                background: #f5f5f5;
            }
            .container { max-width: 480px; margin: 0 auto; background: #fff; }
            .header {
                background: linear-gradient(135deg, #1a8a9e 0%, #14707e 100%);
                color: white; padding: 24px 20px; text-align: center;
            }
            .header h1 { margin: 0; font-size: 20px; font-weight: 700; }
            .header .period { font-size: 12px; opacity: 0.85; margin-top: 4px; }
            .status-banner {
                padding: 16px 20px;
                font-size: 15px; font-weight: 600;
                text-align: center;
                background: #f0fafb;
                border-bottom: 1px solid #d4eef2;
            }
            .content { padding: 20px; }
            .section-title {
                font-size: 12px; font-weight: 700;
                color: #1a8a9e; text-transform: uppercase;
                letter-spacing: 0.5px;
                margin: 16px 0 8px 0;
                padding-bottom: 4px;
                border-bottom: 2px solid #1a8a9e;
            }
            .section-title:first-child { margin-top: 0; }
            .stat-row {
                display: flex; justify-content: space-between;
                padding: 6px 0;
                border-bottom: 1px solid #f0f0f0;
                font-size: 13px;
            }
            .stat-label { color: #555; }
            .stat-value { font-weight: 600; }
            .tir-highlight {
                font-size: 28px; font-weight: 700;
                color: #1a8a9e; text-align: center;
                margin: 8px 0;
            }
            .tir-label {
                font-size: 11px; color: #888;
                text-align: center; margin-bottom: 12px;
            }
            .alert-row {
                padding: 6px 0;
                font-size: 13px;
                border-bottom: 1px solid #f0f0f0;
            }
            .footer {
                padding: 16px 20px;
                font-size: 10px; color: #999;
                text-align: center; line-height: 1.5;
                border-top: 1px solid #eee;
            }
            .footer .brand { color: #1a8a9e; font-weight: 700; }
        </style>
        </head>
        <body>
        <div class="container">
            <div class="header">
                <h1>LoopInsights Digest</h1>
                <div class="period">\(frequency.periodLabel) — \(shortDate.string(from: now))</div>
            </div>

            <div class="status-banner">\(statusEmoji) \(statusSummary)</div>

            <div class="content">
                <div class="section-title">📊 Glucose</div>
                <div class="tir-highlight">\(String(format: "%.0f", g.timeInRange))%</div>
                <div class="tir-label">Time in Range (70–180 mg/dL)</div>
                <div class="stat-row"><span class="stat-label">Average Glucose</span><span class="stat-value">\(String(format: "%.0f", g.averageGlucose)) mg/dL</span></div>
                <div class="stat-row"><span class="stat-label">GMI (est. A1C)</span><span class="stat-value">\(String(format: "%.1f", g.gmi))%</span></div>
                <div class="stat-row"><span class="stat-label">Std Deviation</span><span class="stat-value">\(String(format: "%.0f", g.standardDeviation)) mg/dL</span></div>
                <div class="alert-row">\(lowDesc)</div>
                <div class="alert-row">\(highDesc)</div>

                <div class="section-title">💉 Insulin</div>
                <div class="stat-row"><span class="stat-label">Avg Daily Dose</span><span class="stat-value">\(String(format: "%.1f", i.totalDailyDose)) U</span></div>
                <div class="stat-row"><span class="stat-label">Basal / Bolus</span><span class="stat-value">\(String(format: "%.0f", i.basalPercentage))% / \(String(format: "%.0f", i.bolusPercentage))%</span></div>
                <div class="stat-row"><span class="stat-label">Correction Boluses</span><span class="stat-value">\(i.correctionBolusCount)</span></div>

                <div class="section-title">🍽️ Meals</div>
                <div class="stat-row"><span class="stat-label">Meals Logged</span><span class="stat-value">\(c.mealCount)</span></div>
                <div class="stat-row"><span class="stat-label">Avg Daily Carbs</span><span class="stat-value">\(String(format: "%.0f", c.averageDailyCarbs))g</span></div>
                <div class="stat-row"><span class="stat-label">Avg Per Meal</span><span class="stat-value">\(String(format: "%.0f", c.averageCarbsPerMeal))g</span></div>
            </div>

            <div class="footer">
                <span class="brand">LoopInsights</span> — AI-Powered Therapy Settings Analysis<br>
                Generated \(dateFormatter.string(from: now))<br>
                This is an automated summary for informational purposes only.
            </div>
        </div>
        </body>
        </html>
        """

        return DigestContent(
            subject: subject,
            plainText: plainText,
            htmlBody: htmlBody,
            generatedAt: now,
            frequency: frequency
        )
    }

}
