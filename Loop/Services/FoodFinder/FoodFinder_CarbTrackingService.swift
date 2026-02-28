//
//  FoodFinder_CarbTrackingService.swift
//  Loop
//
//  FoodFinder — Carb tracking aggregation engine.
//  Queries HealthKit for dietary carbohydrate data and produces
//  daily/weekly/monthly summaries with historical comparisons.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import os.log

// MARK: - Data Types

struct FoodFinder_CarbEntry: Identifiable {
    let id: String
    let date: Date
    let grams: Double
    let foodType: String?
}

struct FoodFinder_DailyCarbSummary: Identifiable {
    let id: String
    let date: Date
    let totalCarbs: Double
    let mealCount: Int
    let entries: [FoodFinder_CarbEntry]

    init(date: Date, totalCarbs: Double, mealCount: Int, entries: [FoodFinder_CarbEntry]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.id = formatter.string(from: date)
        self.date = date
        self.totalCarbs = totalCarbs
        self.mealCount = mealCount
        self.entries = entries
    }
}

struct FoodFinder_CarbSnapshot {
    let todayCarbs: Double
    let todayMealCount: Int
    let sameWeekdayLastWeekCarbs: Double?
    let sameWeekdayLastWeekMealCount: Int?
    let weeklyAverage: Double?
    let monthlyAverage: Double?
    let fetchDate: Date

    var deltaFromLastWeek: Double? {
        guard let lastWeek = sameWeekdayLastWeekCarbs else { return nil }
        return todayCarbs - lastWeek
    }
}

enum FoodFinder_CarbPeriod: Int, CaseIterable, Identifiable {
    case week = 7
    case twoWeeks = 14
    case month = 30
    case threeMonths = 90

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .week: return "7 Days"
        case .twoWeeks: return "14 Days"
        case .month: return "30 Days"
        case .threeMonths: return "90 Days"
        }
    }
}

struct FoodFinder_WeeklyCarbSummary: Identifiable {
    let id: String
    let weekStart: Date
    let totalCarbs: Double
    let avgDailyCarbs: Double
    let mealCount: Int

    var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(formatter.string(from: weekStart))-\(formatter.string(from: end))"
    }
}

struct FoodFinder_DayOfWeekPattern: Identifiable {
    let dayOfWeek: Int // 1=Sun, 2=Mon, ..., 7=Sat
    let averageCarbs: Double

    var id: Int { dayOfWeek }

    var dayName: String {
        let formatter = DateFormatter()
        return formatter.shortWeekdaySymbols[dayOfWeek - 1]
    }
}

// MARK: - Service

final class FoodFinder_CarbTrackingService {
    static let shared = FoodFinder_CarbTrackingService()

    private let healthStore = HKHealthStore()
    private let log = OSLog(category: "FoodFinder_CarbTracking")
    private let calendar = Calendar.current

    // Cache
    private(set) var snapshot: FoodFinder_CarbSnapshot?
    private var cachedDailySummaries: [FoodFinder_CarbPeriod: [FoodFinder_DailyCarbSummary]] = [:]
    private var cacheTimestamp: Date?
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    private init() {}

    // MARK: - Public API

    /// Fetches today's snapshot with same-day-last-week comparison and averages.
    @discardableResult
    func fetchSnapshot() async -> FoodFinder_CarbSnapshot? {
        if let cached = snapshot, let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < cacheDuration {
            return cached
        }

        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        // Same weekday last week
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let lastWeekEnd = calendar.date(byAdding: .day, value: -7, to: startOfTomorrow)!

        // 7-day and 30-day lookback
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday)!

        // Run queries in parallel
        async let todayEntries = fetchCarbEntries(from: startOfToday, to: now)
        async let lastWeekEntries = fetchCarbEntries(from: lastWeekStart, to: lastWeekEnd)
        async let sevenDayEntries = fetchCarbEntries(from: sevenDaysAgo, to: now)
        async let thirtyDayEntries = fetchCarbEntries(from: thirtyDaysAgo, to: now)

        let today = await todayEntries
        let lastWeek = await lastWeekEntries
        let sevenDay = await sevenDayEntries
        let thirtyDay = await thirtyDayEntries

        let todayCarbs = today.reduce(0.0) { $0 + $1.grams }
        let lastWeekCarbs = lastWeek.reduce(0.0) { $0 + $1.grams }
        let sevenDayCarbs = sevenDay.reduce(0.0) { $0 + $1.grams }
        let thirtyDayCarbs = thirtyDay.reduce(0.0) { $0 + $1.grams }

        let snap = FoodFinder_CarbSnapshot(
            todayCarbs: round(todayCarbs),
            todayMealCount: today.count,
            sameWeekdayLastWeekCarbs: lastWeek.isEmpty ? nil : round(lastWeekCarbs),
            sameWeekdayLastWeekMealCount: lastWeek.isEmpty ? nil : lastWeek.count,
            weeklyAverage: sevenDay.isEmpty ? nil : round(sevenDayCarbs / 7.0),
            monthlyAverage: thirtyDay.isEmpty ? nil : round(thirtyDayCarbs / 30.0),
            fetchDate: now
        )

