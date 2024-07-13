//
//  FavoriteFoodsViewModel.swift
//  Loop
//
//  Created by Noah Brauner on 7/27/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
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
    
    func onFoodSave(_ newFood: NewFavoriteFood) {
        if isAddViewActive {
            let newStoredFood = StoredFavoriteFood(name: newFood.name, carbsQuantity: newFood.carbsQuantity, foodType: newFood.foodType, absorptionTime: newFood.absorptionTime)
            withAnimation {
                favoriteFoods.append(newStoredFood)
            }
            isAddViewActive = false
        }
        else if var selectedFood, let selectedFooxIndex = favoriteFoods.firstIndex(of: selectedFood) {
            selectedFood.name = newFood.name
            selectedFood.carbsQuantity = newFood.carbsQuantity
            selectedFood.foodType = newFood.foodType
            selectedFood.absorptionTime = newFood.absorptionTime
            favoriteFoods[selectedFooxIndex] = selectedFood
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
    }

    func onFoodReorder(from: IndexSet, to: Int) {
        withAnimation {
            favoriteFoods.move(fromOffsets: from, toOffset: to)
        }
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
