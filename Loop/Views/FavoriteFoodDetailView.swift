//
//  FavoriteFoodDetailView.swift
//  Loop
//
//  Created by Noah Brauner on 8/2/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit

public struct FavoriteFoodDetailView: View {
    let food: StoredFavoriteFood?
    let onFoodDelete: (StoredFavoriteFood) -> Void
    
    @State private var isConfirmingDelete = false
    
    let carbFormatter: QuantityFormatter
    let absorptionTimeFormatter: DateComponentsFormatter
    let preferredCarbUnit: HKUnit
    
    public init(food: StoredFavoriteFood?, onFoodDelete: @escaping (StoredFavoriteFood) -> Void, isConfirmingDelete: Bool = false, carbFormatter: QuantityFormatter, absorptionTimeFormatter: DateComponentsFormatter, preferredCarbUnit: HKUnit = HKUnit.gram()) {
        self.food = food
        self.onFoodDelete = onFoodDelete
        self.isConfirmingDelete = isConfirmingDelete
        self.carbFormatter = carbFormatter
        self.absorptionTimeFormatter = absorptionTimeFormatter
        self.preferredCarbUnit = preferredCarbUnit
    }
    
    public var body: some View {
        if let food {
            List {
                if let thumb = thumbnailForFood(food) {
                    Section {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))
                }
                Section("Information") {
                    VStack(spacing: 16) {
                        let rows: [(field: String, value: String)] = [
                            (String(localized: "Name", comment: "Label for name row on add favorite food screen"), food.name),
                            (String(localized: "Carb Quantity", comment: "Label for carb quantity row on add favorite food screen"), food.carbsString(formatter: carbFormatter)),
                            (String(localized:"Food Type", comment: "Label for food type entry on add favorite food screen"), food.foodType),
                            (String(localized: "Absorption Time", comment: "Label for food absorption entry on add favorite food screen"), food.absorptionTimeString(formatter: absorptionTimeFormatter))
                        ]
                        ForEach(rows, id: \.field) { row in
                            HStack {
                                Text(row.field)
                                    .font(.subheadline)
                                Spacer()
                                Text(row.value)
                        HStack {
                            Text("Name")
                                .font(.subheadline)
                            Spacer()
                            Text(food.name)
                                .font(.subheadline)
                        }

                        HStack {
                            Text("Carb Quantity")
                                .font(.subheadline)
                            Spacer()
                            Text(food.carbsString(formatter: carbFormatter))
                                .font(.subheadline)
                        }

                        HStack(alignment: .center) {
                            Text("Food Type")
                                .font(.subheadline)
                            Spacer()
                            if let thumb = thumbnailForFood(food) {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                                    )
                            } else {
                                Text(food.foodType)
                                    .font(.subheadline)
                            }
                        }

                        HStack {
                            Text("Absorption Time")
                                .font(.subheadline)
                            Spacer()
                            Text(food.absorptionTimeString(formatter: absorptionTimeFormatter))
                                .font(.subheadline)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                
                Button(role: .destructive, action: { isConfirmingDelete.toggle() }) {
                    Text("Delete Food")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .alert(isPresented: $isConfirmingDelete) {
                Alert(
                    title: Text("Delete “\(food.name)”?"),
                    message: Text("Are you sure you want to delete this food?"),
                    primaryButton: .cancel(),
                    secondaryButton: .destructive(Text("Delete"), action: { onFoodDelete(food) })
                )
            }
            .insetGroupedListStyle()
            .navigationTitle(food.title)
        }
    }
}

extension FavoriteFoodDetailView {
    private func thumbnailForFood(_ food: StoredFavoriteFood) -> UIImage? {
        let map = UserDefaults.standard.favoriteFoodImageIDs
        guard let id = map[food.id] else { return nil }
        return FavoriteFoodImageStore.loadThumbnail(id: id)
    }
}
