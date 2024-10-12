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
                Section("Information") {
                    VStack(spacing: 16) {
                        let rows: [(field: String, value: String)] = [
                            (NSLocalizedString("Name", comment: "Label for name in favorite food entry"), food.name),
                            (NSLocalizedString("Carb Quantity", comment:"Label for carb quantity in favorite food entry"), food.carbsString(formatter: carbFormatter)),
                            (NSLocalizedString("Food Type", comment:"Label for food type in favorite food entry"), food.foodType),
                            (NSLocalizedString("Absorption Time", comment:"Label for absorption time in favorite food entry"), food.absorptionTimeString(formatter: absorptionTimeFormatter))
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
                
                Button(role: .destructive, action: { isConfirmingDelete.toggle() }) {
                    Text("Delete Food")
                        .frame(maxWidth: .infinity, alignment: .center) // Align text in center
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
