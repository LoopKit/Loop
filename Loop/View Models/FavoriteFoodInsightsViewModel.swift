//
//  FavoriteFoodInsightsViewModel.swift
//  Loop
//
//  Created by Noah Brauner on 7/15/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import LoopAlgorithm
import os.log
import Combine
import HealthKit

protocol FavoriteFoodInsightsViewModelDelegate: AnyObject {
    func selectedFavoriteFoodLastEaten(_ favoriteFood: StoredFavoriteFood) async throws -> Date?
    func getFavoriteFoodCarbEntries(_ favoriteFood: StoredFavoriteFood) async throws -> [StoredCarbEntry]
    func getHistoricalChartsData(start: Date, end: Date) async throws -> HistoricalChartsData
}

struct HistoricalChartsData {
    let glucoseValues: [GlucoseValue]
    let carbEntries: [StoredCarbEntry]
    let doses: [BasalRelativeDose]
    let iobValues: [InsulinValue]
    let carbAbsorptionReview: CarbAbsorptionReview?
}

class FavoriteFoodInsightsViewModel: ObservableObject {
    let food: StoredFavoriteFood
    var carbEntries: [StoredCarbEntry] = []
    @Published var carbEntryIndex = 0
    var carbEntry: StoredCarbEntry? {
        let entryExistsForIndex = 0..<carbEntries.count ~= carbEntryIndex
        return entryExistsForIndex ? carbEntries[carbEntryIndex] : nil
    }
    
    static var minTimeIntervalPrecedingFoodEaten: TimeInterval = .hours(1)
    static var minTimeIntervalFollowingFoodEaten: TimeInterval = .hours(6)
    var historyLength: TimeInterval { FavoriteFoodInsightsViewModel.minTimeIntervalPrecedingFoodEaten + FavoriteFoodInsightsViewModel.minTimeIntervalFollowingFoodEaten }

    // Updates each time carbEntry updates
    @Published var historicalGlucoseValues: [GlucoseValue] = []
    @Published var historicalCarbEntries: [StoredCarbEntry] = []
    @Published var historicalDoses: [BasalRelativeDose] = []
    @Published var historicalIOBValues: [InsulinValue] = []
    @Published var historicalCarbAbsorptionReview: CarbAbsorptionReview? = nil
    
    @Published var startDate = Date()
    var endDate: Date {
        startDate.addingTimeInterval(historyLength)
    }
    var dateInterval: DateInterval {
        DateInterval(start: startDate, end: endDate)
    }
    var now = Date()
    
    var preferredCarbUnit = HKUnit.gram()
    lazy var carbFormatter = QuantityFormatter(for: preferredCarbUnit)
    lazy var absorptionTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    lazy var dateFormater: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter
    }()
    lazy var relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    lazy var dateIntervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.timeStyle = .short
        formatter.dateTemplate = "MMMMd h:mm a"
        return formatter
    }()
    
    private let log = OSLog(category: "FavoriteFoodInsightsViewModel")
    
    let chartManager: ChartsManager = {
        let glucoseChart = GlucoseCarbChart(yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil)
        glucoseChart.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayRangeWide
        let iobChart = IOBChart()
        let doseChart = DoseChart()
        let carbEffectChart = CarbEffectChart()
        carbEffectChart.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayBound
        return ChartsManager(colors: .primary, settings: .default, charts: [glucoseChart, iobChart, doseChart, carbEffectChart], traitCollection: .current)
    }()
    
    private weak var delegate: FavoriteFoodInsightsViewModelDelegate?
    
    private lazy var cancellables = Set<AnyCancellable>()

    init(delegate: FavoriteFoodInsightsViewModelDelegate?, food: StoredFavoriteFood) {
        self.delegate = delegate
        self.food = food
        fetchCarbEntries(food)
        observeCarbEntryIndexChange()
    }
    
    private func fetchCarbEntries(_ food: StoredFavoriteFood) {
        Task { @MainActor in
            do {
                if let entries = try await delegate?.getFavoriteFoodCarbEntries(food), !entries.isEmpty {
                    self.carbEntries = entries
                    updateStartDateAndRefreshCharts(from: entries.first!)
                }
            }
            catch {
                log.error("Failed to fetch carb entries for favorite food: %{public}@", String(describing: error))
            }
        }
    }
    
    private func updateStartDateAndRefreshCharts(from entry: StoredCarbEntry) {
        var components = DateComponents()
        components.minute = 0
        let minimumStartDate = entry.startDate.addingTimeInterval(-FavoriteFoodInsightsViewModel.minTimeIntervalPrecedingFoodEaten)
        let hourRoundedStartDate = Calendar.current.nextDate(after: minimumStartDate, matching: components, matchingPolicy: .strict, direction: .backward) ?? minimumStartDate
        
        startDate = hourRoundedStartDate
        refreshCharts()
    }
    
    private func refreshCharts() {
        Task { @MainActor in
            do {
                if let historicalChartsData = try await delegate?.getHistoricalChartsData(start: dateInterval.start, end: dateInterval.end) {
                    var carbEntriesWithCorrectedFavoriteFoods = historicalChartsData.carbEntries.map({ historicalCarbEntry in
                        // only show a favorite food icon in the glcuose-carb chart if carb entry is currently viewed favorite food
                        StoredCarbEntry(
                            startDate: historicalCarbEntry.startDate,
                            quantity: historicalCarbEntry.quantity,
                            favoriteFoodID: historicalCarbEntry.uuid == carbEntry?.uuid ? historicalCarbEntry.favoriteFoodID : nil
                        )
                    })
                    self.historicalGlucoseValues = historicalChartsData.glucoseValues
                    self.historicalCarbEntries = carbEntriesWithCorrectedFavoriteFoods
                    self.historicalDoses = historicalChartsData.doses
                    self.historicalIOBValues = historicalChartsData.iobValues
                    self.historicalCarbAbsorptionReview = historicalChartsData.carbAbsorptionReview
                }
            } catch {
                log.error("Failed to fetch historical data in date interval: %{public}@, %{public}@", String(describing: dateInterval), String(describing: error))
            }
        }
    }
    
    private func observeCarbEntryIndexChange() {
        $carbEntryIndex
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] index in
                guard let strongSelf = self else { return }
                strongSelf.updateStartDateAndRefreshCharts(from: strongSelf.carbEntries[strongSelf.carbEntryIndex])
            }
            .store(in: &cancellables)
    }
}
