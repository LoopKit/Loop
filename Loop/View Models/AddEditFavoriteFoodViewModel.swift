//
//  AddEditFavoriteFoodViewModel.swift
//  Loop
//
//  Created by Noah Brauner on 7/31/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit

final class AddEditFavoriteFoodViewModel: ObservableObject {
    static let maxNameLength = 30
    enum Alert: Identifiable {
        var id: Self {
            return self
        }
        
        case maxQuantityExceded
        case warningQuantityValidation
    }
    
    @Published var name = ""
    
    @Published var carbsQuantity: Double? = nil
    var preferredCarbUnit = HKUnit.gram()
    var maxCarbEntryQuantity = LoopConstants.maxCarbEntryQuantity
    var warningCarbEntryQuantity = LoopConstants.warningCarbEntryQuantity
    
    @Published var foodType = ""

    @Published var absorptionTime: TimeInterval
    let minAbsorptionTime = LoopConstants.minCarbAbsorptionTime
    let maxAbsorptionTime = LoopConstants.maxCarbAbsorptionTime
    var absorptionRimesRange: ClosedRange<TimeInterval> {
        return minAbsorptionTime...maxAbsorptionTime
    }
    
    @Published var alert: AddEditFavoriteFoodViewModel.Alert?
    
    private let onSave: (NewFavoriteFood) -> ()

    private static func truncatedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed
        guard clean.count > maxNameLength else { return clean }
        let endIndex = clean.index(clean.startIndex, offsetBy: maxNameLength)
        return String(clean[..<endIndex])
    }

    private static func resolvedFoodType(initial: String, additionalCandidates: [String?]) -> String {
        let trimmedInitial = initial.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraCandidates = additionalCandidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmptyExtras = extraCandidates.filter { !$0.isEmpty }

        // Prefer any mapped emoji for known simple foods using the provided candidates.
        let lookupCandidates = ([trimmedInitial] + nonEmptyExtras).filter { !$0.isEmpty }
        if let emoji = lookupCandidates.compactMap({ EmojiThumbnailProvider.emoji(for: $0) }).first {
            return emoji
        }

        // If no emoji mapping, fall back to the first non-empty candidate (initial or provided name).
        if !trimmedInitial.isEmpty {
            return trimmedInitial
        }
        return nonEmptyExtras.first ?? trimmedInitial
    }
    
    init(originalFavoriteFood: StoredFavoriteFood?, onSave: @escaping (NewFavoriteFood) -> ()) {
        self.onSave = onSave
        if let food = originalFavoriteFood {
            self.originalFavoriteFood = food
            self.name = Self.truncatedName(food.name)
            self.carbsQuantity = food.carbsQuantity.doubleValue(for: preferredCarbUnit)
            self.foodType = Self.resolvedFoodType(initial: food.foodType,
                                                  additionalCandidates: [food.name])
            self.absorptionTime = food.absorptionTime
        }
        else {
            self.absorptionTime = .hours(3)
        }
    }
    
    init(carbsQuantity: Double?, foodType: String, absorptionTime: TimeInterval, suggestedName: String? = nil, onSave: @escaping (NewFavoriteFood) -> ()) {
        self.onSave = onSave
        self.carbsQuantity = carbsQuantity
        self.foodType = Self.resolvedFoodType(initial: foodType,
                                              additionalCandidates: [suggestedName])
        self.absorptionTime = absorptionTime
        self.name = Self.truncatedName(suggestedName ?? "")
    }
    
    var originalFavoriteFood: StoredFavoriteFood?
    var updatedFavoriteFood: NewFavoriteFood? {
        if let quantity = carbsQuantity, quantity != 0, name != "", foodType != "" {
            if let o = originalFavoriteFood, o.name == name, o.carbsQuantity.doubleValue(for: preferredCarbUnit) == carbsQuantity && o.foodType == foodType && o.absorptionTime == absorptionTime {
                return nil  // No changes were made
            }
            
            return NewFavoriteFood(
                name: name,
                carbsQuantity: HKQuantity(unit: preferredCarbUnit, doubleValue: quantity),
                foodType: foodType,
                absorptionTime: absorptionTime
            )
        }
        else {
            return nil
        }
    }
    
    func save() {
        guard let updatedFavoriteFood, absorptionTime <= maxAbsorptionTime else { return }

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
        
        onSave(updatedFavoriteFood)
    }
    
    func clearAlertAndSave() {
        guard let updatedFavoriteFood else { return }
        self.alert = nil
        onSave(updatedFavoriteFood)
    }
    
    func clearAlert() {
        self.alert = nil
    }
}
