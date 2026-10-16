//
//  CarbEntryViewModel.swift
//  Loop
//
//  Created by Noah Brauner on 7/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import Combine
import LoopCore
import LoopAlgorithm
import os.log

@MainActor
protocol CarbEntryViewModelDelegate: AnyObject, BolusEntryViewModelDelegate, FavoriteFoodInsightsViewModelDelegate {
    var defaultAbsorptionTimes: DefaultAbsorptionTimes { get }
    func isScheduleOverrideActive(at date: Date) -> Bool
    func getGlucoseSamples(start: Date?, end: Date?) async throws -> [StoredGlucoseSample]
}

@MainActor
final class CarbEntryViewModel: ObservableObject {
    enum Alert: Identifiable {
        var id: Self {
            return self
        }
        
        case maxQuantityExceded
        case warningQuantityValidation
    }
    
    enum Warning: Identifiable {
        var id: Self {
            return self
        }
        
        var priority: Int {
            switch self {
            case .entryIsMissedMeal:
                return 1
            case .glucoseRisingRapidly:
                return 3
            }
        }
        
        case entryIsMissedMeal
        case glucoseRisingRapidly
    }
    
    @Published var alert: CarbEntryViewModel.Alert?
    @Published var warnings: Set<Warning> = []

    @Published var bolusViewModel: BolusEntryViewModel?
    
    let shouldBeginEditingQuantity: Bool
    
    @Published var carbsQuantity: Double? = nil
    var preferredCarbUnit = LoopUnit.gram
    var maxCarbEntryQuantity = LoopConstants.maxCarbEntryQuantity
    var warningCarbEntryQuantity = LoopConstants.warningCarbEntryQuantity
    
    @Published var time = Date()
    private var date = Date()
    var minimumDate: Date {
        get { date.addingTimeInterval(LoopConstants.maxCarbEntryPastTime) }
    }
    var maximumDate: Date {
        get { date.addingTimeInterval(LoopConstants.maxCarbEntryFutureTime) }
    }
    
    @Published var foodType = ""
    @Published var selectedDefaultAbsorptionTimeEmoji: String = ""
    @Published var usesCustomFoodType = false
    @Published var absorptionTimeWasEdited = false // if true, selecting an emoji will not alter the absorption time
    private var absorptionEditIsProgrammatic = false // needed for when absorption time is changed due to favorite food selection, so that absorptionTimeWasEdited does not get set to true

    @Published var absorptionTime: TimeInterval
    let defaultAbsorptionTimes: DefaultAbsorptionTimes
    let minAbsorptionTime = LoopConstants.minCarbAbsorptionTime
    let maxAbsorptionTime = LoopConstants.maxCarbAbsorptionTime
    var absorptionRimesRange: ClosedRange<TimeInterval> {
        return minAbsorptionTime...maxAbsorptionTime
    }
    
    @Published var favoriteFoods = UserDefaults.standard.favoriteFoods
    @Published var selectedFavoriteFoodIndex = -1 {
        willSet {
            self.selectedFavoriteFoodLastEaten = nil
        }
    }
    var selectedFavoriteFood: StoredFavoriteFood? {
        let foodExistsForIndex = 0..<favoriteFoods.count ~= selectedFavoriteFoodIndex
        return foodExistsForIndex ? favoriteFoods[selectedFavoriteFoodIndex] : nil
    }
    // Favorite Food Insights
    @Published var selectedFavoriteFoodLastEaten: Date? = nil
    lazy var relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    
    private let log = OSLog(category: "CarbEntryViewModel")
    
    weak var delegate: CarbEntryViewModelDelegate?
    weak var analyticsServicesManager: AnalyticsServicesManager?
    weak var deliveryDelegate: DeliveryDelegate?

    private lazy var cancellables = Set<AnyCancellable>()
    
