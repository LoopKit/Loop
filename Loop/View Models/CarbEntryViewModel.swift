//
//  CarbEntryViewModel.swift
//  Loop
//
//  Created by Noah Brauner on 7/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit
import Combine

protocol CarbEntryViewModelDelegate: AnyObject, BolusEntryViewModelDelegate {
    var analyticsServicesManager: AnalyticsServicesManager { get }
    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes { get }
}

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
            case .overrideInProgress:
                return 2
            }
        }
        
        case entryIsMissedMeal
        case overrideInProgress
    }
    
    @Published var alert: CarbEntryViewModel.Alert?
    @Published var warnings: Set<Warning> = []

    @Published var bolusViewModel: BolusEntryViewModel?
    
    let shouldBeginEditingQuantity: Bool
    
    @Published var carbsQuantity: Double? = nil
    var preferredCarbUnit = HKUnit.gram()
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
    let defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes
    let minAbsorptionTime = LoopConstants.minCarbAbsorptionTime
    let maxAbsorptionTime = LoopConstants.maxCarbAbsorptionTime
    var absorptionRimesRange: ClosedRange<TimeInterval> {
        return minAbsorptionTime...maxAbsorptionTime
    }
    
    @Published var favoriteFoods = UserDefaults.standard.favoriteFoods
    @Published var selectedFavoriteFoodIndex = -1
    
    weak var delegate: CarbEntryViewModelDelegate?
    
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
        
        observeLoopUpdates()
    }
    
    var originalCarbEntry: StoredCarbEntry? = nil
    private var favoriteFood: FavoriteFood? = nil
    
    private var updatedCarbEntry: NewCarbEntry? {
        if let quantity = carbsQuantity, quantity != 0 {
            if let o = originalCarbEntry, o.quantity.doubleValue(for: preferredCarbUnit) == quantity && o.startDate == time && o.foodType == foodType && o.absorptionTime == absorptionTime {
                return nil  // No changes were made
            }
            
            return NewCarbEntry(
                date: date,
                quantity: HKQuantity(unit: preferredCarbUnit, doubleValue: quantity),
                startDate: time,
                foodType: usesCustomFoodType ? foodType : selectedDefaultAbsorptionTimeEmoji,
                absorptionTime: absorptionTime
            )
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
        get { updatedCarbEntry == nil }
    }
    
    // MARK: - Continue to Bolus and Carb Quantity Warnings
    func continueToBolus() {
        guard updatedCarbEntry != nil else {
            return
        }
        
        validateInputAndContinue()
    }
    
    private func validateInputAndContinue() {
        guard absorptionTime <= maxAbsorptionTime else {
            return
        }
        
        guard let carbsQuantity, carbsQuantity > 0 else { return }
        let quantity = HKQuantity(unit: preferredCarbUnit, doubleValue: carbsQuantity)
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
            originalCarbEntry: originalCarbEntry,
            potentialCarbEntry: updatedCarbEntry,
            selectedCarbAbsorptionTimeEmoji: selectedDefaultAbsorptionTimeEmoji
        )
        Task {
            await viewModel.generateRecommendationAndStartObserving()
        }
        
        viewModel.analyticsServicesManager = delegate?.analyticsServicesManager
        bolusViewModel = viewModel
        
        delegate?.analyticsServicesManager.didDisplayBolusScreen()
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
        if index == -1 {
            self.carbsQuantity = 0
            self.foodType = ""
            self.absorptionTime = defaultAbsorptionTimes.medium
            self.absorptionTimeWasEdited = false
            self.usesCustomFoodType = false
        }
        else {
            let food = favoriteFoods[index]
            self.carbsQuantity = food.carbsQuantity.doubleValue(for: preferredCarbUnit)
            self.foodType = food.foodType
            self.absorptionTime = food.absorptionTime
            self.absorptionTimeWasEdited = true
            self.usesCustomFoodType = true
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
        self.checkIfOverrideEnabled()
        NotificationCenter.default
            .publisher(for: .LoopDataUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkIfOverrideEnabled()
            }
            .store(in: &cancellables)
    }
    
    private func checkIfOverrideEnabled() {
        if let managerSettings = delegate?.settings,
           managerSettings.scheduleOverrideEnabled(at: Date()),
           let overrideSettings = managerSettings.scheduleOverride?.settings,
           overrideSettings.effectiveInsulinNeedsScaleFactor != 1.0 {
            self.warnings.insert(.overrideInProgress)
        }
        else {
            self.warnings.remove(.overrideInProgress)
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
