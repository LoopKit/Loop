//
//  DataLayer_ReportGenerator.swift
//  Loop
//
//  DataLayer — On-device HTML→PDF report generator for provider sharing.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import UIKit

// MARK: - Report Data Model

/// Aggregated report data built from decoded DataLayer event payloads.
struct DataLayer_ReportData {

    struct GlucoseStats {
        var average: Double = 0
        var stdDev: Double = 0
        var cv: Double = 0
        var gmi: Double = 0
        var tirPercent: Double = 0      // 70-180
        var titrPercent: Double = 0     // 70-140
        var veryLow: Double = 0         // <54
        var low: Double = 0             // 54-69
        var inRange: Double = 0         // 70-180
        var high: Double = 0            // 181-250
        var veryHigh: Double = 0        // >250
        var sampleCount: Int = 0
        var dailyStats: [(date: String, avg: Double, min: Double, max: Double)] = []
    }

    struct InsulinStats {
        var tdd: Double = 0
        var basalUnits: Double = 0
        var bolusUnits: Double = 0
        var basalPercent: Double = 0
        var bolusPercent: Double = 0
        var dailyTDD: [(date: String, tdd: Double)] = []
    }

    struct CarbStats {
        var dailyAvg: Double = 0
        var mealCount: Int = 0
        var avgPerMeal: Double = 0
    }

    struct MealEntry {
        var foodName: String
        var carbsGrams: Double
        var confidencePercent: Int?
        var date: Date
    }

    struct SubstanceStats {
        var caffeineLogCount: Int = 0
        var caffeineTotalMg: Double = 0
        var alcoholLogCount: Int = 0
        var alcoholTotalDrinks: Double = 0
    }

    var glucose = GlucoseStats()
    var insulin = InsulinStats()
    var carbs = CarbStats()
    var meals: [MealEntry] = []
    var substances = SubstanceStats()
    var hasGlucose: Bool { glucose.sampleCount > 0 }
    var hasInsulin: Bool { insulin.tdd > 0 }
    var hasCarbs: Bool { carbs.mealCount > 0 }
    var hasMeals: Bool { !meals.isEmpty }
    var hasSubstances: Bool { substances.caffeineLogCount > 0 || substances.alcoholLogCount > 0 }
}

// MARK: - Report Generator

/// Generates a professional medical-style PDF report from DataLayer's local event store.
/// All processing is on-device — no backend needed. Consent is respected by construction
/// (only consented event types exist in the store).
final class DataLayer_ReportGenerator {

    // MARK: - Main Entry Point

    /// Query EventStore → aggregate → HTML → PDF → temp file URL.
    static func generateReport(days: Int) async -> URL? {
        let coordinator = DataLayer_Coordinator.shared
        let end = Date()
        let start = end.addingTimeInterval(-Double(days) * 86400)

        let glucoseEvents = coordinator.events(from: start, to: end, type: .glucoseSample)
        let insulinEvents = coordinator.events(from: start, to: end, type: .insulinDelivery)
        let carbEvents = coordinator.events(from: start, to: end, type: .carbEntry)
        let mealEvents = coordinator.events(from: start, to: end, type: .mealAnalysis)
        let caffeineEvents = coordinator.events(from: start, to: end, type: .caffeineLogged)
        let alcoholEvents = coordinator.events(from: start, to: end, type: .alcoholLogged)

        let allEvents = glucoseEvents + insulinEvents + carbEvents + mealEvents + caffeineEvents + alcoholEvents
        let data = aggregateFromEvents(allEvents)
        let html = generateHTML(data: data, days: days)
        return await generatePDF(from: html)
    }

    // MARK: - Aggregation

