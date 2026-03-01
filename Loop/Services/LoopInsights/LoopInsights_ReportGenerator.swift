//
//  LoopInsights_ReportGenerator.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import UIKit
import SwiftUI

/// Generates HTML→PDF reports for LoopInsights data (stats, goals, patterns, reflections).
/// Reports can be shared via the system share sheet.
final class LoopInsights_ReportGenerator {

    // MARK: - HTML Generation

    /// Generate a complete HTML report from LoopInsights data.
    static func generateHTML(
        stats: LoopInsightsAggregatedStats?,
        goals: [LoopInsightsGoal],
        patterns: [LoopInsightsCachedPattern],
        reflections: [LoopInsightsReflection]
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        let shortDateFormatter = DateFormatter()
        shortDateFormatter.dateStyle = .medium

        let now = Date()
        let periodLabel = stats?.period.displayName ?? "N/A"
        let startDate: Date
        if let stats = stats {
            startDate = now.addingTimeInterval(-stats.period.timeInterval)
        } else {
            startDate = now.addingTimeInterval(-14 * 24 * 3600)
        }

        var html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                font-family: -apple-system, Helvetica Neue, Arial, sans-serif;
                margin: 32px;
                color: #1a1a1a;
                font-size: 13px;
                line-height: 1.5;
            }
            h1 { font-size: 22px; color: #333; margin-bottom: 4px; }
            h2 { font-size: 16px; color: #555; margin-top: 24px; margin-bottom: 8px; border-bottom: 1px solid #ddd; padding-bottom: 4px; }
            .header-meta { color: #888; font-size: 11px; margin-bottom: 20px; }
            table { width: 100%; border-collapse: collapse; margin-bottom: 16px; }
            td { padding: 5px 8px; border-bottom: 1px solid #eee; }
            td:first-child { color: #666; width: 55%; }
            td:last-child { font-weight: 600; text-align: right; }
            .goal-row { margin-bottom: 8px; }
            .goal-label { font-weight: 600; }
            .goal-progress { color: #666; }
            .goal-achieved { color: #34c759; }
            .pattern-card { background: #f8f8f8; padding: 8px 12px; border-radius: 6px; margin-bottom: 6px; }
            .pattern-type { font-weight: 600; font-size: 12px; }
            .pattern-desc { color: #555; font-size: 12px; }
            .reflection { margin-bottom: 8px; padding: 8px 12px; background: #f8f8f8; border-radius: 6px; }
            .reflection-date { color: #888; font-size: 11px; }
            .reflection-mood { font-size: 11px; font-weight: 600; }
            .reflection-text { font-size: 12px; margin-top: 2px; }
            .disclaimer { margin-top: 24px; padding-top: 12px; border-top: 1px solid #ddd; color: #999; font-size: 10px; }
        </style>
        </head>
        <body>
        <h1>LoopInsights Report</h1>
        <div class="header-meta">
            Period: \(shortDateFormatter.string(from: startDate)) – \(shortDateFormatter.string(from: now)) (\(periodLabel))<br>
            Generated: \(dateFormatter.string(from: now))
        </div>
        """

        // Glucose Section
        if let stats = stats {
            html += """
            <h2>Glucose</h2>
            <table>
                <tr><td>Time in Range (70-180)</td><td>\(String(format: "%.1f%%", stats.glucoseStats.timeInRange))</td></tr>
                <tr><td>Time in Tight Range (70-\(stats.glucoseStats.tightRangeUpperBound))</td><td>\(String(format: "%.1f%%", stats.glucoseStats.timeInTightRange))</td></tr>
                <tr><td>Average Glucose</td><td>\(String(format: "%.0f mg/dL", stats.glucoseStats.averageGlucose))</td></tr>
                <tr><td>GMI (est. A1C)</td><td>\(String(format: "%.1f%%", stats.glucoseStats.gmi))</td></tr>
                <tr><td>Coefficient of Variation</td><td>\(String(format: "%.1f%%", stats.glucoseStats.coefficientOfVariation))</td></tr>
                <tr><td>Below Range (&lt;70)</td><td>\(String(format: "%.1f%%", stats.glucoseStats.timeBelowRange))</td></tr>
                <tr><td>Above Range (&gt;180)</td><td>\(String(format: "%.1f%%", stats.glucoseStats.timeAboveRange))</td></tr>
                <tr><td>Std Deviation</td><td>\(String(format: "%.1f mg/dL", stats.glucoseStats.standardDeviation))</td></tr>
                <tr><td>Readings</td><td>\(stats.glucoseStats.sampleCount)</td></tr>
            </table>
            """

            // Insulin Section
            html += """
            <h2>Insulin</h2>
            <table>
                <tr><td>Total Daily Dose</td><td>\(String(format: "%.1f U/day", stats.insulinStats.totalDailyDose))</td></tr>
                <tr><td>Basal</td><td>\(String(format: "%.0f%%", stats.insulinStats.basalPercentage))</td></tr>
                <tr><td>Bolus</td><td>\(String(format: "%.0f%%", stats.insulinStats.bolusPercentage))</td></tr>
                <tr><td>Correction Boluses</td><td>\(stats.insulinStats.correctionBolusCount)</td></tr>
            </table>
            """

            // Carbs Section
            html += """
            <h2>Carbs</h2>
            <table>
                <tr><td>Daily Average</td><td>\(String(format: "%.0f g/day", stats.carbStats.averageDailyCarbs))</td></tr>
                <tr><td>Per Meal Average</td><td>\(String(format: "%.0f g", stats.carbStats.averageCarbsPerMeal))</td></tr>
                <tr><td>Meals Logged</td><td>\(stats.carbStats.mealCount)</td></tr>
            </table>
            """
        }

        // Goals Section
        if !goals.isEmpty {
            html += "<h2>Goals</h2>"
            for goal in goals {
                let statusText = goal.achieved
                    ? "<span class=\"goal-achieved\">Achieved</span>"
                    : "<span class=\"goal-progress\">\(String(format: "%.1f", goal.currentValue))\(goal.type.unit) / \(String(format: "%.1f", goal.targetValue))\(goal.type.unit)</span>"
                html += """
                <div class="goal-row">
                    <span class="goal-label">\(escapeHTML(goal.displayLabel))</span> — \(statusText)
                </div>
                """
            }
        }

        // Patterns Section
        if !patterns.isEmpty {
            html += "<h2>Patterns</h2>"
            for pattern in patterns {
                html += """
                <div class="pattern-card">
                    <div class="pattern-type">\(escapeHTML(pattern.type))</div>
                    <div class="pattern-desc">\(escapeHTML(pattern.description))</div>
                </div>
                """
            }
        }

        // Reflections Section (last 5)
        let recentReflections = Array(reflections.prefix(5))
        if !recentReflections.isEmpty {
            html += "<h2>Recent Reflections</h2>"
            let reflectionDateFormatter = DateFormatter()
            reflectionDateFormatter.dateStyle = .medium
            reflectionDateFormatter.timeStyle = .short

            for reflection in recentReflections {
                html += """
                <div class="reflection">
                    <span class="reflection-date">\(reflectionDateFormatter.string(from: reflection.timestamp))</span>
                    <span class="reflection-mood"> \(reflection.mood.emoji) \(reflection.mood.displayName)</span>
                    <div class="reflection-text">\(escapeHTML(reflection.text))</div>
                </div>
                """
            }
        }

        // Disclaimer
        html += """
        <div class="disclaimer">
            This report is generated by LoopInsights for informational purposes only. It is not a substitute for
            professional medical advice, diagnosis, or treatment. Always consult your healthcare provider before
            making changes to your diabetes therapy.
        </div>
        </body>
        </html>
        """

        return html
    }

    // MARK: - PDF Generation

    /// Generate a PDF file from HTML content. Returns URL to temp file.
    static func generatePDF(from html: String) async -> URL? {
        return await MainActor.run {
            let formatter = UIMarkupTextPrintFormatter(markupText: html)

            let renderer = UIPrintPageRenderer()
            renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

            // A4 page size
            let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
            let printableRect = pageRect.insetBy(dx: 36, dy: 36)

            renderer.setValue(NSValue(cgRect: pageRect), forKey: "paperRect")
            renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")

            let pdfData = NSMutableData()
            UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)

            for i in 0..<renderer.numberOfPages {
                UIGraphicsBeginPDFPage()
                renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
            }

            UIGraphicsEndPDFContext()

            // Write to temp file
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let filename = "LoopInsights_Report_\(dateFormatter.string(from: Date())).pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            do {
                try pdfData.write(to: tempURL)
                return tempURL
            } catch {
                LoopInsights_FeatureFlags.log.error("Failed to write PDF: \(error)")
                return nil
            }
        }
    }

    // MARK: - Helpers

    private static func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Share Sheet (UIViewControllerRepresentable)

/// SwiftUI wrapper for UIActivityViewController to share PDFs and other items.
struct LoopInsights_ActivityViewRepresentable: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?

    init(activityItems: [Any], applicationActivities: [UIActivity]? = nil) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
