//
//  FoodFinder_CarbTrackingDashboard.swift
//  Loop
//
//  FoodFinder — Carb tracking card and full dashboard.
//  Card shows today's carbs with same-day-last-week comparison.
//  Dashboard shows daily bar chart, weekly averages, day-of-week
//  patterns, and food type breakdown over a selectable time period.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI
import Charts

// MARK: - Compact Card (shown in CarbEntryView)

struct FoodFinder_CarbTrackingCard: View {
    let service: FoodFinder_CarbTrackingService

    @State private var snapshot: FoodFinder_CarbSnapshot?
    @State private var showDashboard = false

    private let purple = Color(red: 107/255, green: 47/255, blue: 160/255)

    var body: some View {
        Group {
            if let snap = snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(purple)
                        Text("CARB TRACKING")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 26)

                    Button(action: { showDashboard = true }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(Int(snap.todayCarbs))g today")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("(\(snap.todayMealCount) \(snap.todayMealCount == 1 ? "meal" : "meals"))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let lastWeekCarbs = snap.sameWeekdayLastWeekCarbs,
                               let delta = snap.deltaFromLastWeek {
                                HStack(spacing: 4) {
                                    Text(weekdayName(snap.fetchDate))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("last week: \(Int(lastWeekCarbs))g")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("(\(delta >= 0 ? "+" : "")\(Int(delta))g)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(delta > 0 ? .orange : .green)
                                }
                            }

                            if let weekAvg = snap.weeklyAverage {
                                Text("7-day avg: \(Int(weekAvg))g/day")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CardBackground())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
                .sheet(isPresented: $showDashboard) {
                    NavigationView {
                        FoodFinder_CarbTrackingDashboard()
                            .navigationTitle("Carb Tracking")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") { showDashboard = false }
                                }
                            }
                    }
                }
            }
        }
        .task {
            snapshot = await service.fetchSnapshot()
        }
    }

    private func weekdayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

// MARK: - Full Dashboard

struct FoodFinder_CarbTrackingDashboard: View {
    @State private var selectedPeriod: FoodFinder_CarbPeriod = .week
    @State private var dailySummaries: [FoodFinder_DailyCarbSummary] = []
    @State private var weeklySummaries: [FoodFinder_WeeklyCarbSummary] = []
    @State private var dayOfWeekPatterns: [FoodFinder_DayOfWeekPattern] = []
    @State private var foodTypeBreakdown: [(foodType: String, totalCarbs: Double, count: Int)] = []

    private let service = FoodFinder_CarbTrackingService.shared
    private let purple = Color(red: 107/255, green: 47/255, blue: 160/255)
    private let lightPurple = Color(red: 167/255, green: 117/255, blue: 210/255)

    // Computed display properties
    private var averageDailyCarbs: Double {
        guard !dailySummaries.isEmpty else { return 0 }
        return round(dailySummaries.reduce(0.0) { $0 + $1.totalCarbs } / Double(dailySummaries.count))
    }
    private var totalMeals: Int { dailySummaries.reduce(0) { $0 + $1.mealCount } }
    private var peakDayCarbs: Double { dailySummaries.map(\.totalCarbs).max() ?? 0 }
    private var maxDailyCarbs: Double { max(dailySummaries.map(\.totalCarbs).max() ?? 200, 50) }
    private var maxDayOfWeekCarbs: Double { max(dayOfWeekPatterns.map(\.averageCarbs).max() ?? 200, 50) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                periodPicker
                summaryStatsRow
                dailyCarbsChart
                weeklyAveragesSection
                dayOfWeekSection
                foodTypeSection
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .task { await loadData() }
        .onChange(of: selectedPeriod) { _ in
            Task { await loadData() }
        }
    }

    // MARK: Data Loading

    private func loadData() async {
        let summaries = await service.fetchDailySummaries(period: selectedPeriod)
        dailySummaries = summaries
        weeklySummaries = service.weeklyAverages(from: summaries)
        dayOfWeekPatterns = service.dayOfWeekPatterns(from: summaries)

        let retentionDays = UserDefaults.standard.analysisHistoryRetentionDays
        let records = FoodFinder_AnalysisHistoryStore.loadRecords(retentionDays: retentionDays)
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedPeriod.rawValue, to: Date()) ?? Date()

