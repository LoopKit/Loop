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
    
    @Published var alert: CarbEntryViewModel.Alert?
    
    @Published var bolusViewModel: BolusEntryViewModel?
    
    let shouldBeginEditingQuantity: Bool
    
    @Published var carbsQuantity: Double? = nil
    var preferredCarbUnit = HKUnit.gram()
    var maxCarbEntryQuantity = LoopConstants.maxCarbEntryQuantity
    var warningCarbEntryQuantity = LoopConstants.warningCarbEntryQuantity
    
    @Published var time = Date()
    private var date = Date()
    var minimumDate: Date {
        get { date.addingTimeInterval(.hours(-12)) }
    }
    var maximumDate: Date {
        get { date.addingTimeInterval(.hours(1)) }
    }
    
    @Published var foodType = ""
    @Published var selectedDefaultAbsorptionTimeEmoji: String = ""
    @Published var usesCustomFoodType = false
    @Published var absorptionTimeWasEdited = false // if true, selecting an emoji will not alter the absorption time

    @Published var absorptionTime: TimeInterval
    let defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes
    let minAbsorptionTime = LoopConstants.minCarbAbsorptionTime
    let maxAbsorptionTime = LoopConstants.maxCarbAbsorptionTime
    var absorptionRimesRange: ClosedRange<TimeInterval> {
        return minAbsorptionTime...maxAbsorptionTime
    }
    
    weak var delegate: CarbEntryViewModelDelegate?
    
    private lazy var cancellables = Set<AnyCancellable>()
    
    /// Initalizer for when`CarbEntryView` is presented from the home screen
    init(delegate: CarbEntryViewModelDelegate) {
        self.delegate = delegate
        self.absorptionTime = delegate.defaultAbsorptionTimes.medium
        self.defaultAbsorptionTimes = delegate.defaultAbsorptionTimes
        self.shouldBeginEditingQuantity = true
        
        observeAbsorptionTimeChange()
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
    }
    
    var originalCarbEntry: StoredCarbEntry? = nil
    
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
            if let carbsQuantity, 0...maxCarbEntryQuantity.doubleValue(for: preferredCarbUnit) ~= carbsQuantity, foodType != "" {
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
        else if quantity.compare(warningCarbEntryQuantity) == .orderedDescending {
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
    
    // MARK: - Utility
    private func observeAbsorptionTimeChange() {
        $absorptionTime
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in
                self?.absorptionTimeWasEdited = true
            }
            .store(in: &cancellables)
    }
}
