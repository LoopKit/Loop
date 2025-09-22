//
//  FavoriteFoodsViewModel.swift
//  Loop
//
//  Created by Noah Brauner on 7/27/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit
import HealthKit
import LoopKit
import Combine

final class FavoriteFoodsViewModel: ObservableObject {
    @Published var favoriteFoods = UserDefaults.standard.favoriteFoods
    @Published var selectedFood: StoredFavoriteFood?
    
    @Published var isDetailViewActive = false
    @Published var isEditViewActive = false
    @Published var isAddViewActive = false
    
    var preferredCarbUnit = HKUnit.gram()
    lazy var carbFormatter = QuantityFormatter(for: preferredCarbUnit)
    lazy var absorptionTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    private lazy var cancellables = Set<AnyCancellable>()
    
    init() {
        observeFavoriteFoodChange()
    }
    
    private func firstFiveWords(of text: String) -> String {
        let words = text.split { $0.isWhitespace }
        if words.count <= 5 { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return words.prefix(5).joined(separator: " ")
    }

    func onFoodSave(_ newFood: NewFavoriteFood) {
        let trimmedName = firstFiveWords(of: newFood.name)
        // Determine if this is a simple food that maps to an emoji, and use ONLY the emoji for Food Type
        let candidateNames = [newFood.name, newFood.foodType].compactMap { $0 }
        let matchedNameForEmoji = candidateNames.first { EmojiThumbnailProvider.emoji(for: $0) != nil }
        let resolvedEmoji: String? = matchedNameForEmoji.flatMap { EmojiThumbnailProvider.emoji(for: $0) }
        let finalFoodType = resolvedEmoji ?? newFood.foodType

        if isAddViewActive {
            let newStoredFood = StoredFavoriteFood(name: trimmedName, carbsQuantity: newFood.carbsQuantity, foodType: finalFoodType, absorptionTime: newFood.absorptionTime)
            withAnimation { favoriteFoods.append(newStoredFood) }
            UserDefaults.standard.writeFavoriteFoods(favoriteFoods)
            // Save emoji thumbnail if applicable so list shows an icon
            if let match = matchedNameForEmoji, let image = EmojiThumbnailProvider.image(for: match) {
                if let id = FavoriteFoodImageStore.saveThumbnail(from: image) {
                    var map = UserDefaults.standard.favoriteFoodImageIDs
                    map[newStoredFood.id] = id
                    UserDefaults.standard.favoriteFoodImageIDs = map
                }
            }
            isAddViewActive = false
        } else if var selectedFood, let selectedFooxIndex = favoriteFoods.firstIndex(of: selectedFood) {
            selectedFood.name = trimmedName
            selectedFood.carbsQuantity = newFood.carbsQuantity
            selectedFood.foodType = finalFoodType
            selectedFood.absorptionTime = newFood.absorptionTime
            favoriteFoods[selectedFooxIndex] = selectedFood
            UserDefaults.standard.writeFavoriteFoods(favoriteFoods)
            // Update emoji thumbnail if applicable
            if let match = matchedNameForEmoji, let image = EmojiThumbnailProvider.image(for: match) {
                if let id = FavoriteFoodImageStore.saveThumbnail(from: image) {
                    var map = UserDefaults.standard.favoriteFoodImageIDs
                    map[selectedFood.id] = id
                    UserDefaults.standard.favoriteFoodImageIDs = map
                }
            }
            isEditViewActive = false
        }
    }
    
    func onFoodDelete(_ food: StoredFavoriteFood) {
        if isDetailViewActive {
            isDetailViewActive = false
        }
        withAnimation {
            _ = favoriteFoods.remove(food)
        }
        UserDefaults.standard.writeFavoriteFoods(favoriteFoods)
        var map = UserDefaults.standard.favoriteFoodImageIDs
        if let id = map[food.id] {
            FavoriteFoodImageStore.deleteThumbnail(id: id)
            map.removeValue(forKey: food.id)
            UserDefaults.standard.favoriteFoodImageIDs = map
        }
    }

    func onFoodReorder(from: IndexSet, to: Int) {
        withAnimation {
            favoriteFoods.move(fromOffsets: from, toOffset: to)
        }
        UserDefaults.standard.writeFavoriteFoods(favoriteFoods)
    }
    
    func addFoodTapped() {
        isAddViewActive = true
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
}
