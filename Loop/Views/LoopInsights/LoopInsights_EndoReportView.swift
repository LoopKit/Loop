//
//  LoopInsights_EndoReportView.swift
//  Loop
//
//  LoopInsights — Endo Visit Report Generator.
//  Generates a branded, shareable PDF summary for endocrinologist appointments.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct LoopInsights_EndoReportView: View {

    let coordinator: LoopInsights_Coordinator

    @State private var reportPeriod: LoopInsightsAnalysisPeriod = .fourteenDays
    @State private var isGenerating = false
    @State private var pdfURL: URL?
    @State private var showingShareSheet = false
    @State private var errorMessage: String?

    // Section toggles
    @State private var includeGlucose = true
    @State private var includeInsulin = true
    @State private var includeNutrition = true
    @State private var includeSettingsChanges = true
    @State private var includeAIInsights = true
    @State private var includeBiometrics = true
    @State private var includeEngagement = true
    @State private var includeCaffeineAlcohol = true
    @State private var includePumpSuspensions = true

    @Environment(\.dismiss) private var dismiss

    private let tealColor = Color(red: 26/255, green: 138/255, blue: 158/255)

    private var emailSubject: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        return "LoopInsights Endo Report — \(dateFormatter.string(from: Date()))"
    }

    var body: some View {
        List {
            headerSection
            periodPicker
            contentPreviewSection
            generateSection

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Endo Report", comment: "LoopInsights endo report title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
            }
        }
        .sheet(isPresented: $showingShareSheet, onDismiss: { isGenerating = false }) {
            if let url = pdfURL {
                LoopInsights_ActivityViewRepresentable(
                    activityItems: [LoopInsights_SubjectItemSource(url: url, subject: emailSubject)]
                )
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundColor(tealColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Generate Endo Report", comment: "Endo report header"))
                            .font(.headline)
                        Text(NSLocalizedString("Create a shareable PDF summary for your endocrinologist appointment", comment: "Endo report description"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(NSLocalizedString("No personal health data leaves your device until you share", comment: "Endo report privacy note"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Section(header: Text(NSLocalizedString("Report Period", comment: "Endo report period section"))) {
            Picker(NSLocalizedString("Period", comment: "Period picker label"), selection: $reportPeriod) {
                Text("7 days").tag(LoopInsightsAnalysisPeriod.sevenDays)
                Text("14 days").tag(LoopInsightsAnalysisPeriod.fourteenDays)
                Text("30 days").tag(LoopInsightsAnalysisPeriod.thirtyDays)
                Text("90 days").tag(LoopInsightsAnalysisPeriod.ninetyDays)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Content Toggles

    private var contentPreviewSection: some View {
        Section(header: Text(NSLocalizedString("Report Contents", comment: "Endo report contents section"))) {
            reportToggleRow(icon: "chart.bar.fill", color: tealColor, title: "Glucose Summary", detail: "TIR, GMI, averages, variability, time-of-day patterns", isOn: $includeGlucose)
            reportToggleRow(icon: "syringe.fill", color: .blue, title: "Insulin Delivery", detail: "TDD, basal/bolus split, correction frequency, daily trends", isOn: $includeInsulin)
            reportToggleRow(icon: "fork.knife", color: .orange, title: "Nutrition & Meals", detail: "Daily carbs, meal frequency, timing patterns", isOn: $includeNutrition)
            reportToggleRow(icon: "chart.line.uptrend.xyaxis", color: .purple, title: "Settings Changes", detail: "Applied suggestions, outcomes, impact metrics", isOn: $includeSettingsChanges)
            reportToggleRow(icon: "brain.head.profile", color: tealColor, title: "AI Insights", detail: "Detected patterns, behavior insights, recommendations", isOn: $includeAIInsights)
            reportToggleRow(icon: "figure.walk", color: .green, title: "Activity & Biometrics", detail: "Steps, heart rate, sleep, exercise correlation", isOn: $includeBiometrics)
            reportToggleRow(icon: "checkmark.shield.fill", color: .indigo, title: "Engagement & Compliance", detail: "Suggestion acceptance, dismissals, reverts", isOn: $includeEngagement)
            reportToggleRow(icon: "cup.and.saucer.fill", color: .brown, title: "Caffeine & Alcohol", detail: "Tracked intake and averages", isOn: $includeCaffeineAlcohol)
            reportToggleRow(icon: "pause.circle.fill", color: .red, title: "Pump Suspensions", detail: "Zero-delivery events and sub-basal time", isOn: $includePumpSuspensions)
        }
    }

    private func reportToggleRow(icon: String, color: Color, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .tint(tealColor)
        .padding(.vertical, 2)
    }

    // MARK: - Generate Button

    private var generateSection: some View {
        Section {
            Button(action: generateReport) {
                HStack {
                    Spacer()
                    if isGenerating {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(NSLocalizedString("Generating...", comment: "Endo report generating"))
                    } else {
                        Image(systemName: "doc.badge.arrow.up.fill")
                            .padding(.trailing, 4)
                        Text(NSLocalizedString("Generate & Share Report", comment: "Endo report generate button"))
                    }
                    Spacer()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .background(isGenerating ? Color.gray : tealColor)
                .cornerRadius(10)
            }
            .disabled(isGenerating)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Report Generation

    private func generateReport() {
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let stats = try await coordinator.dataAggregator.aggregateData(period: reportPeriod)
                let allResolved = coordinator.suggestionStore.resolvedRecords
                let appliedSuggestions = allResolved
                    .filter { $0.status == .applied || $0.status == .autoApplied }
                    .sorted { ($0.resolvedAt ?? $0.createdAt) > ($1.resolvedAt ?? $1.createdAt) }
                let dismissedCount = allResolved.filter { $0.status == .dismissed }.count
                let revertedCount = allResolved.filter { $0.status == .reverted }.count
                let behaviorPatterns = LoopInsights_BehaviorInsightsAnalyzer.analyzePatterns()
                let detectedPatterns = LoopInsights_DashboardViewModel.detectPatterns(from: stats)
                let mealArchive = MealArchive.meals(
                    from: Date().addingTimeInterval(-reportPeriod.timeInterval),
                    to: Date()
                )

                let sections = LoopInsights_EndoReportGenerator.SectionFlags(
                    glucose: includeGlucose,
                    insulin: includeInsulin,
                    nutrition: includeNutrition,
                    settingsChanges: includeSettingsChanges,
                    aiInsights: includeAIInsights,
                    biometrics: includeBiometrics,
                    engagement: includeEngagement,
                    caffeineAlcohol: includeCaffeineAlcohol,
                    pumpSuspensions: includePumpSuspensions
                )

                let html = LoopInsights_EndoReportGenerator.generateEndoReportHTML(
                    stats: stats,
                    period: reportPeriod,
                    appliedSuggestions: Array(appliedSuggestions.prefix(10)),
                    dismissedCount: dismissedCount,
                    revertedCount: revertedCount,
                    behaviorPatterns: behaviorPatterns,
                    detectedPatterns: detectedPatterns,
                    mealCount: mealArchive.count,
                    caffeineTracker: coordinator.caffeineTracker,
                    alcoholTracker: coordinator.alcoholTracker,
                    sections: sections
                )

                if let url = await LoopInsights_ReportGenerator.generatePDF(from: html) {
                    await MainActor.run {
                        self.pdfURL = url
                        self.showingShareSheet = true
                        // isGenerating stays true until share sheet appears
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Failed to generate PDF"
                        self.isGenerating = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Data loading failed: \(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }
}

// MARK: - Endo Report HTML Generator

enum LoopInsights_EndoReportGenerator {

    struct SectionFlags {
        var glucose: Bool = true
        var insulin: Bool = true
        var nutrition: Bool = true
        var settingsChanges: Bool = true
        var aiInsights: Bool = true
        var biometrics: Bool = true
        var engagement: Bool = true
        var caffeineAlcohol: Bool = true
        var pumpSuspensions: Bool = true
    }

    static func generateEndoReportHTML(
        stats: LoopInsightsAggregatedStats,
        period: LoopInsightsAnalysisPeriod,
        appliedSuggestions: [LoopInsightsSuggestionRecord],
        dismissedCount: Int,
        revertedCount: Int,
        behaviorPatterns: [LoopInsightsCorrectionPattern],
        detectedPatterns: [LoopInsightsDetectedPattern] = [],
        mealCount: Int,
        caffeineTracker: LoopInsights_CaffeineTracker,
        alcoholTracker: LoopInsights_AlcoholTracker,
        sections: SectionFlags = SectionFlags()
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long

        let now = Date()
        let startDate = now.addingTimeInterval(-period.timeInterval)

        var html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            * { box-sizing: border-box; }
            body {
                font-family: -apple-system, 'SF Pro Display', Helvetica Neue, Arial, sans-serif;
                margin: 0;
                padding: 0;
                color: #1a1a1a;
                font-size: 12px;
                line-height: 1.5;
                background: #fff;
            }
            .page { padding: 32px 36px; }

            /* Header / Branding */
            .header {
                background: linear-gradient(135deg, #1a8a9e 0%, #14707e 100%);
                color: white;
                padding: 28px 36px;
                border-radius: 0 0 16px 16px;
                margin-bottom: 24px;
            }
            .header h1 {
                font-size: 24px;
                margin: 0 0 4px 0;
                font-weight: 700;
                letter-spacing: -0.5px;
            }
            .header .subtitle {
                font-size: 13px;
                opacity: 0.9;
                margin: 0;
            }
            .header .period {
                font-size: 11px;
                opacity: 0.75;
                margin-top: 8px;
            }
            .header .logo-text {
                font-size: 16px;
                font-weight: 700;
                letter-spacing: 0.5px;
                opacity: 0.85;
                margin-bottom: 6px;
            }

            /* Section Headers */
            h2 {
                font-size: 14px;
                color: #1a8a9e;
                margin: 20px 0 10px 0;
                padding-bottom: 6px;
                border-bottom: 2px solid #1a8a9e;
                font-weight: 700;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }

            /* Glucose Two-Column Layout */
            .glucose-row {
                display: flex;
                gap: 20px;
                margin-bottom: 16px;
            }
            .glucose-stats-col {
                flex: 0 0 55%;
            }
            .glucose-tir-col {
                flex: 1;
                display: flex;
                flex-direction: column;
                align-items: center;
            }

            /* Stats Cards */
            .stats-grid {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 8px;
                margin-bottom: 12px;
            }
            .stats-grid-3 {
                display: grid;
                grid-template-columns: 1fr 1fr 1fr;
                gap: 10px;
                margin-bottom: 16px;
            }
            .stat-card {
                background: #f5fafb;
                border: 1px solid #d4eef2;
                border-radius: 8px;
                padding: 8px 10px;
                text-align: center;
            }
            .stat-card .value {
                font-size: 18px;
                font-weight: 700;
                color: #1a8a9e;
                margin: 2px 0;
            }
            .stat-card .label {
                font-size: 9px;
                color: #666;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }
            .stat-card.highlight {
                background: #1a8a9e;
                border-color: #1a8a9e;
            }
            .stat-card.highlight .value { color: white; }
            .stat-card.highlight .label { color: rgba(255,255,255,0.8); }

            /* Vertical TIR Bar (Dexcom Clarity style) */
            .tir-vertical-container {
                display: flex;
                align-items: stretch;
                gap: 8px;
                width: 100%;
                height: 110px;
            }
            .tir-vertical-bar {
                width: 32px;
                border-radius: 4px;
                overflow: hidden;
                display: flex;
                flex-direction: column;
                flex-shrink: 0;
            }
            .tir-v-segment { width: 100%; min-height: 2px; }
            .tir-very-high { background: #C14F0C; }
            .tir-high { background: #F0CA4C; }
            .tir-in-range { background: #74A52E; }
            .tir-low { background: #D36265; }
            .tir-very-low { background: #7F0302; }
            .tir-labels {
                display: flex;
                flex-direction: column;
                justify-content: center;
                font-size: 11px;
                color: #555;
                gap: 2px;
                flex: 1;
            }
            .tir-label-row {
                line-height: 1.4;
            }
            .tir-label-row.highlight {
                font-weight: 700;
                color: #1a1a1a;
                font-size: 12px;
            }
            .tir-label-row.tight {
                color: #1a8a9e;
                font-size: 11px;
            }
            .tir-footer {
                margin-top: 6px;
                font-size: 10px;
                line-height: 1.5;
            }

            /* Time of Day Chart (simple text-based) */
            .tod-grid {
                display: grid;
                grid-template-columns: repeat(6, 1fr);
                gap: 4px;
                margin: 8px 0;
            }
            .tod-cell {
                text-align: center;
                padding: 6px 4px;
                border-radius: 6px;
                font-size: 10px;
            }
            .tod-label { font-size: 9px; color: #888; margin-top: 2px; }
            .tod-value { font-weight: 700; font-size: 13px; }

            /* Tables */
            table { width: 100%; border-collapse: collapse; margin: 8px 0 16px 0; }
            th {
                text-align: left;
                padding: 6px 8px;
                background: #f0f8f9;
                border-bottom: 2px solid #1a8a9e;
                font-size: 10px;
                text-transform: uppercase;
                letter-spacing: 0.5px;
                color: #1a8a9e;
            }
            td {
                padding: 6px 8px;
                border-bottom: 1px solid #eef5f6;
                font-size: 11px;
            }
            tr:nth-child(even) { background: #fafcfd; }

            /* Suggestion Cards */
            .suggestion-card {
                background: #f8fcfd;
                border-left: 3px solid #1a8a9e;
                padding: 8px 12px;
                margin-bottom: 8px;
                border-radius: 0 6px 6px 0;
            }
            .suggestion-header { font-weight: 600; font-size: 11px; }
            .suggestion-detail { font-size: 10px; color: #555; margin-top: 2px; }
            .suggestion-outcome {
                display: inline-block;
                font-size: 9px;
                padding: 2px 6px;
                border-radius: 4px;
                margin-top: 4px;
                font-weight: 600;
            }
            .outcome-success { background: #d4f5dc; color: #1a7a2e; }
            .outcome-partial { background: #dce8f8; color: #2956a8; }
            .outcome-none { background: #fce8d5; color: #a85c00; }
            .outcome-worsened { background: #fde0e0; color: #a82929; }

            /* Pattern Cards */
            .pattern-card {
                background: #f5f0fa;
                border-left: 3px solid #7c3aed;
                padding: 8px 12px;
                margin-bottom: 6px;
                border-radius: 0 6px 6px 0;
            }
            .pattern-type { font-weight: 600; font-size: 11px; color: #5b21b6; }
            .pattern-desc { font-size: 10px; color: #555; }

            /* Footer */
            .footer {
                margin-top: 24px;
                padding-top: 16px;
                border-top: 2px solid #d4eef2;
                color: #888;
                font-size: 9px;
                line-height: 1.6;
            }
            .footer .brand {
                color: #1a8a9e;
                font-weight: 700;
                font-size: 10px;
            }
        </style>
        </head>
        <body>
        <div class="header">
            <div class="logo-text">LoopInsights</div>
            <h1>Endocrinologist Visit Report</h1>
            <p class="subtitle">Automated Insulin Delivery Performance Summary</p>
            <p class="period">\(dateFormatter.string(from: startDate)) — \(dateFormatter.string(from: now)) (\(period.displayName))</p>
        </div>
        <div class="page">
        """

        // MARK: - Glucose Summary
        if sections.glucose {
        html += "<h2>📊 Glucose Summary</h2>"

        // Two-column layout: stat cards on left, vertical TIR bar on right
        let veryLow = stats.glucoseStats.timeVeryLow
        let low = stats.glucoseStats.timeLow
        let inRange = stats.glucoseStats.timeInRange
        let high = stats.glucoseStats.timeHigh
        let veryHigh = stats.glucoseStats.timeVeryHigh

        html += """
        <div class="glucose-row">
            <div class="glucose-stats-col">
                <div class="stats-grid">
                    <div class="stat-card highlight">
                        <div class="label">Time in Range</div>
                        <div class="value">\(String(format: "%.0f", inRange))%</div>
                    </div>
                    <div class="stat-card">
                        <div class="label">GMI (est. A1C)</div>
                        <div class="value">\(String(format: "%.1f", stats.glucoseStats.gmi))%</div>
                    </div>
                    <div class="stat-card">
                        <div class="label">Average</div>
                        <div class="value">\(String(format: "%.0f", stats.glucoseStats.averageGlucose))</div>
                    </div>
                    <div class="stat-card">
                        <div class="label">Std Deviation</div>
                        <div class="value">\(String(format: "%.0f", stats.glucoseStats.standardDeviation))</div>
                    </div>
                    <div class="stat-card">
                        <div class="label">CV</div>
                        <div class="value">\(String(format: "%.0f", stats.glucoseStats.coefficientOfVariation))%</div>
                    </div>
                    <div class="stat-card">
                        <div class="label">Readings</div>
                        <div class="value">\(stats.glucoseStats.sampleCount)</div>
                    </div>
                </div>
            </div>
            <div class="glucose-tir-col">
                <div style="font-size: 12px; font-weight: 700; color: #1a1a1a; margin-bottom: 6px;">Time in Range</div>
                <div class="tir-vertical-container">
                    <div class="tir-vertical-bar">
                        <div class="tir-v-segment tir-very-high" style="height: \(veryHigh)%"></div>
                        <div class="tir-v-segment tir-high" style="height: \(high)%"></div>
                        <div class="tir-v-segment tir-in-range" style="height: \(inRange)%"></div>
                        <div class="tir-v-segment tir-low" style="height: \(low)%"></div>
                        <div class="tir-v-segment tir-very-low" style="height: \(veryLow)%"></div>
                    </div>
                    <div class="tir-labels">
                        <div class="tir-label-row">\(String(format: "%.0f", veryHigh))% Very High</div>
                        <div class="tir-label-row">\(String(format: "%.0f", high))% High</div>
                        <div class="tir-label-row highlight">\(String(format: "%.0f", inRange))% In Range</div>
                        <div class="tir-label-row tight">\(String(format: "%.0f", stats.glucoseStats.timeInTightRange))% In Tight Range</div>
                        <div class="tir-label-row">\(String(format: "%.0f", low))% Low</div>
                        <div class="tir-label-row">\(String(format: "%.0f", veryLow))% Very Low</div>
                    </div>
                </div>
                <div class="tir-footer">
                    <strong>Target Range:</strong> 70–180 mg/dL<br>
                    <span style="color: #1a8a9e;">Tight Range: 70–\(stats.glucoseStats.tightRangeUpperBound) mg/dL</span>
                </div>
            </div>
        </div>
        """

        // Time of Day glucose averages
        let sortedHours = stats.glucoseStats.hourlyAverages.sorted { $0.key < $1.key }
        if !sortedHours.isEmpty {
            html += "<strong style=\"font-size: 11px;\">Glucose by Time of Day (mg/dL)</strong>"
            html += "<div class=\"tod-grid\">"
            let buckets: [(label: String, hours: [Int])] = [
                ("Night", [0,1,2,3]),
                ("Early AM", [4,5,6,7]),
                ("Morning", [8,9,10,11]),
                ("Afternoon", [12,13,14,15]),
                ("Evening", [16,17,18,19]),
                ("Late", [20,21,22,23])
            ]
            for bucket in buckets {
                let avg = bucket.hours.compactMap { stats.glucoseStats.hourlyAverages[$0] }
                let mean = avg.isEmpty ? 0 : avg.reduce(0, +) / Double(avg.count)
                let bgColor = mean < 70 ? "#ffe0e0" : mean > 180 ? "#fff3e0" : "#e8f8e8"
                let textColor = mean < 70 ? "#cc0000" : mean > 180 ? "#cc6600" : "#1a7a2e"
                html += """
                <div class="tod-cell" style="background: \(bgColor);">
                    <div class="tod-value" style="color: \(textColor);">\(String(format: "%.0f", mean))</div>
                    <div class="tod-label">\(bucket.label)</div>
                </div>
                """
            }
            html += "</div>"
        }
        } // end sections.glucose

        // MARK: - Insulin Delivery
        if sections.insulin {
            html += "<h2>💉 Insulin Delivery</h2>"
            html += """
            <div class="stats-grid-3">
                <div class="stat-card">
                    <div class="label">Avg TDD</div>
                    <div class="value">\(String(format: "%.1f", stats.insulinStats.totalDailyDose))U</div>
                </div>
                <div class="stat-card">
                    <div class="label">Basal</div>
                    <div class="value">\(String(format: "%.0f", stats.insulinStats.basalPercentage))%</div>
                </div>
                <div class="stat-card">
                    <div class="label">Bolus</div>
                    <div class="value">\(String(format: "%.0f", stats.insulinStats.bolusPercentage))%</div>
                </div>
            </div>
            <table>
                <tr><th>Metric</th><th>Value</th></tr>
                <tr><td>Correction Boluses</td><td>\(stats.insulinStats.correctionBolusCount)</td></tr>
                <tr><td>TDD Range</td><td>\(String(format: "%.1f", stats.insulinStats.tddMin)) – \(String(format: "%.1f", stats.insulinStats.tddMax)) U</td></tr>
                <tr><td>TDD Variability (CV)</td><td>\(String(format: "%.0f", stats.insulinStats.tddVariabilityCV))%</td></tr>
            """
            if let weekChange = stats.insulinStats.tddWeekOverWeekChange {
                html += "<tr><td>Week-over-Week TDD Change</td><td>\(String(format: "%+.0f", weekChange))%</td></tr>"
            }
            html += "</table>"
        }

        // MARK: - Nutrition
        if sections.nutrition {
            html += "<h2>🍽️ Nutrition & Meals</h2>"
            html += """
            <div class="stats-grid-3">
                <div class="stat-card">
                    <div class="label">Daily Carbs</div>
                    <div class="value">\(String(format: "%.0f", stats.carbStats.averageDailyCarbs))g</div>
                </div>
                <div class="stat-card">
                    <div class="label">Meals Logged</div>
                    <div class="value">\(mealCount > 0 ? "\(mealCount)" : "\(stats.carbStats.mealCount)")</div>
                </div>
                <div class="stat-card">
                    <div class="label">Per Meal Avg</div>
                    <div class="value">\(String(format: "%.0f", stats.carbStats.averageCarbsPerMeal))g</div>
                </div>
            </div>
            """
        }

        // MARK: - Settings Changes
        if sections.settingsChanges && !appliedSuggestions.isEmpty {
            html += "<h2>⚙️ Settings Changes Applied</h2>"
            let dateFormatterShort = DateFormatter()
            dateFormatterShort.dateStyle = .medium

            for record in appliedSuggestions.prefix(8) {
                let dateStr = dateFormatterShort.string(from: record.resolvedAt ?? record.createdAt)
                let outcomeHTML: String
                if let eval = record.outcomeEvaluation {
                    let cls: String
                    switch eval.verdict {
                    case .success: cls = "outcome-success"
                    case .partial: cls = "outcome-partial"
                    case .noImprovement: cls = "outcome-none"
                    case .worsened: cls = "outcome-worsened"
                    case .insufficientData: cls = "outcome-none"
                    }
                    outcomeHTML = "<span class=\"suggestion-outcome \(cls)\">\(eval.verdict.displayName) — \(escapeHTML(eval.reasoning))</span>"
                } else {
                    outcomeHTML = "<span class=\"suggestion-outcome outcome-none\">Awaiting evaluation</span>"
                }

                html += """
                <div class="suggestion-card">
                    <div class="suggestion-header">\(record.suggestion.settingType.displayName) — \(dateStr)</div>
                    <div class="suggestion-detail">\(escapeHTML(record.suggestion.summaryDescription))</div>
                    \(outcomeHTML)
                </div>
                """
            }
        }

        // MARK: - Activity & Biometrics
        if sections.biometrics, let bio = stats.biometricStats {
            html += "<h2>🏃 Activity & Biometrics</h2>"
            html += "<table><tr><th>Metric</th><th>Value</th></tr>"
            if let steps = bio.steps {
                html += "<tr><td>Avg Daily Steps</td><td>\(String(format: "%.0f", steps.averageDailySteps))</td></tr>"
            }
            if let hr = bio.heartRate {
                html += "<tr><td>Avg Resting HR</td><td>\(String(format: "%.0f", hr.averageRestingHR)) bpm</td></tr>"
            }
            if let hrv = bio.hrv {
                html += "<tr><td>Avg HRV (SDNN)</td><td>\(String(format: "%.0f", hrv.averageSDNN)) ms</td></tr>"
            }
            if let sleep = bio.sleep {
                html += "<tr><td>Avg Sleep Duration</td><td>\(String(format: "%.1f", sleep.averageDurationHours))h</td></tr>"
            }
            if let energy = bio.activeEnergy {
                html += "<tr><td>Avg Active Energy</td><td>\(String(format: "%.0f", energy.averageDailyCalories)) kcal</td></tr>"
            }
            if let weight = bio.weight {
                html += "<tr><td>Latest Weight</td><td>\(String(format: "%.1f", weight.latestWeight)) kg</td></tr>"
                if abs(weight.weightTrend) > 0.1 {
                    html += "<tr><td>Weight Trend</td><td>\(String(format: "%+.1f", weight.weightTrend)) kg</td></tr>"
                }
            }
            html += "</table>"
        }

        // MARK: - Engagement & Compliance
        if sections.engagement {
            html += "<h2>📋 Engagement & Compliance</h2>"
            let totalSuggestions = appliedSuggestions.count + dismissedCount + revertedCount
            let acceptanceRate = totalSuggestions > 0 ? Double(appliedSuggestions.count) / Double(totalSuggestions) * 100 : 0
            html += """
            <table>
                <tr><th>Metric</th><th>Value</th></tr>
                <tr><td>AI Suggestions Applied</td><td>\(appliedSuggestions.count)</td></tr>
                <tr><td>AI Suggestions Dismissed</td><td>\(dismissedCount)</td></tr>
                <tr><td>AI Suggestions Reverted</td><td>\(revertedCount)</td></tr>
                <tr><td>Acceptance Rate</td><td>\(String(format: "%.0f", acceptanceRate))%</td></tr>
                <tr><td>Meals Logged (FoodFinder)</td><td>\(mealCount)</td></tr>
                <tr><td>Carb Entries (total)</td><td>\(stats.carbStats.mealCount)</td></tr>
            </table>
            """
        }

        // MARK: - Caffeine & Alcohol
        if sections.caffeineAlcohol {
            let caffeineEntries = caffeineTracker.entries
            let alcoholEntries = alcoholTracker.entries
            let periodStart = Date().addingTimeInterval(-period.timeInterval)
            let caffeineInPeriod = caffeineEntries.filter { $0.timestamp >= periodStart }
            let alcoholInPeriod = alcoholEntries.filter { $0.timestamp >= periodStart }

            if !caffeineInPeriod.isEmpty || !alcoholInPeriod.isEmpty {
                html += "<h2>☕ Caffeine & Alcohol Tracking</h2>"
                html += "<table><tr><th>Substance</th><th>Details</th></tr>"
                if !caffeineInPeriod.isEmpty {
                    let totalMg = caffeineInPeriod.reduce(0.0) { $0 + $1.milligrams }
                    let avgDaily = totalMg / Double(period.rawValue)
                    html += "<tr><td>Caffeine Entries</td><td>\(caffeineInPeriod.count) in period</td></tr>"
                    html += "<tr><td>Avg Daily Caffeine</td><td>\(String(format: "%.0f", avgDaily)) mg</td></tr>"
                }
                if !alcoholInPeriod.isEmpty {
                    let totalDrinks = alcoholInPeriod.reduce(0.0) { $0 + $1.standardDrinks }
                    let avgWeekly = totalDrinks / (Double(period.rawValue) / 7.0)
                    html += "<tr><td>Alcohol Entries</td><td>\(alcoholInPeriod.count) in period</td></tr>"
                    html += "<tr><td>Avg Weekly Drinks</td><td>\(String(format: "%.1f", avgWeekly)) standard</td></tr>"
                }
                html += "</table>"
            }
        }

        // MARK: - Negative Basal / Pump Suspensions
        if sections.pumpSuspensions, let negBasal = stats.insulinStats.negativeBasalStats {
            let avgSuspensionMin = negBasal.suspensionCount > 0
                ? negBasal.totalSuspensionMinutes / Double(negBasal.suspensionCount) : 0
            html += "<h2>⏸️ Pump Suspensions & Sub-Basal</h2>"
            html += """
            <table>
                <tr><th>Metric</th><th>Value</th></tr>
                <tr><td>Suspension Events</td><td>\(negBasal.suspensionCount)</td></tr>
                <tr><td>Total Suspension Time</td><td>\(String(format: "%.0f", negBasal.totalSuspensionMinutes)) min (\(String(format: "%.1f", negBasal.suspensionPercentage))%)</td></tr>
                <tr><td>Avg Duration per Event</td><td>\(String(format: "%.0f", avgSuspensionMin)) min</td></tr>
                <tr><td>Sub-Basal Time</td><td>\(String(format: "%.0f", negBasal.subBasalMinutes)) min</td></tr>
                <tr><td>Overcorrection Events (suspend → rebound &gt;180)</td><td>\(negBasal.overcorrectionEvents)</td></tr>
            </table>
            """
        }

        // MARK: - AI Insights (detected patterns + behavior corrections)
        if sections.aiInsights {
            let hasDetected = !detectedPatterns.isEmpty
            let hasBehavior = !behaviorPatterns.isEmpty

            if hasDetected || hasBehavior {
                html += "<h2>🧠 AI Insights</h2>"

                // Detected glucose/insulin patterns
                if hasDetected {
                    html += "<p style=\"font-size: 10px; color: #666; margin-bottom: 8px; font-weight: 600;\">Detected Glucose & Insulin Patterns</p>"
                    for pattern in detectedPatterns {
                        let severityColor: String
                        let severityLabel: String
                        switch pattern.severity {
                        case .high:
                            severityColor = "#dc2626"
                            severityLabel = "High"
                        case .medium:
                            severityColor = "#d97706"
                            severityLabel = "Medium"
                        case .low:
                            severityColor = "#2563eb"
                            severityLabel = "Low"
                        }
                        html += """
                        <div class="pattern-card" style="border-left-color: \(severityColor);">
                            <div class="pattern-type" style="color: \(severityColor);">\(escapeHTML(pattern.type.displayName)) <span style="font-size: 9px; font-weight: 400;">(\(severityLabel) confidence)</span></div>
                            <div class="pattern-desc">\(escapeHTML(pattern.detail))</div>
                        </div>
                        """
                    }
                }

                // Behavior correction patterns
                if hasBehavior {
                    if hasDetected { html += "<div style=\"height: 12px;\"></div>" }
                    html += "<p style=\"font-size: 10px; color: #666; margin-bottom: 8px; font-weight: 600;\">Behavior Correction Patterns</p>"
                    html += "<p style=\"font-size: 9px; color: #999; margin-bottom: 6px;\">Consistent adjustments the user makes to AI carb estimates:</p>"
                    for pattern in behaviorPatterns.prefix(5) {
                        html += """
                        <div class="pattern-card">
                            <div class="pattern-type">\(pattern.groupingType.displayName): \(escapeHTML(pattern.groupingValue))</div>
                            <div class="pattern-desc">\(escapeHTML(pattern.summaryDescription)) (consistency: \(String(format: "%.0f", pattern.consistency * 100))%)</div>
                        </div>
                        """
                    }
                }
            }
        }

        // MARK: - Footer
        html += """
        <div class="footer">
            <span class="brand">LoopInsights</span> — AI-Powered Therapy Settings Analysis<br>
            This report was automatically generated for informational purposes only. It is not a substitute for
            professional medical advice, diagnosis, or treatment. Always consult your healthcare provider before
            making changes to your diabetes therapy.<br><br>
            Generated: \(dateFormatter.string(from: now)) • Report Period: \(period.displayName) • Readings: \(stats.glucoseStats.sampleCount)
        </div>
        </div>
        </body>
        </html>
        """

        return html
    }

    private static func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