    /// Initalizer for when`CarbEntryView` is presented from the home screen
    init(delegate: CarbEntryViewModelDelegate) {
        self.delegate = delegate
        self.absorptionTime = delegate.defaultAbsorptionTimes.medium
        self.defaultAbsorptionTimes = delegate.defaultAbsorptionTimes
        self.shouldBeginEditingQuantity = true
        
        observeAbsorptionTimeChange()
        observeFavoriteFoodChange()
        observeFavoriteFoodIndexChange()
        observeLoopUpdates()
    }
    
    /// Initalizer for when`CarbEntryView` has an entry to edit
    init(delegate: CarbEntryViewModelDelegate, originalCarbEntry: StoredCarbEntry) {
        self.delegate = delegate
        self.originalCarbEntry = originalCarbEntry
        self.defaultAbsorptionTimes = delegate.defaultAbsorptionTimes

        self.carbsQuantity = originalCarbEntry.quantity.doubleValue(for: preferredCarbUnit)
        self.time = originalCarbEntry.startDate
        self.foodType = originalCarbEntry.foodType ?? ""
        self.absorptionTime = originalCarbEntry.absorptionTime ?? .hours(3)
        self.absorptionTimeWasEdited = true
        self.usesCustomFoodType = true
        self.shouldBeginEditingQuantity = false
        
        if let favoriteFoodIndex = favoriteFoods.firstIndex(where: { $0.id == originalCarbEntry.favoriteFoodID }) {
            self.selectedFavoriteFoodIndex = favoriteFoodIndex
            updateFavoriteFoodLastEatenDate(for: favoriteFoods[favoriteFoodIndex])
        }
        
        observeFavoriteFoodIndexChange()
        observeLoopUpdates()
    }
    
    var originalCarbEntry: StoredCarbEntry? = nil
    private let newEntrySyncIdentifier = UUID().uuidString

    private var carbEntryChange: CarbEntryChange? {
        if let quantity = carbsQuantity, quantity != 0 {
            let favoriteFoodID = selectedFavoriteFoodIndex == -1 ? nil : favoriteFoods[selectedFavoriteFoodIndex].id

            if let o = originalCarbEntry, o.quantity.doubleValue(for: preferredCarbUnit) == quantity && o.startDate == time && o.foodType == foodType && o.absorptionTime == absorptionTime, o.favoriteFoodID == favoriteFoodID {
                return nil  // No changes were made
            }

            let carbsQuantity = LoopQuantity(unit: preferredCarbUnit, doubleValue: quantity)
            let entryFoodType = usesCustomFoodType ? foodType : selectedDefaultAbsorptionTimeEmoji

            guard let originalCarbEntry else {
                return .add(NewCarbEntry(
                    date: date,
                    syncIdentifier: newEntrySyncIdentifier,
                    quantity: carbsQuantity,
                    startDate: time,
                    foodType: entryFoodType,
                    absorptionTime: absorptionTime,
                    favoriteFoodID: favoriteFoodID
                ))
            }

            return .edit(originalCarbEntry, CarbEntryUpdate(
                date: date,
                quantity: carbsQuantity,
                startDate: time,
                foodType: entryFoodType,
                absorptionTime: absorptionTime,
                favoriteFoodID: favoriteFoodID
            ))
        }
        else {
            return nil
        }
    }
    
    var saveFavoriteFoodButtonDisabled: Bool {
        get {
            if let carbsQuantity, 0...maxCarbEntryQuantity.doubleValue(for: preferredCarbUnit) ~= carbsQuantity, selectedFavoriteFoodIndex == -1 {
                return false
            }
            return true
        }
    }
    
    var continueButtonDisabled: Bool {
        get { carbEntryChange == nil }
    }
    
    // MARK: - Continue to Bolus and Carb Quantity Warnings
    func continueToBolus() {
        guard carbEntryChange != nil else {
            return
        }
        
        validateInputAndContinue()
    }
    
