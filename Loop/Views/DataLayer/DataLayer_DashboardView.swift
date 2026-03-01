//
//  DataLayer_DashboardView.swift
//  Loop
//
//  DataLayer — Local data visualization dashboard with constituency demo tabs.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

// MARK: - Constituency Data

/// Aggregated metrics decoded from local DataLayer events for constituency tabs.
private struct ConstituencyData {
    // Glucose
    var glucoseAvg: Double = 0
    var glucoseStdDev: Double = 0
    var glucoseCV: Double = 0
    var glucoseGMI: Double = 0
    var glucoseTIR: Double = 0
    var glucoseBelow54: Double = 0
    var glucoseBelow70: Double = 0
    var glucoseAbove180: Double = 0
    var glucoseAbove250: Double = 0
    var glucoseSampleCount: Int = 0

    // Insulin
    var totalDailyDose: Double = 0
    var basalUnits: Double = 0
    var bolusUnits: Double = 0
    var deliveryCount: Int = 0

    // Carbs
    var totalCarbs: Double = 0
    var mealCount: Int = 0
    var dailyAvgCarbs: Double = 0
    var avgCarbsPerMeal: Double = 0

    // AI Suggestions
    var aiGenerated: Int = 0
    var aiApplied: Int = 0
    var aiDismissed: Int = 0
    var aiReverted: Int = 0

    // Chat
    var chatMessages: Int = 0
    var voiceMessages: Int = 0
    var textMessages: Int = 0

    // FoodFinder
    var mealAnalyses: Int = 0
    var barcodeScans: Int = 0
    var mealsConfirmed: Int = 0

    // Meal Debriefs
    var debriefCount: Int = 0
    var avgPeakDelta: Double = 0

    // Substances
    var caffeineLogCount: Int = 0
    var avgCaffeineMg: Double = 0
    var alcoholLogCount: Int = 0
    var avgDrinks: Double = 0
    var highHypoRiskCount: Int = 0

    // Presets
    var presetActivations: Int = 0
    var presetsByType: [(String, Int)] = []

    // Biometrics
    var avgHeartRate: Double = 0
    var avgHRV: Double = 0
    var totalSteps: Double = 0
    var avgSleepHours: Double = 0
    var biometricCount: Int = 0

    // Settings
    var settingsChanges: Int = 0
    var aiSuggestedChanges: Int = 0
    var manualChanges: Int = 0

    // Overrides
    var overrideActivations: Int = 0
    var overridesByType: [(String, Int)] = []

    // Sessions
    var sessionCount: Int = 0
    var activeDays: Int = 0
    var sessionsPerDay: Double = 0

    // Feature Adoption
    var activeFeatures: [String] = []

    // Data Completeness
    var dataStartDate: Date?
    var dataEndDate: Date?
    var daysWithData: Int = 0
    var eventsByTypeCount: [(String, Int)] = []
}

// MARK: - Dashboard View

/// Dashboard showing locally recorded DataLayer events with
/// visual breakdowns by type, upload status, and daily volume.
struct DataLayer_DashboardView: View {

    @State private var selectedTab = 0
    @State private var eventsByType: [(String, Int)] = []
    @State private var uploadStatus: [(String, Int)] = []
    @State private var dailyCounts: [(String, Int)] = []
    @State private var recentEvents: [DataLayer_Event] = []
    @State private var totalEvents = 0
    @State private var cd = ConstituencyData()

    // Ask Loopy! state
    @State private var loopyQuery = ""
    @State private var loopyResponse = ""
    @State private var loopyIsLoading = false
    @State private var loopyError = ""

    private let store = DataLayer_EventCollector.shared.eventStore