    static func aggregateFromEvents(_ events: [DataLayer_Event]) -> DataLayer_ReportData {
        var data = DataLayer_ReportData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var allReadings: [(date: Date, mgdl: Double)] = []
        var allDeliveries: [(date: Date, units: Double, type: String)] = []
        var allCarbEntries: [(date: Date, grams: Double)] = []

        for event in events {
            switch event.eventType {
            case .glucoseSample:
                if let payload = try? decoder.decode(DataLayer_GlucoseSamplePayload.self, from: event.payload) {
                    for reading in payload.readings {
                        allReadings.append((date: reading.timestamp, mgdl: reading.mgdl))
                    }
                }

            case .insulinDelivery:
                if let payload = try? decoder.decode(DataLayer_InsulinDeliveryPayload.self, from: event.payload) {
                    for delivery in payload.deliveries {
                        allDeliveries.append((date: delivery.startDate, units: delivery.units, type: delivery.type))
                    }
                }

            case .carbEntry:
                if let payload = try? decoder.decode(DataLayer_CarbEntryPayload.self, from: event.payload) {
                    for entry in payload.entries {
                        allCarbEntries.append((date: entry.date, grams: entry.grams))
                    }
                }

            case .mealAnalysis:
                if let payload = try? decoder.decode(DataLayer_MealAnalysisPayload.self, from: event.payload) {
                    data.meals.append(DataLayer_ReportData.MealEntry(
                        foodName: payload.foodName,
                        carbsGrams: payload.carbsGrams,
                        confidencePercent: payload.aiConfidencePercent,
                        date: event.timestamp
                    ))
                }

            case .caffeineLogged:
                if let payload = try? decoder.decode(DataLayer_CaffeineLoggedPayload.self, from: event.payload) {
                    data.substances.caffeineLogCount += 1
                    data.substances.caffeineTotalMg += payload.milligrams
                }

            case .alcoholLogged:
                if let payload = try? decoder.decode(DataLayer_AlcoholLoggedPayload.self, from: event.payload) {
                    data.substances.alcoholLogCount += 1
                    data.substances.alcoholTotalDrinks += payload.standardDrinks
                }

            default:
                break
            }
        }

        // Glucose aggregation
        if !allReadings.isEmpty {
            let values = allReadings.map { $0.mgdl }
            let count = Double(values.count)
            let avg = values.reduce(0, +) / count
            let variance = values.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / count
            let sd = sqrt(variance)

            data.glucose.average = avg
            data.glucose.stdDev = sd
            data.glucose.cv = avg > 0 ? (sd / avg) * 100 : 0
            data.glucose.gmi = 3.31 + (0.02392 * avg)  // GMI formula
            data.glucose.sampleCount = values.count

            let veryLow = values.filter { $0 < 54 }.count
            let low = values.filter { $0 >= 54 && $0 < 70 }.count
            let inRange = values.filter { $0 >= 70 && $0 <= 180 }.count
            let high = values.filter { $0 > 180 && $0 <= 250 }.count
            let veryHigh = values.filter { $0 > 250 }.count
            let tightRange = values.filter { $0 >= 70 && $0 <= 140 }.count

            data.glucose.veryLow = Double(veryLow) / count * 100
            data.glucose.low = Double(low) / count * 100
            data.glucose.inRange = Double(inRange) / count * 100
            data.glucose.high = Double(high) / count * 100
            data.glucose.veryHigh = Double(veryHigh) / count * 100
            data.glucose.tirPercent = Double(inRange) / count * 100
            data.glucose.titrPercent = Double(tightRange) / count * 100

            // Daily stats
            let cal = Calendar.current
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            var byDay: [String: [Double]] = [:]
            for r in allReadings {
                let key = dayFormatter.string(from: r.date)
                byDay[key, default: []].append(r.mgdl)
            }
            data.glucose.dailyStats = byDay.keys.sorted().map { day in
                let vals = byDay[day]!
                return (date: day, avg: vals.reduce(0, +) / Double(vals.count),
                        min: vals.min() ?? 0, max: vals.max() ?? 0)
            }
        }

        // Insulin aggregation
        if !allDeliveries.isEmpty {
            let totalUnits = allDeliveries.map { $0.units }.reduce(0, +)
            let basalUnits = allDeliveries.filter { $0.type == "basal" }.map { $0.units }.reduce(0, +)
            let bolusUnits = allDeliveries.filter { $0.type != "basal" }.map { $0.units }.reduce(0, +)

            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            var byDay: [String: Double] = [:]
            for d in allDeliveries {
                let key = dayFormatter.string(from: d.date)
                byDay[key, default: 0] += d.units
            }
            let dayCount = max(Double(byDay.count), 1)

            data.insulin.tdd = totalUnits / dayCount
            data.insulin.basalUnits = basalUnits / dayCount
            data.insulin.bolusUnits = bolusUnits / dayCount
            data.insulin.basalPercent = totalUnits > 0 ? (basalUnits / totalUnits) * 100 : 0
            data.insulin.bolusPercent = totalUnits > 0 ? (bolusUnits / totalUnits) * 100 : 0
            data.insulin.dailyTDD = byDay.keys.sorted().map { (date: $0, tdd: byDay[$0]!) }
        }

        // Carb aggregation
        if !allCarbEntries.isEmpty {
            let totalCarbs = allCarbEntries.map { $0.grams }.reduce(0, +)
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            var byDay: [String: Double] = [:]
            for c in allCarbEntries {
                let key = dayFormatter.string(from: c.date)
                byDay[key, default: 0] += c.grams
            }
            let dayCount = max(Double(byDay.count), 1)

            data.carbs.dailyAvg = totalCarbs / dayCount
            data.carbs.mealCount = allCarbEntries.count
            data.carbs.avgPerMeal = totalCarbs / Double(allCarbEntries.count)
        }

        // Sort meals by date descending, keep top 20
        data.meals.sort { $0.date > $1.date }
        if data.meals.count > 20 { data.meals = Array(data.meals.prefix(20)) }

        return data
    }