    private func validateInputAndContinue() {
        guard absorptionTime <= maxAbsorptionTime else {
            return
        }
        
        guard let carbsQuantity, carbsQuantity > 0 else { return }
        let quantity = LoopQuantity(unit: preferredCarbUnit, doubleValue: carbsQuantity)
        if quantity.compare(maxCarbEntryQuantity) == .orderedDescending {
            self.alert = .maxQuantityExceded
            return
        }
        else if quantity.compare(warningCarbEntryQuantity) == .orderedDescending, selectedFavoriteFoodIndex == -1 {
            self.alert = .warningQuantityValidation
            return
        }
        
        Task { @MainActor in
            setBolusViewModel()
        }
    }
        
    @MainActor private func setBolusViewModel() {
        let viewModel = BolusEntryViewModel(
            delegate: delegate,
            screenWidth: UIScreen.main.bounds.width,
            carbEntryChange: carbEntryChange,
            selectedCarbAbsorptionTimeEmoji: selectedDefaultAbsorptionTimeEmoji
        )
        
        viewModel.analyticsServicesManager = analyticsServicesManager
        viewModel.deliveryDelegate = deliveryDelegate
        bolusViewModel = viewModel
        
        analyticsServicesManager?.didDisplayBolusScreen()
    }
    
    func clearAlert() {
        self.alert = nil
    }
    
    func clearAlertAndContinueToBolus() {
        self.alert = nil
        Task { @MainActor in
            setBolusViewModel()
        }
    }
    
    // MARK: - Favorite Foods
    func onFavoriteFoodSave(_ food: NewFavoriteFood) {
        let newStoredFood = StoredFavoriteFood(name: food.name, carbsQuantity: food.carbsQuantity, foodType: food.foodType, absorptionTime: food.absorptionTime)
        favoriteFoods.append(newStoredFood)
        selectedFavoriteFoodIndex = favoriteFoods.count - 1
    }
    