    var body: some View {
        List {
            tabPicker
            tabContent
        }
        .navigationTitle("DataLayer Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadData()
            loadConstituencyData()
        }
        .onChange(of: selectedTab) { _ in
            loopyQuery = ""
            loopyResponse = ""
            loopyIsLoading = false
            loopyError = ""
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Section {
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Pharma").tag(1)
                Text("Devices").tag(2)
                Text("Payers").tag(3)
                Text("Research").tag(4)
                Text("Digital").tag(5)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 1: pharmaContent
        case 2: devicesContent
        case 3: payersContent
        case 4: researchContent
        case 5: digitalHealthContent
        default: overviewContent
        }
    }

    // MARK: - Tab 0: Overview

    @ViewBuilder
    private var overviewContent: some View {
        summarySection
        dailyTrendSection
        eventsByTypeSection
        uploadStatusSection
        recentEventsSection
    }

    // MARK: - Tab 1: Pharma

    @ViewBuilder
    private var pharmaContent: some View {
        constituencySection(icon: "drop.fill", color: .red, title: "GLUCOSE CONTROL") {
            dataRow("Average Glucose", cd.glucoseSampleCount > 0 ? "\(Int(cd.glucoseAvg)) mg/dL" : "—")
            dataRow("Time in Range (70-180)", cd.glucoseSampleCount > 0 ? pct(cd.glucoseTIR) : "—", color: .green)
            dataRow("GMI (est. A1C)", cd.glucoseSampleCount > 0 ? pct(cd.glucoseGMI) : "—")
            dataRow("Coefficient of Variation", cd.glucoseSampleCount > 0 ? pct(cd.glucoseCV) : "—")
            dataRow("Sample Count", "\(cd.glucoseSampleCount)")
        }

        constituencySection(icon: "syringe.fill", color: .orange, title: "INSULIN DELIVERY") {
            dataRow("Total Daily Dose", cd.deliveryCount > 0 ? String(format: "%.1f U", cd.totalDailyDose) : "—")
            dataRow("Basal", cd.deliveryCount > 0 ? String(format: "%.1f U (%.0f%%)", cd.basalUnits, cd.totalDailyDose > 0 ? cd.basalUnits / cd.totalDailyDose * 100 : 0) : "—")
            dataRow("Bolus", cd.deliveryCount > 0 ? String(format: "%.1f U (%.0f%%)", cd.bolusUnits, cd.totalDailyDose > 0 ? cd.bolusUnits / cd.totalDailyDose * 100 : 0) : "—")
        }

        constituencySection(icon: "brain.head.profile", color: Color(red: 26/255, green: 138/255, blue: 158/255), title: "AI THERAPY ADHERENCE") {
            dataRow("Suggestions Generated", "\(cd.aiGenerated)")
            dataRow("Applied", "\(cd.aiApplied)" + (cd.aiGenerated > 0 ? String(format: " (%.0f%%)", Double(cd.aiApplied) / Double(cd.aiGenerated) * 100) : ""))
            dataRow("Dismissed", "\(cd.aiDismissed)")
            dataRow("Reverted", "\(cd.aiReverted)")
        }

        constituencySection(icon: "gearshape.fill", color: .gray, title: "THERAPY SETTINGS EVOLUTION") {
            dataRow("Total Changes", "\(cd.settingsChanges)")
            dataRow("AI-Suggested", "\(cd.aiSuggestedChanges)")
            dataRow("Manual", "\(cd.manualChanges)")
        }

        constituencySection(icon: "cross.vial.fill", color: .brown, title: "SUBSTANCE INTERACTIONS") {
            dataRow("Caffeine Logs", "\(cd.caffeineLogCount)")
            dataRow("Avg Caffeine", cd.caffeineLogCount > 0 ? String(format: "%.0f mg", cd.avgCaffeineMg) : "—")
            dataRow("Alcohol Logs", "\(cd.alcoholLogCount)")
            dataRow("Avg Drinks/Log", cd.alcoholLogCount > 0 ? String(format: "%.1f", cd.avgDrinks) : "—")
            dataRow("High Hypo Risk Events", "\(cd.highHypoRiskCount)", color: cd.highHypoRiskCount > 0 ? .red : .primary)
        }

        loopySection(for: .pharma)
    }

    // MARK: - Tab 2: Devices

    @ViewBuilder
    private var devicesContent: some View {
        constituencySection(icon: "fork.knife", color: Color(red: 107/255, green: 47/255, blue: 160/255), title: "MEAL → GLUCOSE CORRELATIONS") {
            dataRow("Meal Analyses", "\(cd.mealAnalyses)")
            dataRow("Debriefs Completed", "\(cd.debriefCount)")
            dataRow("Avg Predicted vs Actual", cd.debriefCount > 0 ? String(format: "±%.0f mg/dL", abs(cd.avgPeakDelta)) : "—")
        }

        constituencySection(icon: "bolt.fill", color: .yellow, title: "OVERRIDE USAGE") {
            dataRow("Override Activations", "\(cd.overrideActivations)")
            if cd.overridesByType.isEmpty {
                dataRow("Types", "—")
            } else {
                ForEach(cd.overridesByType, id: \.0) { type, count in
                    dataRow(type, "\(count)")
                }
            }
        }

        constituencySection(icon: "figure.run", color: Color(red: 76/255, green: 175/255, blue: 80/255), title: "AUTOPRESET ENGAGEMENT") {
            dataRow("Preset Activations", "\(cd.presetActivations)")
            if cd.presetsByType.isEmpty {
                dataRow("Activity Types", "—")
            } else {
                ForEach(cd.presetsByType, id: \.0) { type, count in
                    dataRow(type, "\(count)")
                }
            }
        }

        constituencySection(icon: "heart.fill", color: .pink, title: "BIOMETRIC CONTEXT") {
            dataRow("Avg Heart Rate", cd.biometricCount > 0 ? String(format: "%.0f bpm", cd.avgHeartRate) : "—")
            dataRow("Avg HRV", cd.biometricCount > 0 ? String(format: "%.0f ms", cd.avgHRV) : "—")
            dataRow("Total Steps", cd.biometricCount > 0 ? formatNumber(cd.totalSteps) : "—")
            dataRow("Avg Sleep", cd.biometricCount > 0 ? String(format: "%.1f hrs", cd.avgSleepHours) : "—")
        }

        constituencySection(icon: "power", color: .secondary, title: "SESSION BEHAVIOR") {
            dataRow("Total Sessions", "\(cd.sessionCount)")
            dataRow("Active Days", "\(cd.activeDays)")
            dataRow("Sessions/Day", cd.activeDays > 0 ? String(format: "%.1f", cd.sessionsPerDay) : "—")
        }

        loopySection(for: .devices)
    }

    // MARK: - Tab 3: Payers

    @ViewBuilder
    private var payersContent: some View {
        constituencySection(icon: "shield.fill", color: riskTierColor, title: "RISK TIER") {
            dataRow("Classification", cd.glucoseSampleCount > 0 ? riskTierLabel : "—", color: riskTierColor)
            dataRow("Time in Range", cd.glucoseSampleCount > 0 ? pct(cd.glucoseTIR) : "—")
            dataRow("GMI", cd.glucoseSampleCount > 0 ? pct(cd.glucoseGMI) : "—")
        }

        constituencySection(icon: "exclamationmark.triangle.fill", color: .red, title: "HYPO EVENT FREQUENCY") {
            dataRow("Very Low (<54 mg/dL)", cd.glucoseSampleCount > 0 ? pct(cd.glucoseBelow54) : "—", color: .red)
            dataRow("Low (<70 mg/dL)", cd.glucoseSampleCount > 0 ? pct(cd.glucoseBelow70) : "—", color: .orange)
            dataRow("Total Readings", "\(cd.glucoseSampleCount)")
        }

        constituencySection(icon: "wineglass.fill", color: Color(red: 0.9, green: 0.6, blue: 0.1), title: "SUBSTANCE RISK FACTORS") {
            dataRow("Alcohol Logs", "\(cd.alcoholLogCount)")
            dataRow("Avg Drinks/Log", cd.alcoholLogCount > 0 ? String(format: "%.1f", cd.avgDrinks) : "—")
            dataRow("High Hypo Risk Events", "\(cd.highHypoRiskCount)", color: cd.highHypoRiskCount > 0 ? .red : .primary)
        }

        constituencySection(icon: "brain.head.profile", color: Color(red: 26/255, green: 138/255, blue: 158/255), title: "ALGORITHM ADHERENCE") {
            let acceptRate = cd.aiGenerated > 0 ? Double(cd.aiApplied) / Double(cd.aiGenerated) * 100 : 0
            dataRow("Acceptance Rate", cd.aiGenerated > 0 ? pct(acceptRate) : "—", color: acceptRate >= 70 ? .green : (acceptRate >= 40 ? .orange : .red))
            dataRow("Generated", "\(cd.aiGenerated)")
            dataRow("Applied", "\(cd.aiApplied)")
            dataRow("Reverted", "\(cd.aiReverted)")
        }

        constituencySection(icon: "heart.text.square.fill", color: .pink, title: "BIOMETRIC HEALTH MARKERS") {
            dataRow("Resting Heart Rate", cd.biometricCount > 0 ? String(format: "%.0f bpm", cd.avgHeartRate) : "—")
            dataRow("Sleep Duration", cd.biometricCount > 0 ? String(format: "%.1f hrs", cd.avgSleepHours) : "—")
            dataRow("HRV", cd.biometricCount > 0 ? String(format: "%.0f ms", cd.avgHRV) : "—")
        }

        loopySection(for: .payers)
    }

    // MARK: - Tab 4: Research

    @ViewBuilder
    private var researchContent: some View {
        constituencySection(icon: "waveform.path.ecg", color: .red, title: "AGP-STANDARD GLUCOSE") {
            dataRow("Mean Glucose", cd.glucoseSampleCount > 0 ? String(format: "%.1f mg/dL", cd.glucoseAvg) : "—")
            dataRow("Std Deviation", cd.glucoseSampleCount > 0 ? String(format: "%.1f mg/dL", cd.glucoseStdDev) : "—")
            dataRow("CV", cd.glucoseSampleCount > 0 ? pct(cd.glucoseCV) : "—")
            dataRow("GMI", cd.glucoseSampleCount > 0 ? pct(cd.glucoseGMI) : "—")
            Divider()
            dataRow("Very Low (<54)", cd.glucoseSampleCount > 0 ? pct(cd.glucoseBelow54) : "—")
            dataRow("Low (54-69)", cd.glucoseSampleCount > 0 ? pct(cd.glucoseBelow70 - cd.glucoseBelow54) : "—")
            dataRow("In Range (70-180)", cd.glucoseSampleCount > 0 ? pct(cd.glucoseTIR) : "—", color: .green)
            dataRow("High (181-250)", cd.glucoseSampleCount > 0 ? pct(cd.glucoseAbove180 - cd.glucoseAbove250) : "—")
            dataRow("Very High (>250)", cd.glucoseSampleCount > 0 ? pct(cd.glucoseAbove250) : "—")
            Divider()
            dataRow("Sample Count", "\(cd.glucoseSampleCount)")
        }

        constituencySection(icon: "syringe.fill", color: .orange, title: "INSULIN DELIVERY DETAIL") {
            dataRow("Total Daily Dose", cd.deliveryCount > 0 ? String(format: "%.2f U", cd.totalDailyDose) : "—")
            dataRow("Basal Units", cd.deliveryCount > 0 ? String(format: "%.2f U", cd.basalUnits) : "—")
            dataRow("Bolus Units", cd.deliveryCount > 0 ? String(format: "%.2f U", cd.bolusUnits) : "—")
            dataRow("Delivery Records", "\(cd.deliveryCount)")
        }

        constituencySection(icon: "fork.knife", color: Color(red: 107/255, green: 47/255, blue: 160/255), title: "CARBOHYDRATE INTAKE") {
            dataRow("Daily Avg Carbs", cd.mealCount > 0 ? String(format: "%.0f g", cd.dailyAvgCarbs) : "—")
            dataRow("Total Meals", "\(cd.mealCount)")
            dataRow("Avg Carbs/Meal", cd.mealCount > 0 ? String(format: "%.0f g", cd.avgCarbsPerMeal) : "—")
        }

        constituencySection(icon: "chart.line.uptrend.xyaxis", color: .blue, title: "MEAL DEBRIEF ACCURACY") {
            dataRow("Debriefs Completed", "\(cd.debriefCount)")
            dataRow("Avg Predicted vs Actual", cd.debriefCount > 0 ? String(format: "±%.0f mg/dL", abs(cd.avgPeakDelta)) : "—")
        }

        constituencySection(icon: "checkmark.seal.fill", color: .green, title: "DATA COMPLETENESS") {
            if let start = cd.dataStartDate, let end = cd.dataEndDate {
                dataRow("Date Range", "\(formatDateShort(start)) – \(formatDateShort(end))")
            } else {
                dataRow("Date Range", "—")
            }
            dataRow("Days with Data", "\(cd.daysWithData)")
            if !cd.eventsByTypeCount.isEmpty {
                Divider()
                ForEach(cd.eventsByTypeCount, id: \.0) { type, count in
                    dataRow(displayName(for: type), "\(count)")
                }
            }
        }

        loopySection(for: .research)
    }

    // MARK: - Tab 5: Digital Health

    @ViewBuilder
    private var digitalHealthContent: some View {
        constituencySection(icon: "app.badge.checkmark.fill", color: .blue, title: "FEATURE ADOPTION") {
            if cd.activeFeatures.isEmpty {
                dataRow("Active Features", "None detected")
            } else {
                ForEach(cd.activeFeatures, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(feature)
                            .font(.caption)
                        Spacer()
                    }
                }
            }
        }

        constituencySection(icon: "bubble.left.and.bubble.right.fill", color: Color(red: 26/255, green: 138/255, blue: 158/255), title: "AI ENGAGEMENT") {
            dataRow("Chat Messages", "\(cd.chatMessages)")
            dataRow("Voice-Initiated", "\(cd.voiceMessages)")
            dataRow("Text-Initiated", "\(cd.textMessages)")
            dataRow("AI Suggestions", "\(cd.aiGenerated)")
        }

        constituencySection(icon: "camera.viewfinder", color: Color(red: 107/255, green: 47/255, blue: 160/255), title: "FOODFINDER USAGE") {
            dataRow("Meal Analyses", "\(cd.mealAnalyses)")
            dataRow("Barcode Scans", "\(cd.barcodeScans)")
            dataRow("Meals Confirmed", "\(cd.mealsConfirmed)")
            let confirmRate = cd.mealAnalyses > 0 ? Double(cd.mealsConfirmed) / Double(cd.mealAnalyses) * 100 : 0
            dataRow("Confirmation Rate", cd.mealAnalyses > 0 ? pct(confirmRate) : "—")
        }

        constituencySection(icon: "chart.line.uptrend.xyaxis", color: .green, title: "APP STICKINESS") {
            dataRow("Total Sessions", "\(cd.sessionCount)")
            dataRow("Days Active", "\(cd.activeDays)")
            dataRow("Sessions/Day", cd.activeDays > 0 ? String(format: "%.1f", cd.sessionsPerDay) : "—")
        }

        constituencySection(icon: "brain", color: .purple, title: "BEHAVIORAL INSIGHTS") {
            dataRow("Override Activations", "\(cd.overrideActivations)")
            dataRow("Preset Activations", "\(cd.presetActivations)")
            dataRow("Settings Changes", "\(cd.settingsChanges)")
            dataRow("AI-Suggested Changes", "\(cd.aiSuggestedChanges)")
        }

        loopySection(for: .digitalHealth)
    }