        var grouped: [String: (carbs: Double, count: Int)] = [:]
        for record in records where record.date >= cutoff {
            let type = record.foodType.isEmpty ? "Other" : record.foodType
            let existing = grouped[type] ?? (carbs: 0, count: 0)
            grouped[type] = (carbs: existing.carbs + record.carbsGrams, count: existing.count + 1)
        }
        foodTypeBreakdown = grouped.map { (foodType: $0.key, totalCarbs: round($0.value.carbs), count: $0.value.count) }
            .sorted { $0.totalCarbs > $1.totalCarbs }
    }

    // MARK: Period Picker

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(FoodFinder_CarbPeriod.allCases) { period in
                Text(period.label).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: Summary Stats

    private var summaryStatsRow: some View {
        HStack(spacing: 12) {
            statCard(title: "Avg Daily", value: "\(Int(averageDailyCarbs))g", icon: "chart.line.uptrend.xyaxis")
            statCard(title: "Total Meals", value: "\(totalMeals)", icon: "fork.knife")
            statCard(title: "Peak Day", value: "\(Int(peakDayCarbs))g", icon: "arrow.up.circle")
        }
        .padding(.horizontal)
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(purple)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(CardBackground())
    }

    // MARK: Daily Carbs Bar Chart

    private var dailyCarbsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Carbs")
                .font(.headline)
                .padding(.horizontal)

            if dailySummaries.isEmpty {
                Text("No carb data for this period")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if #available(iOS 16, *) {
                Chart(dailySummaries) { summary in
                    BarMark(
                        x: .value("Date", summary.date, unit: .day),
                        y: .value("Carbs", summary.totalCarbs)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [lightPurple, purple],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(3)
                }
                .chartYAxisLabel("grams")
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(dailySummaries.count / 7, 1))) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        AxisGridLine()
                    }
                }
                .frame(height: 200)
                .padding(.horizontal)
            } else {
                textFallbackChart
            }
        }
        .padding(.vertical, 12)
        .background(CardBackground())
        .padding(.horizontal)
    }

    private var textFallbackChart: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(dailySummaries.suffix(14)) { summary in
                HStack(spacing: 4) {
                    Text(shortDate(summary.date))
                        .font(.caption2)
                        .frame(width: 50, alignment: .leading)
                    GeometryReader { geo in
                        let width = maxDailyCarbs > 0
                            ? CGFloat(summary.totalCarbs / maxDailyCarbs) * geo.size.width
                            : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(purple.opacity(0.7))
                            .frame(width: max(width, 1), height: 12)
                    }
                    .frame(height: 14)
                    Text("\(Int(summary.totalCarbs))g")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: Weekly Averages

    private var weeklyAveragesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Averages")
                .font(.headline)
                .padding(.horizontal)

            if weeklySummaries.isEmpty {
                Text("Not enough data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(weeklySummaries) { week in
                    HStack {
                        Text(week.weekLabel)
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(week.avgDailyCarbs))g/day")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("(\(week.mealCount) meals)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 12)
        .background(CardBackground())
        .padding(.horizontal)
    }

    // MARK: Day-of-Week Patterns

    private var dayOfWeekSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Day-of-Week Patterns")
                .font(.headline)
                .padding(.horizontal)

            if dayOfWeekPatterns.isEmpty {
                Text("Not enough data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(dayOfWeekPatterns) { pattern in
                    HStack(spacing: 8) {
                        Text(pattern.dayName)
                            .font(.caption)
                            .frame(width: 32, alignment: .leading)
                        GeometryReader { geo in
                            let width = maxDayOfWeekCarbs > 0
                                ? CGFloat(pattern.averageCarbs / maxDayOfWeekCarbs) * geo.size.width
                                : 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [purple.opacity(0.6), purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(width, 2), height: 16)
                        }
                        .frame(height: 18)
                        Text("\(Int(pattern.averageCarbs))g")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 12)
        .background(CardBackground())
        .padding(.horizontal)
    }

    // MARK: Food Type Breakdown

    private var foodTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Food Types")
                .font(.headline)
                .padding(.horizontal)

            if foodTypeBreakdown.isEmpty {
                Text("No FoodFinder analysis data for this period")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(foodTypeBreakdown.prefix(10), id: \.foodType) { item in
                    HStack {
                        Text(item.foodType)
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(item.totalCarbs))g")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("(\(item.count)x)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 12)
        .background(CardBackground())
        .padding(.horizontal)
    }

    // MARK: Helpers

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}