        self.snapshot = snap
        self.cacheTimestamp = now
        return snap
    }

    /// Fetches per-day summaries for a given period, filling zero-carb days.
    func fetchDailySummaries(period: FoodFinder_CarbPeriod) async -> [FoodFinder_DailyCarbSummary] {
        if let cached = cachedDailySummaries[period], let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < cacheDuration {
            return cached
        }

        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -period.rawValue, to: startOfToday)!

        let entries = await fetchCarbEntries(from: startDate, to: now)

        // Group entries by date
        var grouped: [String: [FoodFinder_CarbEntry]] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for entry in entries {
            let key = formatter.string(from: entry.date)
            grouped[key, default: []].append(entry)
        }

        // Build summaries for every day in the period
        var summaries: [FoodFinder_DailyCarbSummary] = []
        for dayOffset in 0..<period.rawValue {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate)!
            let key = formatter.string(from: date)
            let dayEntries = grouped[key] ?? []
            let total = dayEntries.reduce(0.0) { $0 + $1.grams }
            summaries.append(FoodFinder_DailyCarbSummary(
                date: date, totalCarbs: round(total), mealCount: dayEntries.count, entries: dayEntries
            ))
        }

        cachedDailySummaries[period] = summaries
        return summaries
    }

    /// Groups daily summaries into weekly averages.
    func weeklyAverages(from dailySummaries: [FoodFinder_DailyCarbSummary]) -> [FoodFinder_WeeklyCarbSummary] {
        guard !dailySummaries.isEmpty else { return [] }

        var weeks: [FoodFinder_WeeklyCarbSummary] = []
        var i = 0
        while i < dailySummaries.count {
            let weekStart = dailySummaries[i].date
            let end = min(i + 7, dailySummaries.count)
            let slice = Array(dailySummaries[i..<end])
            let totalCarbs = slice.reduce(0.0) { $0 + $1.totalCarbs }
            let totalMeals = slice.reduce(0) { $0 + $1.mealCount }
            let daysInWeek = Double(slice.count)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            weeks.append(FoodFinder_WeeklyCarbSummary(
                id: formatter.string(from: weekStart),
                weekStart: weekStart,
                totalCarbs: round(totalCarbs),
                avgDailyCarbs: round(totalCarbs / daysInWeek),
                mealCount: totalMeals
            ))
            i = end
        }
        return weeks
    }

    /// Computes average carbs by day of week (Mon-Sun).
    func dayOfWeekPatterns(from dailySummaries: [FoodFinder_DailyCarbSummary]) -> [FoodFinder_DayOfWeekPattern] {
        guard !dailySummaries.isEmpty else { return [] }

        var totals: [Int: (sum: Double, count: Int)] = [:]
        for summary in dailySummaries {
            let weekday = calendar.component(.weekday, from: summary.date)
            let existing = totals[weekday] ?? (sum: 0, count: 0)
            totals[weekday] = (sum: existing.sum + summary.totalCarbs, count: existing.count + 1)
        }

        return totals.map { weekday, data in
            FoodFinder_DayOfWeekPattern(
                dayOfWeek: weekday,
                averageCarbs: data.count > 0 ? round(data.sum / Double(data.count)) : 0
            )
        }.sorted { $0.dayOfWeek < $1.dayOfWeek }
    }

    /// Builds compact text for AI prompts.
    func buildCarbTrackingContext() async -> String {
        guard let snap = await fetchSnapshot() else { return "" }

        var lines: [String] = ["CARB TRACKING:"]
        lines.append("  Today: \(Int(snap.todayCarbs))g (\(snap.todayMealCount) meals)")

        if let lastWeekCarbs = snap.sameWeekdayLastWeekCarbs {
            let dayName = {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return formatter.string(from: snap.fetchDate)
            }()
            lines.append("  Same \(dayName) Last Week: \(Int(lastWeekCarbs))g")
            if let delta = snap.deltaFromLastWeek {
                let sign = delta >= 0 ? "+" : ""
                lines.append("  Difference: \(sign)\(Int(delta))g")
            }
        }

        if let weekAvg = snap.weeklyAverage {
            lines.append("  7-Day Average: \(Int(weekAvg))g/day")
        }
        if let monthAvg = snap.monthlyAverage {
            lines.append("  30-Day Average: \(Int(monthAvg))g/day")
        }

        return lines.joined(separator: "\n")
    }

    /// Invalidates all cached data. Call after a carb entry is saved.
    func invalidateCache() {
        snapshot = nil
        cachedDailySummaries.removeAll()
        cacheTimestamp = nil
    }

    // MARK: - Private HealthKit Queries

    private func fetchCarbEntries(from startDate: Date, to endDate: Date) async -> [FoodFinder_CarbEntry] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        guard let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(
                sampleType: carbType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    os_log("Error fetching carb entries: %{public}@", log: OSLog(category: "FoodFinder_CarbTracking"), type: .error, error.localizedDescription)
                    continuation.resume(returning: [])
                    return
                }

                guard let quantitySamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let entries = quantitySamples.map { sample in
                    FoodFinder_CarbEntry(
                        id: sample.uuid.uuidString,
                        date: sample.startDate,
                        grams: sample.quantity.doubleValue(for: .gram()),
                        foodType: sample.metadata?[HKMetadataKeyFoodType] as? String
                    )
                }

                continuation.resume(returning: entries)
            }

            healthStore.execute(query)
        }
    }
}