    private func observeFavoriteFoodIndexChange() {
        $selectedFavoriteFoodIndex
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] index in
                self?.favoriteFoodSelected(at: index)
            }
            .store(in: &cancellables)
    }
    
    private func observeFavoriteFoodChange() {
        $favoriteFoods
            .dropFirst()
            .removeDuplicates()
            .sink { newValue in
                UserDefaults.standard.favoriteFoods = newValue
            }
            .store(in: &cancellables)
    }

    private func favoriteFoodSelected(at index: Int) {
        self.absorptionEditIsProgrammatic = true
        // only updates carb entry fields if on new carb entry screen
        if index == -1 {
            if originalCarbEntry == nil {
                self.carbsQuantity = 0
                self.absorptionTime = defaultAbsorptionTimes.medium
                self.absorptionTimeWasEdited = false
                self.usesCustomFoodType = false
            }
            self.foodType = ""
        }
        else {
            let food = favoriteFoods[index]
            self.carbsQuantity = food.carbsQuantity.doubleValue(for: preferredCarbUnit)
            self.foodType = food.foodType
            self.absorptionTime = food.absorptionTime
            self.absorptionTimeWasEdited = true
            self.usesCustomFoodType = true
            updateFavoriteFoodLastEatenDate(for: food)
        }
    }
    
    private func updateFavoriteFoodLastEatenDate(for food: StoredFavoriteFood) {
        // Update favorite food insights last eaten date
        Task { @MainActor in
            do {
                if let lastEaten = try await delegate?.selectedFavoriteFoodLastEaten(food) {
                    withAnimation(.default) {
                        self.selectedFavoriteFoodLastEaten = lastEaten
                    }
                }
            }
            catch {
                log.error("Failed to fetch last eaten date for favorite food: %{public}@, %{public}@", String(describing: selectedFavoriteFood), String(describing: error))
            }
        }
    }
    
    // MARK: - Utility
    func restoreUserActivityState(_ activity: NSUserActivity) {
        if let entry = activity.newCarbEntry {
            time = entry.date
            carbsQuantity = entry.quantity.doubleValue(for: preferredCarbUnit)

            if let foodType = entry.foodType {
                self.foodType = foodType
                usesCustomFoodType = true
            }

            if let absorptionTime = entry.absorptionTime {
                self.absorptionTime = absorptionTime
                absorptionTimeWasEdited = true
            }
            
            if activity.entryisMissedMeal {
                warnings.insert(.entryIsMissedMeal)
            }
        }
    }
    
    private func observeLoopUpdates() {
        checkIfOverrideEnabled()
        checkGlucoseRisingRapidly()
        NotificationCenter.default
            .publisher(for: .LoopDataUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkIfOverrideEnabled()
                self?.checkGlucoseRisingRapidly()
            }
            .store(in: &cancellables)
    }
    
    @Published var currentOverride: TemporaryScheduleOverride?
    
    private func checkIfOverrideEnabled() {
        guard let delegate else {
            return
        }

        if delegate.isScheduleOverrideActive(at: Date()),
           let override = delegate.scheduleOverride ?? delegate.preMealOverride
        {
            currentOverride = override
        } else {
            currentOverride = nil
        }
    }
    
    private func checkGlucoseRisingRapidly() {
        guard let delegate else {
            warnings.remove(.glucoseRisingRapidly)
            return
        }
        
        let now = Date()
        let startDate = now.addingTimeInterval(-LoopConstants.missedMealWarningGlucoseRecencyWindow)
        
        Task { @MainActor in
            let glucoseSamples = try? await delegate.getGlucoseSamples(start: startDate, end: nil)
            guard let glucoseSamples else {
                warnings.remove(.glucoseRisingRapidly)
                return
            }
            
            let filteredGlucoseSamples = glucoseSamples.filterDateRange(startDate, now)
            guard filteredGlucoseSamples.count >= 2 else {
                warnings.remove(.glucoseRisingRapidly)
                return
            }
            
            // Condition 1: Rate of change between the most recent two glucose readings within 14 minutes
            let twoReadingWindow = now.addingTimeInterval(.minutes(-14))
            let twoReadingSamples = filteredGlucoseSamples.filterDateRange(twoReadingWindow, now)
            
            if twoReadingSamples.count >= 2 {
                let recentTwo = Array(twoReadingSamples.suffix(2))
                let firstOfTwo = recentTwo[0]
                let lastOfTwo = recentTwo[1]
                
                let duration = lastOfTwo.startDate.timeIntervalSince(firstOfTwo.startDate)
                let delta = lastOfTwo.quantity.doubleValue(for: .milligramsPerDeciliter) - firstOfTwo.quantity.doubleValue(for: .milligramsPerDeciliter)
                let velocity = delta / duration.minutes // Unit = mg/dL/min

                if velocity >= LoopConstants.missedMealWarningGlucoseRiseThreshold {
                    warnings.insert(.glucoseRisingRapidly)
                    return
                }
            }
            
            // Condition 2: Rate of change over the most recent three glucose readings within 19 minutes
            let threeReadingWindow = now.addingTimeInterval(-LoopConstants.missedMealWarningGlucoseRecencyWindow)
            let threeReadingSamples = filteredGlucoseSamples.filterDateRange(threeReadingWindow, now)
            
            if threeReadingSamples.count >= 3 {
                let recentThree = Array(threeReadingSamples.suffix(3))
                let firstOfThree = recentThree[0]
                let lastOfThree = recentThree[2]
                
                let duration = lastOfThree.startDate.timeIntervalSince(firstOfThree.startDate)
                let delta = lastOfThree.quantity.doubleValue(for: .milligramsPerDeciliter) - firstOfThree.quantity.doubleValue(for: .milligramsPerDeciliter)
                let velocity = delta / duration.minutes // Unit = mg/dL/min

                if velocity >= LoopConstants.missedMealWarningGlucoseRiseThreshold {
                    warnings.insert(.glucoseRisingRapidly)
                    return
                }
            }
            
            // Neither condition met
            warnings.remove(.glucoseRisingRapidly)
        }
    }

    private func observeAbsorptionTimeChange() {
        $absorptionTime
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in
                if self?.absorptionEditIsProgrammatic == true {
                    self?.absorptionEditIsProgrammatic = false
                }
                else {
                    self?.absorptionTimeWasEdited = true
                }
            }
            .store(in: &cancellables)
    }
}
