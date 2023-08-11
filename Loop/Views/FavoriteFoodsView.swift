//
//  FavoriteFoodsView.swift
//  Loop
//
//  Created by Noah Brauner on 7/12/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct FavoriteFoodsView: View {
    @Environment(\.dismissAction) private var dismiss
    
    @StateObject private var viewModel = FavoriteFoodsViewModel()

    @State private var foodToConfirmDeleteId: String? = nil
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationView {
            VStack {
                List {
                    if viewModel.favoriteFoods.isEmpty {
                        Section {
                            Text("Selecting a favorite food in the carb entry screen automatically fills in the carb quantity, food type, and absorption time fields! Tap the add button below to create your first favorite food!")
                        }
                    }
                    else {
                        Section(header: listHeader) {
                            ForEach(viewModel.favoriteFoods) { food in
                                FavoriteFoodListRow(food: food, foodToConfirmDeleteId: $foodToConfirmDeleteId, onFoodTap: onFoodTap(_:), onFoodDelete: viewModel.onFoodDelete(_:), carbFormatter: viewModel.carbFormatter, absorptionTimeFormatter: viewModel.absorptionTimeFormatter, preferredCarbUnit: viewModel.preferredCarbUnit)
                                    .environment(\.editMode, self.$editMode)
                                    .listRowInsets(EdgeInsets())
                            }
                            .onMove(perform: viewModel.onFoodReorder(from:to:))
                            .moveDisabled(!editMode.isEditing)
                            .deleteDisabled(true)
                        }
                    }
                    
                    Section {
                        addFoodButton
                            .listRowInsets(EdgeInsets())
                    }
                }
                .insetGroupedListStyle()
                
                
                NavigationLink(destination: AddEditFavoriteFoodView(originalFavoriteFood: viewModel.selectedFood, onSave: viewModel.onFoodSave(_:)), isActive: $viewModel.isEditViewActive) {
                    EmptyView()
                }
                
                NavigationLink(destination: FavoriteFoodDetailView(food: viewModel.selectedFood, onFoodDelete: viewModel.onFoodDelete(_:), carbFormatter: viewModel.carbFormatter, absorptionTimeFormatter: viewModel.absorptionTimeFormatter, preferredCarbUnit: viewModel.preferredCarbUnit), isActive: $viewModel.isDetailViewActive) {
                    EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    dismissButton
                }
            }
            .navigationBarTitle("Favorite Foods", displayMode: .large)
        }
        .sheet(isPresented: $viewModel.isAddViewActive) {
            AddEditFavoriteFoodView(onSave: viewModel.onFoodSave(_:))
        }
        .onChange(of: editMode) { newValue in
            if !newValue.isEditing {
                foodToConfirmDeleteId = nil
            }
        }
    }
    
    private func onFoodTap(_ food: StoredFavoriteFood) {
        viewModel.selectedFood = food
        if editMode.isEditing {
            viewModel.isEditViewActive = true
        }
        else {
            viewModel.isDetailViewActive = true
        }
    }
}

extension FavoriteFoodsView {
    private var listHeader: some View {
        HStack {
            Text("All Favorites")
                .font(.title3)
                .fontWeight(.semibold)
                .textCase(nil)
                .foregroundColor(.primary)
            
            Spacer()
            
            editButton
        }
        .listRowInsets(EdgeInsets(top: 20, leading: 4, bottom: 10, trailing: 4))
    }
    
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Done")
        }
    }
        
    private var editButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                editMode.toggle()
            }
        }) {
            Text(editMode.title)
                .textCase(nil)
        }
    }
    
    private var addFoodButton: some View {
        Button(action: viewModel.addFoodTapped) {
            HStack {
                Image(systemName: "plus.circle.fill")
                
                Text("Add a new favorite food")
            }
        }
        .buttonStyle(ActionButtonStyle())
    }
}