    // MARK: - HTML Generation

    static func generateHTML(data: DataLayer_ReportData, days: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let shortDateFormatter = DateFormatter()
        shortDateFormatter.dateStyle = .medium
        let mealDateFormatter = DateFormatter()
        mealDateFormatter.dateStyle = .short
        mealDateFormatter.timeStyle = .short

        let now = Date()
        let start = now.addingTimeInterval(-Double(days) * 86400)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

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
            th { text-align: left; padding: 5px 8px; border-bottom: 2px solid #ddd; font-size: 12px; color: #666; }
            td { padding: 5px 8px; border-bottom: 1px solid #eee; }
            .stat-table td:first-child { color: #666; width: 55%; }
            .stat-table td:last-child { font-weight: 600; text-align: right; }
            .tir-bar { height: 18px; border-radius: 4px; display: flex; overflow: hidden; margin: 8px 0; }
            .tir-bar div { height: 100%; }
            .tir-vlow { background: #d32f2f; }
            .tir-low { background: #f44336; }
            .tir-range { background: #4caf50; }
            .tir-high { background: #ff9800; }
            .tir-vhigh { background: #e65100; }
            .tir-legend { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 12px; }
            .tir-legend span { font-size: 10px; color: #666; }
            .tir-legend .dot { display: inline-block; width: 8px; height: 8px; border-radius: 2px; margin-right: 3px; vertical-align: middle; }
            .meal-row { margin-bottom: 6px; padding: 6px 10px; background: #f8f8f8; border-radius: 5px; }
            .meal-name { font-weight: 600; }
            .meal-detail { color: #666; font-size: 12px; }
            .disclaimer { margin-top: 28px; padding-top: 12px; border-top: 1px solid #ddd; color: #999; font-size: 10px; }
        </style>
        </head>
        <body>
        <h1>Loop Data Report</h1>
        <div class="header-meta">
            \(shortDateFormatter.string(from: start)) – \(shortDateFormatter.string(from: now)) (\(days) days)<br>
            Generated: \(dateFormatter.string(from: now))<br>
            Loop v\(escapeHTML(version))
        </div>
        """

        // Glucose Summary
        if data.hasGlucose {
            let g = data.glucose
            html += """
            <h2>Glucose Summary</h2>
            <div class="tir-bar">
                <div class="tir-vlow" style="width:\(String(format:"%.1f", g.veryLow))%"></div>
                <div class="tir-low" style="width:\(String(format:"%.1f", g.low))%"></div>
                <div class="tir-range" style="width:\(String(format:"%.1f", g.inRange))%"></div>
                <div class="tir-high" style="width:\(String(format:"%.1f", g.high))%"></div>
                <div class="tir-vhigh" style="width:\(String(format:"%.1f", g.veryHigh))%"></div>
            </div>
            <div class="tir-legend">
                <span><span class="dot" style="background:#d32f2f"></span>Very Low &lt;54: \(String(format:"%.1f%%", g.veryLow))</span>
                <span><span class="dot" style="background:#f44336"></span>Low 54-69: \(String(format:"%.1f%%", g.low))</span>
                <span><span class="dot" style="background:#4caf50"></span>In Range 70-180: \(String(format:"%.1f%%", g.inRange))</span>
                <span><span class="dot" style="background:#ff9800"></span>High 181-250: \(String(format:"%.1f%%", g.high))</span>
                <span><span class="dot" style="background:#e65100"></span>Very High &gt;250: \(String(format:"%.1f%%", g.veryHigh))</span>
            </div>
            <table class="stat-table">
                <tr><td>Average Glucose</td><td>\(String(format:"%.0f mg/dL", g.average))</td></tr>
                <tr><td>Standard Deviation</td><td>\(String(format:"%.1f mg/dL", g.stdDev))</td></tr>
                <tr><td>Coefficient of Variation</td><td>\(String(format:"%.1f%%", g.cv))</td></tr>
                <tr><td>GMI (est. A1C)</td><td>\(String(format:"%.1f%%", g.gmi))</td></tr>
                <tr><td>Time in Range (70-180)</td><td>\(String(format:"%.1f%%", g.tirPercent))</td></tr>
                <tr><td>Time in Tight Range (70-140)</td><td>\(String(format:"%.1f%%", g.titrPercent))</td></tr>
                <tr><td>Readings</td><td>\(g.sampleCount)</td></tr>
            </table>
            """

            // Daily glucose table
            if !g.dailyStats.isEmpty {
                html += """
                <h2>Daily Glucose</h2>
                <table>
                    <tr><th>Date</th><th>Avg</th><th>Min</th><th>Max</th></tr>
                """
                for day in g.dailyStats {
                    html += "<tr><td>\(escapeHTML(day.date))</td><td>\(String(format:"%.0f", day.avg))</td><td>\(String(format:"%.0f", day.min))</td><td>\(String(format:"%.0f", day.max))</td></tr>"
                }
                html += "</table>"
            }
        }

        // Insulin Delivery
        if data.hasInsulin {
            let ins = data.insulin
            html += """
            <h2>Insulin Delivery</h2>
            <table class="stat-table">
                <tr><td>Total Daily Dose</td><td>\(String(format:"%.1f U/day", ins.tdd))</td></tr>
                <tr><td>Basal</td><td>\(String(format:"%.1f U (%.0f%%)", ins.basalUnits, ins.basalPercent))</td></tr>
                <tr><td>Bolus</td><td>\(String(format:"%.1f U (%.0f%%)", ins.bolusUnits, ins.bolusPercent))</td></tr>
            </table>
            """

            if !ins.dailyTDD.isEmpty {
                html += """
                <table>
                    <tr><th>Date</th><th>TDD (U)</th></tr>
                """
                for day in ins.dailyTDD {
                    html += "<tr><td>\(escapeHTML(day.date))</td><td>\(String(format:"%.1f", day.tdd))</td></tr>"
                }
                html += "</table>"
            }
        }

        // Carbs & Meals
        if data.hasCarbs {
            let c = data.carbs
            html += """
            <h2>Carbs &amp; Meals</h2>
            <table class="stat-table">
                <tr><td>Daily Average</td><td>\(String(format:"%.0f g/day", c.dailyAvg))</td></tr>
                <tr><td>Meals Logged</td><td>\(c.mealCount)</td></tr>
                <tr><td>Avg per Meal</td><td>\(String(format:"%.0f g", c.avgPerMeal))</td></tr>
            </table>
            """
        }

        // AI Meal Analyses
        if data.hasMeals {
            html += "<h2>Meal Analyses (Top \(data.meals.count))</h2>"
            for meal in data.meals {
                let conf = meal.confidencePercent.map { "\($0)% confidence" } ?? ""
                html += """
                <div class="meal-row">
                    <span class="meal-name">\(escapeHTML(meal.foodName))</span>
                    <span class="meal-detail"> — \(String(format:"%.0f g carbs", meal.carbsGrams))\(conf.isEmpty ? "" : " · \(conf)") · \(mealDateFormatter.string(from: meal.date))</span>
                </div>
                """
            }
        }

        // Substances
        if data.hasSubstances {
            let s = data.substances
            html += """
            <h2>Substances</h2>
            <table class="stat-table">
            """
            if s.caffeineLogCount > 0 {
                html += """
                <tr><td>Caffeine Logs</td><td>\(s.caffeineLogCount)</td></tr>
                <tr><td>Total Caffeine</td><td>\(String(format:"%.0f mg", s.caffeineTotalMg))</td></tr>
                """
            }
            if s.alcoholLogCount > 0 {
                html += """
                <tr><td>Alcohol Logs</td><td>\(s.alcoholLogCount)</td></tr>
                <tr><td>Total Drinks</td><td>\(String(format:"%.1f", s.alcoholTotalDrinks))</td></tr>
                """
            }
            html += "</table>"
        }

        // Disclaimer
        html += """
        <div class="disclaimer">
            This report is generated by Loop for informational purposes only. It is not a substitute for
            professional medical advice, diagnosis, or treatment. Always consult your healthcare provider before
            making changes to your diabetes therapy. Data reflects only what was collected on this device
            during the selected time period.
        </div>
        </body>
        </html>
        """

        return html
    }

    // MARK: - PDF Generation

    /// Identical pipeline to LoopInsights_ReportGenerator: UIMarkupTextPrintFormatter → UIPrintPageRenderer → A4 PDF.
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

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let filename = "Loop_Data_Report_\(dateFormatter.string(from: Date())).pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            do {
                try pdfData.write(to: tempURL)
                return tempURL
            } catch {
                DataLayer_FeatureFlags.log.error("Failed to write PDF: \(error)")
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
