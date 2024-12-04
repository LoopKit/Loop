//
//  FavoriteFoodDetailView.swift
//  Loop
//
//  Created by Noah Brauner on 8/2/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

public struct FavoriteFoodDetailView: View {
    @ObservedObject var viewModel: FavoriteFoodsViewModel
    
    @State private var isConfirmingDelete = false
    @State private var showFavoriteFoodInsights = false

    public var body: some View {
        if let food = viewModel.selectedFood {
            Group {
                List {
                    informationSection(for: food)
                    actionsSection(for: food)
                    FavoriteFoodInsightsCardView(
                        showFavoriteFoodInsights: $showFavoriteFoodInsights,
                        foodName: viewModel.selectedFood?.name,
                        lastEatenDate: viewModel.selectedFoodLastEaten,
                        relativeDateFormatter: viewModel.relativeDateFormatter,
                        presentInSection: true
                    )
                }
                .alert(isPresented: $isConfirmingDelete) {
                    Alert(
                        title: Text("Delete “\(food.name)”?"),
                        message: Text("Are you sure you want to delete this food?"),
                        primaryButton: .cancel(),
                        secondaryButton: .destructive(Text("Delete"), action: viewModel.deleteSelectedFood)
                    )
                }
                .insetGroupedListStyle()
                .navigationTitle(food.title)
                                
                NavigationLink(destination: FavoriteFoodAddEditView(originalFavoriteFood: viewModel.selectedFood, onSave: viewModel.onFoodSave(_:)), isActive: $viewModel.isEditViewActive) {
                    EmptyView()
                }
                
                NavigationLink(destination: FavoriteFoodInsightsView(viewModel: FavoriteFoodInsightsViewModel(delegate: viewModel.insightsDelegate, food: food), presentedAsSheet: false), isActive: $showFavoriteFoodInsights) {
                    EmptyView()
                }
            }
        }
    }
    
    private func informationSection(for food: StoredFavoriteFood) -> some View {
        Section("Information") {
            VStack(spacing: 16) {
                let rows: [(field: String, value: String)] = [
                    ("Name", food.name),
                    ("Carb Quantity", food.carbsString(formatter: viewModel.carbFormatter)),
                    ("Food Type", food.foodType),
                    ("Absorption Time", food.absorptionTimeString(formatter: viewModel.absorptionTimeFormatter))
                ]
                ForEach(rows, id: \.field) { row in
                    HStack {
                        Text(row.field)
                            .font(.subheadline)
                        Spacer()
                        Text(row.value)
                            .font(.subheadline)
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
    
    private func actionsSection(for food: StoredFavoriteFood) -> some View {
        Section {
            Button(action: { viewModel.isEditViewActive.toggle() }) {
                HStack {
                    // Fix the list row inset with centered content from shifting to the center.
                    // https://stackoverflow.com/questions/75046730/swiftui-list-divider-unwanted-inset-at-the-start-when-non-text-component-is-u
                    Text("")
                        .frame(maxWidth: 0)
                        .accessibilityHidden(true)
                    
                    Spacer()
                    
                    Text("Edit Food")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(.accentColor)
                    
                    Spacer()
                }
            }
            
            Button(role: .destructive, action: { isConfirmingDelete.toggle() }) {
                Text("Delete Food")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