    // MARK: - Overview Sections

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.blue)
                    Text("OVERVIEW")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                HStack {
                    statCard(value: "\(totalEvents)", label: "Total Events", color: .blue)
                    statCard(value: "\(eventsByType.count)", label: "Event Types", color: .purple)
                    statCard(value: "\(uploadedCount)", label: "Uploaded", color: .green)
                    statCard(value: "\(pendingCount)", label: "Pending", color: .orange)
                }
            }
        }
    }

    private var dailyTrendSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("DAILY VOLUME (14 DAYS)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                if dailyCounts.isEmpty {
                    Text("No data yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    let maxCount = dailyCounts.map(\.1).max() ?? 1
                    ForEach(dailyCounts, id: \.0) { day, count in
                        HStack(spacing: 8) {
                            Text(shortDate(day))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 45, alignment: .trailing)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: max(2, geo.size.width * CGFloat(count) / CGFloat(maxCount)))
                            }
                            .frame(height: 14)

                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 35, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var eventsByTypeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundColor(.purple)
                    Text("EVENTS BY TYPE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                if eventsByType.isEmpty {
                    Text("No events recorded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    let maxCount = eventsByType.first?.1 ?? 1
                    ForEach(eventsByType, id: \.0) { type, count in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: iconForEventType(type))
                                    .foregroundColor(colorForEventType(type))
                                    .frame(width: 16)
                                Text(displayName(for: type))
                                    .font(.caption)
                                Spacer()
                                Text("\(count)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorForEventType(type).opacity(0.4))
                                    .frame(width: max(2, geo.size.width * CGFloat(count) / CGFloat(maxCount)))
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    private var uploadStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundColor(.green)
                    Text("UPLOAD STATUS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                if totalEvents == 0 {
                    Text("No events to upload")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            ForEach(uploadStatus, id: \.0) { status, count in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(colorForStatus(status))
                                    .frame(width: max(2, geo.size.width * CGFloat(count) / CGFloat(totalEvents)))
                            }
                        }
                    }
                    .frame(height: 20)

                    HStack(spacing: 16) {
                        ForEach(uploadStatus, id: \.0) { status, count in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(colorForStatus(status))
                                    .frame(width: 8, height: 8)
                                Text("\(status): \(count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentEventsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.blue)
                    Text("RECENT EVENTS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                if recentEvents.isEmpty {
                    Text("No events yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recentEvents, id: \.id) { event in
                        HStack {
                            Image(systemName: iconForEventType(event.eventType.rawValue))
                                .foregroundColor(colorForEventType(event.eventType.rawValue))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: event.eventType.rawValue))
                                    .font(.caption)
                                Text(event.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            statusBadge(event.uploadStatus.rawValue)
                        }
                        if event.id != recentEvents.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - UI Helpers

    private func constituencySection<Content: View>(
        icon: String,
        color: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                content()
            }
        }
    }

    private func dataRow(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colorForStatus(status).opacity(0.15))
            .foregroundColor(colorForStatus(status))
            .cornerRadius(4)
    }

    // MARK: - Ask Loopy!

    private enum Constituency {
        case pharma, devices, payers, research, digitalHealth
    }

    private static let loopyTeal = Color(red: 26/255, green: 138/255, blue: 158/255)

    @ViewBuilder
    private func loopySection(for constituency: Constituency) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(Self.loopyTeal)
                    Text("ASK LOOPY!")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                // Quick-ask chips (hidden when response is showing)
                if loopyResponse.isEmpty && loopyError.isEmpty && !loopyIsLoading {
                    VStack(spacing: 6) {
                        ForEach(quickChips(for: constituency), id: \.self) { chip in
                            Button {
                                loopyQuery = chip
                                sendLoopyQuery(for: constituency)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkle")
                                        .font(.caption2)
                                    Text(chip)
                                        .font(.caption)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Self.loopyTeal.opacity(0.08))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Self.loopyTeal)
                        }
                    }
                }

                // Text field + send
                HStack(spacing: 8) {
                    TextField("Ask about this data...", text: $loopyQuery)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .disabled(loopyIsLoading)
                        .onSubmit {
                            if !loopyQuery.trimmingCharacters(in: .whitespaces).isEmpty && !loopyIsLoading {
                                sendLoopyQuery(for: constituency)
                            }
                        }

                    Button {
                        sendLoopyQuery(for: constituency)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundColor(
                                loopyQuery.trimmingCharacters(in: .whitespaces).isEmpty || loopyIsLoading
                                    ? .gray
                                    : Self.loopyTeal
                            )
                    }
                    .disabled(loopyQuery.trimmingCharacters(in: .whitespaces).isEmpty || loopyIsLoading)
                    .buttonStyle(.plain)
                }

                // Loading state
                if loopyIsLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loopy is thinking...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Error state
                if !loopyError.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(loopyError)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button("Clear") {
                            loopyError = ""
                            loopyResponse = ""
                        }
                        .font(.caption)
                        .foregroundColor(Self.loopyTeal)
                    }
                }

                // Response card
                if !loopyResponse.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                            Text("Loopy says:")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)

                        Text(loopyResponse)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.95))
                    }
                    .padding(12)
                    .background(Self.loopyTeal)
                    .cornerRadius(10)

                    HStack {
                        Spacer()
                        Button("Clear") {
                            loopyResponse = ""
                            loopyError = ""
                        }
                        .font(.caption)
                        .foregroundColor(Self.loopyTeal)
                    }
                }
            }
        }
    }

    private func quickChips(for constituency: Constituency) -> [String] {
        switch constituency {
        case .pharma:
            return [
                "Is my glucose control improving or declining?",
                "What's my AI therapy acceptance rate telling you?",
                "How do caffeine and alcohol affect my numbers?"
            ]
        case .devices:
            return [
                "How accurate are my meal predictions vs actual?",
                "Which AutoPreset activity type do I use most?",
                "What does my session behavior say about engagement?"
            ]
        case .payers:
            return [
                "What risk tier am I in and why?",
                "How often do I go dangerously low?",
                "Am I following algorithm recommendations?"
            ]
        case .research:
            return [
                "Summarize my AGP glucose stats in plain English",
                "What's my data completeness look like?",
                "How does my insulin split compare to typical?"
            ]
        case .digitalHealth:
            return [
                "Which features am I actually using?",
                "How sticky is this app for me?",
                "What's my AI engagement trend?"
            ]
        }
    }

    private func loopySystemPrompt(for constituency: Constituency) -> String {
        let shared = "You are Loopy, a friendly and slightly playful AI data analyst for a diabetes management app. Be concise (2-4 sentences), use specific numbers from the data provided, and never give medical advice."

        switch constituency {
        case .pharma:
            return shared + " You are acting as a pharmaceutical data analyst reviewing drug efficacy and therapy adherence metrics."
        case .devices:
            return shared + " You are acting as a medical device insights specialist analyzing pump, CGM, and meal tracking usage patterns."
        case .payers:
            return shared + " You are acting as a health insurance analytics expert evaluating risk stratification and cost-related markers."
        case .research:
            return shared + " You are acting as a clinical research data scientist reviewing AGP-standard glucose metrics and data quality."
        case .digitalHealth:
            return shared + " You are acting as a product growth analyst evaluating feature adoption, retention, and engagement."
        }
    }

    private func buildLoopyContext(for constituency: Constituency) -> String {
        switch constituency {
        case .pharma:
            return """
            GLUCOSE: avg=\(Int(cd.glucoseAvg))mg/dL, TIR=\(String(format:"%.1f",cd.glucoseTIR))%, GMI=\(String(format:"%.1f",cd.glucoseGMI))%, CV=\(String(format:"%.1f",cd.glucoseCV))%, below54=\(String(format:"%.1f",cd.glucoseBelow54))%, below70=\(String(format:"%.1f",cd.glucoseBelow70))%, above180=\(String(format:"%.1f",cd.glucoseAbove180))%, above250=\(String(format:"%.1f",cd.glucoseAbove250))%, samples=\(cd.glucoseSampleCount)
            INSULIN: TDD=\(String(format:"%.1f",cd.totalDailyDose))U, basal=\(String(format:"%.1f",cd.basalUnits))U, bolus=\(String(format:"%.1f",cd.bolusUnits))U
            AI ADHERENCE: generated=\(cd.aiGenerated), applied=\(cd.aiApplied), dismissed=\(cd.aiDismissed), reverted=\(cd.aiReverted)
            SETTINGS: changes=\(cd.settingsChanges), aiSuggested=\(cd.aiSuggestedChanges), manual=\(cd.manualChanges)
            SUBSTANCES: caffeineLogs=\(cd.caffeineLogCount), avgCaffeine=\(String(format:"%.0f",cd.avgCaffeineMg))mg, alcoholLogs=\(cd.alcoholLogCount), avgDrinks=\(String(format:"%.1f",cd.avgDrinks)), highHypoRisk=\(cd.highHypoRiskCount)
            """

        case .devices:
            let presets = cd.presetsByType.map { "\($0.0):\($0.1)" }.joined(separator: ", ")
            let overrides = cd.overridesByType.map { "\($0.0):\($0.1)" }.joined(separator: ", ")
            return """
            MEALS: analyses=\(cd.mealAnalyses), debriefs=\(cd.debriefCount), avgPredVsActual=±\(String(format:"%.0f",abs(cd.avgPeakDelta)))mg/dL, barcodeScans=\(cd.barcodeScans), confirmed=\(cd.mealsConfirmed)
            GLUCOSE CONTEXT: avg=\(Int(cd.glucoseAvg))mg/dL, TIR=\(String(format:"%.1f",cd.glucoseTIR))%, samples=\(cd.glucoseSampleCount)
            OVERRIDES: activations=\(cd.overrideActivations), types=[\(overrides)]
            PRESETS: activations=\(cd.presetActivations), types=[\(presets)]
            BIOMETRICS: avgHR=\(String(format:"%.0f",cd.avgHeartRate))bpm, avgHRV=\(String(format:"%.0f",cd.avgHRV))ms, steps=\(String(format:"%.0f",cd.totalSteps)), avgSleep=\(String(format:"%.1f",cd.avgSleepHours))hrs, records=\(cd.biometricCount)
            SESSIONS: total=\(cd.sessionCount), activeDays=\(cd.activeDays), perDay=\(String(format:"%.1f",cd.sessionsPerDay))
            """

        case .payers:
            let acceptRate = cd.aiGenerated > 0 ? Double(cd.aiApplied) / Double(cd.aiGenerated) * 100 : 0
            return """
            RISK TIER: TIR=\(String(format:"%.1f",cd.glucoseTIR))%, GMI=\(String(format:"%.1f",cd.glucoseGMI))%, classification=\(riskTierLabel)
            HYPO EVENTS: below54=\(String(format:"%.1f",cd.glucoseBelow54))%, below70=\(String(format:"%.1f",cd.glucoseBelow70))%, totalReadings=\(cd.glucoseSampleCount)
            SUBSTANCE RISK: alcoholLogs=\(cd.alcoholLogCount), avgDrinks=\(String(format:"%.1f",cd.avgDrinks)), highHypoRisk=\(cd.highHypoRiskCount)
            ALGORITHM ADHERENCE: acceptanceRate=\(String(format:"%.1f",acceptRate))%, generated=\(cd.aiGenerated), applied=\(cd.aiApplied), reverted=\(cd.aiReverted)
            BIOMETRICS: restingHR=\(String(format:"%.0f",cd.avgHeartRate))bpm, sleep=\(String(format:"%.1f",cd.avgSleepHours))hrs, HRV=\(String(format:"%.0f",cd.avgHRV))ms
            """

        case .research:
            let typeBreakdown = cd.eventsByTypeCount.map { "\($0.0):\($0.1)" }.joined(separator: ", ")
            let startStr = cd.dataStartDate.map { formatDateShort($0) } ?? "N/A"
            let endStr = cd.dataEndDate.map { formatDateShort($0) } ?? "N/A"
            return """
            AGP GLUCOSE: mean=\(String(format:"%.1f",cd.glucoseAvg))mg/dL, SD=\(String(format:"%.1f",cd.glucoseStdDev))mg/dL, CV=\(String(format:"%.1f",cd.glucoseCV))%, GMI=\(String(format:"%.1f",cd.glucoseGMI))%
            RANGES: veryLow(<54)=\(String(format:"%.1f",cd.glucoseBelow54))%, low(54-69)=\(String(format:"%.1f",cd.glucoseBelow70 - cd.glucoseBelow54))%, inRange(70-180)=\(String(format:"%.1f",cd.glucoseTIR))%, high(181-250)=\(String(format:"%.1f",cd.glucoseAbove180 - cd.glucoseAbove250))%, veryHigh(>250)=\(String(format:"%.1f",cd.glucoseAbove250))%
            INSULIN: TDD=\(String(format:"%.2f",cd.totalDailyDose))U, basal=\(String(format:"%.2f",cd.basalUnits))U, bolus=\(String(format:"%.2f",cd.bolusUnits))U, records=\(cd.deliveryCount)
            CARBS: dailyAvg=\(String(format:"%.0f",cd.dailyAvgCarbs))g, meals=\(cd.mealCount), avgPerMeal=\(String(format:"%.0f",cd.avgCarbsPerMeal))g
            DEBRIEFS: count=\(cd.debriefCount), avgPredVsActual=±\(String(format:"%.0f",abs(cd.avgPeakDelta)))mg/dL
            COMPLETENESS: range=\(startStr)–\(endStr), daysWithData=\(cd.daysWithData), samples=\(cd.glucoseSampleCount)
            EVENT TYPES: [\(typeBreakdown)]
            """

        case .digitalHealth:
            let features = cd.activeFeatures.joined(separator: ", ")
            let confirmRate = cd.mealAnalyses > 0 ? Double(cd.mealsConfirmed) / Double(cd.mealAnalyses) * 100 : 0
            let acceptRate = cd.aiGenerated > 0 ? Double(cd.aiApplied) / Double(cd.aiGenerated) * 100 : 0
            return """
            FEATURES ACTIVE: [\(features)]
            AI ENGAGEMENT: chatMessages=\(cd.chatMessages), voice=\(cd.voiceMessages), text=\(cd.textMessages), aiSuggestions=\(cd.aiGenerated), acceptRate=\(String(format:"%.1f",acceptRate))%
            FOODFINDER: analyses=\(cd.mealAnalyses), barcodeScans=\(cd.barcodeScans), confirmed=\(cd.mealsConfirmed), confirmRate=\(String(format:"%.1f",confirmRate))%
            STICKINESS: sessions=\(cd.sessionCount), activeDays=\(cd.activeDays), sessionsPerDay=\(String(format:"%.1f",cd.sessionsPerDay))
            BEHAVIORAL: overrides=\(cd.overrideActivations), presets=\(cd.presetActivations), settingsChanges=\(cd.settingsChanges), aiSuggestedChanges=\(cd.aiSuggestedChanges)
            """
        }
    }

    private func sendLoopyQuery(for constituency: Constituency) {
        let question = loopyQuery.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }

        loopyIsLoading = true
        loopyError = ""
        loopyResponse = ""

        let systemPrompt = loopySystemPrompt(for: constituency)
        let context = buildLoopyContext(for: constituency)
        let userPrompt = """
        Here is the user's 14-day data summary:

        \(context)

        User question: \(question)
        """

        Task {
            do {
                let response = try await LoopInsights_AIServiceAdapter.shared.sendPrompt(systemPrompt, userPrompt: userPrompt)
                await MainActor.run {
                    loopyResponse = response
                    loopyQuery = ""
                    loopyIsLoading = false
                }
            } catch {
                await MainActor.run {
                    loopyError = error.localizedDescription
                    loopyIsLoading = false
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        totalEvents = store.eventCount()
        eventsByType = store.eventCountsByType()
        uploadStatus = store.uploadStatusCounts()
        dailyCounts = store.dailyEventCounts(days: 14)
        recentEvents = store.recentEvents(limit: 25)
    }

    private func loadConstituencyData() {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -14, to: end)!
        let allEvents = store.events(from: start, to: end)

        var data = ConstituencyData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var allReadings: [Double] = []
        var totalInsulin: Double = 0
        var totalBasal: Double = 0
        var totalBolus: Double = 0
        var insulinRecords = 0
        var totalCarbs: Double = 0
        var carbEntries = 0
        var totalCaffeineMg: Double = 0
        var totalDrinks: Double = 0
        var totalPeakDelta: Double = 0
        var debriefCount = 0
        var totalHR: Double = 0
        var totalHRV: Double = 0
        var totalSteps: Double = 0
        var totalSleep: Double = 0
        var bioCount = 0
        var presetCounts: [String: Int] = [:]
        var overrideCounts: [String: Int] = [:]
        var typeCounts: [String: Int] = [:]
        var uniqueDays = Set<String>()
        var sessionDays = Set<String>()

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"

        for event in allEvents {
            let dayKey = dayFmt.string(from: event.timestamp)
            uniqueDays.insert(dayKey)
            typeCounts[event.eventType.rawValue, default: 0] += 1

            switch event.eventType {
            case .glucoseSample:
                if let p = try? decoder.decode(DataLayer_GlucoseSamplePayload.self, from: event.payload) {
                    for r in p.readings {
                        allReadings.append(r.mgdl)
                    }
                }

            case .insulinDelivery:
                if let p = try? decoder.decode(DataLayer_InsulinDeliveryPayload.self, from: event.payload) {
                    for d in p.deliveries {
                        totalInsulin += d.units
                        if d.type == "bolus" {
                            totalBolus += d.units
                        } else {
                            totalBasal += d.units
                        }
                        insulinRecords += 1
                    }
                }

            case .carbEntry:
                if let p = try? decoder.decode(DataLayer_CarbEntryPayload.self, from: event.payload) {
                    for e in p.entries {
                        totalCarbs += e.grams
                        carbEntries += 1
                    }
                }

            case .mealAnalysis:
                data.mealAnalyses += 1

            case .mealConfirmed:
                data.mealsConfirmed += 1

            case .barcodeScanned:
                data.barcodeScans += 1

            case .aiSuggestionGenerated:
                data.aiGenerated += 1
            case .aiSuggestionApplied:
                data.aiApplied += 1
            case .aiSuggestionDismissed:
                data.aiDismissed += 1
            case .aiSuggestionReverted:
                data.aiReverted += 1

            case .chatMessage:
                data.chatMessages += 1
                if let p = try? decoder.decode(DataLayer_ChatTopicPayload.self, from: event.payload) {
                    if p.isVoiceInitiated {
                        data.voiceMessages += 1
                    } else {
                        data.textMessages += 1
                    }
                }

            case .mealDebrief:
                if let p = try? decoder.decode(DataLayer_MealDebriefPayload.self, from: event.payload),
                   let predicted = p.predictedPeakMgDl, let actual = p.actualPeakMgDl {
                    totalPeakDelta += abs(predicted - actual)
                    debriefCount += 1
                }

            case .caffeineLogged:
                data.caffeineLogCount += 1
                if let p = try? decoder.decode(DataLayer_CaffeineLoggedPayload.self, from: event.payload) {
                    totalCaffeineMg += p.milligrams
                }

            case .alcoholLogged:
                data.alcoholLogCount += 1
                if let p = try? decoder.decode(DataLayer_AlcoholLoggedPayload.self, from: event.payload) {
                    totalDrinks += p.standardDrinks
                    if p.hypoRiskLevel == "high" || p.hypoRiskLevel == "elevated" {
                        data.highHypoRiskCount += 1
                    }
                }

            case .presetActivated:
                data.presetActivations += 1
                if let p = try? decoder.decode(DataLayer_PresetEventPayload.self, from: event.payload) {
                    presetCounts[p.activityType, default: 0] += 1
                }

            case .presetDeactivated, .activityDetected:
                break

            case .biometricSnapshot:
                if let p = try? decoder.decode(DataLayer_BiometricSnapshotPayload.self, from: event.payload) {
                    if let hr = p.avgHeartRate { totalHR += hr; bioCount += 1 }
                    if let hrv = p.avgHRV { totalHRV += hrv }
                    if let steps = p.totalSteps { totalSteps += Double(steps) }
                    if let sleep = p.sleepHours { totalSleep += sleep }
                }

            case .therapySettingsChanged:
                data.settingsChanges += 1
                if let p = try? decoder.decode(DataLayer_TherapySettingsChangedPayload.self, from: event.payload) {
                    if p.wasAISuggested {
                        data.aiSuggestedChanges += 1
                    } else {
                        data.manualChanges += 1
                    }
                }

            case .overrideActivated:
                data.overrideActivations += 1
                if let p = try? decoder.decode(DataLayer_OverridePayload.self, from: event.payload) {
                    overrideCounts[p.overrideType, default: 0] += 1
                }

            case .overrideDeactivated:
                break

            case .sessionStart:
                data.sessionCount += 1
                sessionDays.insert(dayKey)

            case .sessionEnd, .backgroundAlert:
                break
            }
        }

        // Glucose stats
        if !allReadings.isEmpty {
            let n = Double(allReadings.count)
            let avg = allReadings.reduce(0, +) / n
            let variance = allReadings.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / n
            let sd = sqrt(variance)
            data.glucoseAvg = avg
            data.glucoseStdDev = sd
            data.glucoseCV = avg > 0 ? (sd / avg) * 100 : 0
            data.glucoseGMI = 3.31 + 0.02392 * avg
            data.glucoseSampleCount = allReadings.count

            let count = allReadings.count
            data.glucoseBelow54 = Double(allReadings.filter { $0 < 54 }.count) / Double(count) * 100
            data.glucoseBelow70 = Double(allReadings.filter { $0 < 70 }.count) / Double(count) * 100
            data.glucoseTIR = Double(allReadings.filter { $0 >= 70 && $0 <= 180 }.count) / Double(count) * 100
            data.glucoseAbove180 = Double(allReadings.filter { $0 > 180 }.count) / Double(count) * 100
            data.glucoseAbove250 = Double(allReadings.filter { $0 > 250 }.count) / Double(count) * 100
        }

        // Insulin stats (per-day averages)
        let daysActive = max(1, uniqueDays.count)
        data.deliveryCount = insulinRecords
        data.totalDailyDose = totalInsulin / Double(daysActive)
        data.basalUnits = totalBasal / Double(daysActive)
        data.bolusUnits = totalBolus / Double(daysActive)

        // Carb stats
        data.totalCarbs = totalCarbs
        data.mealCount = carbEntries
        data.dailyAvgCarbs = totalCarbs / Double(daysActive)
        data.avgCarbsPerMeal = carbEntries > 0 ? totalCarbs / Double(carbEntries) : 0

        // Substance stats
        data.avgCaffeineMg = data.caffeineLogCount > 0 ? totalCaffeineMg / Double(data.caffeineLogCount) : 0
        data.avgDrinks = data.alcoholLogCount > 0 ? totalDrinks / Double(data.alcoholLogCount) : 0

        // Debrief stats
        data.debriefCount = debriefCount
        data.avgPeakDelta = debriefCount > 0 ? totalPeakDelta / Double(debriefCount) : 0

        // Biometric stats
        data.biometricCount = bioCount
        if bioCount > 0 {
            data.avgHeartRate = totalHR / Double(bioCount)
            data.avgHRV = totalHRV / Double(bioCount)
            data.totalSteps = totalSteps
            data.avgSleepHours = totalSleep / Double(bioCount)
        }

        // Preset/Override breakdowns
        data.presetsByType = presetCounts.sorted { $0.value > $1.value }
        data.overridesByType = overrideCounts.sorted { $0.value > $1.value }

        // Session stats
        data.activeDays = sessionDays.count
        data.sessionsPerDay = sessionDays.count > 0 ? Double(data.sessionCount) / Double(sessionDays.count) : 0

        // Feature adoption (detect from event presence)
        var features: [String] = []
        if data.mealAnalyses > 0 || data.barcodeScans > 0 { features.append("FoodFinder") }
        if data.aiGenerated > 0 || data.chatMessages > 0 { features.append("LoopInsights AI") }
        if data.presetActivations > 0 { features.append("AutoPresets") }
        if debriefCount > 0 { features.append("Meal Debrief") }
        if data.caffeineLogCount > 0 { features.append("Caffeine Tracking") }
        if data.alcoholLogCount > 0 { features.append("Alcohol Tracking") }
        if data.overrideActivations > 0 { features.append("Overrides") }
        data.activeFeatures = features

        // Data completeness
        data.daysWithData = uniqueDays.count
        if let first = allEvents.last?.timestamp { data.dataStartDate = first }
        if let last = allEvents.first?.timestamp { data.dataEndDate = last }
        data.eventsByTypeCount = typeCounts.sorted { $0.value > $1.value }

        cd = data
    }

    // MARK: - Computed

    private var uploadedCount: Int {
        uploadStatus.first(where: { $0.0 == "uploaded" })?.1 ?? 0
    }

    private var pendingCount: Int {
        uploadStatus.first(where: { $0.0 == "pending" })?.1 ?? 0
    }

    private var riskTierLabel: String {
        if cd.glucoseTIR >= 70 { return "Low Risk" }
        if cd.glucoseTIR >= 50 { return "Moderate Risk" }
        return "High Risk"
    }

    private var riskTierColor: Color {
        if cd.glucoseTIR >= 70 { return .green }
        if cd.glucoseTIR >= 50 { return .orange }
        return .red
    }

    // MARK: - Formatting Helpers

    private func pct(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func formatDateShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }

    private func shortDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return month < months.count ? "\(months[month]) \(day)" : dateStr
    }

    private func displayName(for type: String) -> String {
        switch type {
        case "glucoseSample": return "Glucose"
        case "insulinDelivery": return "Insulin"
        case "carbEntry": return "Carbs"
        case "mealAnalysis": return "Meal Analysis"
        case "mealConfirmed": return "Meal Confirmed"
        case "barcodeScanned": return "Barcode Scan"
        case "aiSuggestionGenerated": return "AI Generated"
        case "aiSuggestionApplied": return "AI Applied"
        case "aiSuggestionDismissed": return "AI Dismissed"
        case "aiSuggestionReverted": return "AI Reverted"
        case "chatMessage": return "Chat"
        case "backgroundAlert": return "Alert"
        case "mealDebrief": return "Meal Debrief"
        case "caffeineLogged": return "Caffeine"
        case "alcoholLogged": return "Alcohol"
        case "presetActivated": return "Preset On"
        case "presetDeactivated": return "Preset Off"
        case "activityDetected": return "Activity"
        case "biometricSnapshot": return "Biometrics"
        case "therapySettingsChanged": return "Settings Change"
        case "overrideActivated": return "Override On"
        case "overrideDeactivated": return "Override Off"
        case "sessionStart": return "Session Start"
        case "sessionEnd": return "Session End"
        default: return type
        }
    }

    private func iconForEventType(_ type: String) -> String {
        switch type {
        case "glucoseSample": return "drop.fill"
        case "insulinDelivery": return "syringe.fill"
        case "carbEntry", "mealAnalysis", "mealConfirmed", "mealDebrief": return "fork.knife"
        case "barcodeScanned": return "barcode.viewfinder"
        case "aiSuggestionGenerated", "aiSuggestionApplied", "aiSuggestionDismissed", "aiSuggestionReverted": return "brain.head.profile"
        case "chatMessage": return "bubble.left.fill"
        case "backgroundAlert": return "bell.fill"
        case "caffeineLogged": return "cup.and.saucer.fill"
        case "alcoholLogged": return "wineglass.fill"
        case "presetActivated", "presetDeactivated", "activityDetected": return "figure.run"
        case "biometricSnapshot": return "heart.fill"
        case "therapySettingsChanged": return "gearshape.fill"
        case "overrideActivated", "overrideDeactivated": return "bolt.fill"
        case "sessionStart", "sessionEnd": return "power"
        default: return "circle.fill"
        }
    }

    private func colorForEventType(_ type: String) -> Color {
        switch type {
        case "glucoseSample": return .red
        case "insulinDelivery": return .orange
        case "carbEntry", "mealAnalysis", "mealConfirmed", "mealDebrief", "barcodeScanned": return Color(red: 107/255, green: 47/255, blue: 160/255)
        case "aiSuggestionGenerated", "aiSuggestionApplied", "aiSuggestionDismissed", "aiSuggestionReverted", "chatMessage", "backgroundAlert": return Color(red: 26/255, green: 138/255, blue: 158/255)
        case "caffeineLogged": return .brown
        case "alcoholLogged": return Color(red: 0.9, green: 0.6, blue: 0.1)
        case "presetActivated", "presetDeactivated", "activityDetected": return Color(red: 76/255, green: 175/255, blue: 80/255)
        case "biometricSnapshot": return .pink
        case "therapySettingsChanged": return .gray
        case "overrideActivated", "overrideDeactivated": return .yellow
        case "sessionStart", "sessionEnd": return .secondary
        default: return .blue
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "pending": return .orange
        case "uploading": return .blue
        case "uploaded": return .green
        case "failed": return .red
        case "redacted": return .gray
        default: return .secondary
        }
    }
}
