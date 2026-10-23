//
//  StatisticsViewModel.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

@MainActor
final class StatisticsViewModel: ObservableObject {

    /// Selectable look-back windows. Bounded by the on-device glucose cache.
    enum DateRange: Int, CaseIterable, Identifiable {
        case week = 7
        case twoWeeks = 14
        case month = 30
        case quarter = 90

        var id: Int { rawValue }
        var days: Int { rawValue }
    }

    @Published var selectedRange: DateRange = .twoWeeks {
        didSet {
            guard selectedRange != oldValue else { return }
            recompute()
        }
    }

    @Published private(set) var statistics: GlucoseStatistics?
    @Published private(set) var isLoading = false
    /// Days of glucose actually available (bounded by data accumulated and the cache).
    @Published private(set) var availableDays: Double = 0

    /// Complete days of insulin delivery within the selected range, oldest first.
    @Published private(set) var insulinDays: [DailyInsulinDelivery] = []
    @Published private(set) var insulinToday: DailyInsulinDelivery?
    @Published private(set) var typicalInsulinByNow: TypicalInsulinDelivery?

    private var allSamples: [StoredGlucoseSample] = []
    private var allInsulinDays: [DailyInsulinDelivery] = []
    private let glucoseStore: GlucoseStoreProtocol
    private let insulinDeliveryHistory: ((Int) async throws -> InsulinDeliveryHistory)?
    private let calendar: Calendar
    private let now: () -> Date

    /// Configured local cache duration (how far back glucose is retained on device).
    let cacheDuration: TimeInterval
    let scheduledBasalTotal: Double?

    init(glucoseStore: GlucoseStoreProtocol,
         insulinDeliveryHistory: ((Int) async throws -> InsulinDeliveryHistory)? = nil,
         scheduledBasalTotal: Double? = nil,
         cacheDuration: TimeInterval = Bundle.main.localCacheDuration,
         calendar: Calendar = .current,
         now: @escaping () -> Date = { Date() }) {
        self.glucoseStore = glucoseStore
        self.insulinDeliveryHistory = insulinDeliveryHistory
        self.scheduledBasalTotal = scheduledBasalTotal
        self.cacheDuration = cacheDuration
        self.calendar = calendar
        self.now = now
    }

    var showsInsulin: Bool { insulinDeliveryHistory != nil }

    /// Mean of the complete days in the selected range.
    var averageInsulinDay: InsulinDeliveryTotals? {
        guard !insulinDays.isEmpty else { return nil }
        let count = Double(insulinDays.count)
        let sum = insulinDays.reduce(into: InsulinDeliveryTotals()) { sum, day in
            sum.basal += day.totals.basal
            sum.automaticBolus += day.totals.automaticBolus
            sum.manualBolus += day.totals.manualBolus
        }
        return InsulinDeliveryTotals(basal: sum.basal / count, automaticBolus: sum.automaticBolus / count, manualBolus: sum.manualBolus / count)
    }

    var cacheDurationDays: Int { Int((cacheDuration / 86400).rounded()) }

    /// Info notices for the selected range: shown when the window is incomplete,
    /// with an extra line when the local cache is what's limiting the history.
    /// Empty when there's enough data to fill the selected window.
    var dataNotices: [String] {
        guard availableDays + 1 < Double(selectedRange.days) else { return [] }
        let have = max(0, Int(availableDays.rounded()))
        var notices = [String(format: NSLocalizedString(
            "Showing %1$d days of data — not enough for the full %2$d-day period yet.",
            comment: "Notice when the selected statistics range has incomplete data"), have, selectedRange.days)]
        if cacheDurationDays < selectedRange.days {
            notices.append(String(format: NSLocalizedString(
                "This device keeps %d days of glucose. Increase the cache duration and rebuild to review the full period.",
                comment: "Notice when the local cache limits the statistics history"), cacheDurationDays))
        }
        return notices
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let end = now()
        let start = end.addingTimeInterval(-cacheDuration)
        do {
            allSamples = try await glucoseStore.getGlucoseSamples(start: start, end: end)
                .filter { !$0.isDisplayOnly && !$0.wasUserEntered }
                .sorted { $0.startDate < $1.startDate }
        } catch {
            allSamples = []
        }
        availableDays = allSamples.first.map { end.timeIntervalSince($0.startDate) / 86400 } ?? 0

        if let insulinDeliveryHistory, let history = try? await insulinDeliveryHistory(cacheDurationDays) {
            let days = history.dailyTotals(calendar: calendar)
            allInsulinDays = days.filter(\.isComplete)
            insulinToday = days.last(where: { !$0.isComplete })
            typicalInsulinByNow = history.typicalDelivery(by: history.end, calendar: calendar)
        }
        recompute()
    }

    /// Recompute statistics for the selected window from the already-loaded samples
    /// (no store round-trip), so switching ranges is instant.
    private func recompute() {
        let end = now()
        let start = calendar.date(byAdding: .day, value: -selectedRange.days, to: end)
            ?? end.addingTimeInterval(-Double(selectedRange.days) * 24 * 60 * 60)
        statistics = GlucoseStatistics(samples: allSamples, start: start, end: end, calendar: calendar)
        let firstDay = calendar.date(byAdding: .day, value: -selectedRange.days, to: calendar.startOfDay(for: end)) ?? start
        insulinDays = allInsulinDays.filter { $0.start >= firstDay }
    }
}
