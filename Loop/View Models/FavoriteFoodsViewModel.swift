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
import os.log

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
    
    // Favorite Food Insights
    @Published var selectedFoodLastEaten: Date? = nil
    lazy var relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private let log = OSLog(category: "CarbEntryViewModel")
    
    weak var insightsDelegate: FavoriteFoodInsightsViewModelDelegate?
    
    private lazy var cancellables = Set<AnyCancellable>()
    
    init(insightsDelegate: FavoriteFoodInsightsViewModelDelegate?) {
        self.insightsDelegate = insightsDelegate
        observeFavoriteFoodChange()
        observeDetailViewPresentation()
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
            if isDetailViewActive {
                self.selectedFood = selectedFood
            }
            isEditViewActive = false
        }
    }
    
    func deleteSelectedFood() {
        if let selectedFood {
            onFoodDelete(selectedFood)
        }
        isDetailViewActive = false
    }
    
    func onFoodDelete(_ food: StoredFavoriteFood) {
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
    
    private func observeDetailViewPresentation() {
        $isDetailViewActive
            .sink { [weak self] newValue in
                if newValue {
                    self?.fetchFoodLastEaten()
                }
                else {
                    self?.selectedFoodLastEaten = nil
                }
            }
            .store(in: &cancellables)
    }
    
    private func fetchFoodLastEaten() {
        Task { @MainActor in
            do {
                if let selectedFood, let lastEaten = try await insightsDelegate?.selectedFavoriteFoodLastEaten(selectedFood) {
                    self.selectedFoodLastEaten = lastEaten
                }
            } catch {
                log.error("Failed to fetch last eaten date for favorite food: %{public}@, %{public}@", String(describing: selectedFood), String(describing: error))
            }
        }
    }
}
