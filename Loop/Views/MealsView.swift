//
//  MealsView.swift
//  Loop
//
//  Created by Noah Brauner on 7/12/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit

struct MealsView: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.carbTintColor) private var carbTintColor

    @State private var mealToConfirmDeleteId: String? = nil
    @State private var editMode: EditMode = .inactive
    
    @State private var meals = allMeals
    
    @State var isBolusViewActive = false
    @State var isEditViewActive = false
    @State var isAddViewActive = false

    @State var selectedMeal: Meal? = nil
    
    @State private var draggingMeal: Meal?
    @State private var hasChangedLocation: Bool = false

    var body: some View {
        NavigationViewWrappedContent {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        HStack {
                            Text("All Favorites")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            editButton
                        }
                        
                        ForEach(meals) { meal in
                            draggableMealCardView(meal: meal)
                        }
                    }
                    .environment(\.editMode, self.$editMode)
                    
                    newMealButton
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    dismissButton
                }
            }
            .navigationBarTitle(Text(NSLocalizedString("Favorite Foods", comment: "Favorite Foods screen title")))
            .navigationViewStyle(.stack)
            
            NavigationLink(destination: Text("Coming later:\nprepopulated carb entry screen").multilineTextAlignment(.center), isActive: $isBolusViewActive) {
                EmptyView()
            }
            
            NavigationLink(destination: Text("Coming later:\nedit favorite food screen").multilineTextAlignment(.center), isActive: $isEditViewActive) {
                EmptyView()
            }
            
            NavigationLink(destination: Text("Coming later:\nadd favorite food screen").multilineTextAlignment(.center), isActive: $isAddViewActive) {
                EmptyView()
            }
        }
        .onChange(of: editMode) { newValue in
            if !newValue.isEditing {
                mealToConfirmDeleteId = nil
            }
        }
    }
    
    private func addMeal() {
        isAddViewActive = true
    }
    
    private func onMealTap(_ meal: Meal) {
        selectedMeal = meal
        if editMode.isEditing {
            isEditViewActive = true
        }
        else {
            isBolusViewActive = true
        }
    }
    private func onMealDelete(_ meal: Meal) {
        withAnimation(.easeInOut(duration: 0.3)) {
            _ = meals.remove(meal)
        }
    }

    private func onMealReorder(from: IndexSet, to: Int) {
        withAnimation {
            meals.move(fromOffsets: from, toOffset: to)
        }
    }
}

extension MealsView {
    @ViewBuilder func draggableMealCardView(meal: Meal) -> some View {
        Button(action: {
            onMealTap(meal)
        }) {
            MealCardView(meal: meal, mealToConfirmDeleteId: $mealToConfirmDeleteId, onMealTap: onMealTap(_:), onMealDelete: onMealDelete(_:))
                .onDrag {
                    draggingMeal = meal
                    return NSItemProvider(object: "\(meal.id)" as NSString)
                } preview: {
                    MealCardView(meal: meal, mealToConfirmDeleteId: $mealToConfirmDeleteId, onMealTap: onMealTap(_:), onMealDelete: onMealDelete(_:))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: DragRelocateDelegate(
                        item: meal,
                        listData: meals,
                        current: $draggingMeal,
                        hasChangedLocation: $hasChangedLocation
                    ) { from, to in
                        onMealReorder(from: from, to: to)
                    }
                )
                .disabled(!editMode.isEditing)
                .buttonStyle(ListButtonStyle())
        }
    }
    
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Cancel")
        }
    }
    
//    private var plusButton: some View {
//        Button(action: addMeal) {
//            Image(systemName: "plus")
//        }
//    }
        
    private var editButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                editMode.toggle()
            }
        }) {
            Text(editMode.title)
        }
    }
    
    private var newMealButton: some View {
        Button(action: addMeal) {
            HStack {
                Image(systemName: "plus.circle.fill")
                
                Text("Add a new favorite food")
            }
        }
        .buttonStyle(ActionButtonStyle())
        .padding(.top)
    }
}

fileprivate struct NavigationViewWrappedContent<Content: View>: View {
    var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)
                
                content
            }
        }
    }
}

fileprivate struct DragRelocateDelegate<Item: Equatable>: DropDelegate {
    let item: Item
    var listData: [Item]
    @Binding var current: Item?
    @Binding var hasChangedLocation: Bool

    var moveAction: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard item != current, let current = current else { return }
        guard let from = listData.firstIndex(of: current), let to = listData.firstIndex(of: item) else { return }
        
        hasChangedLocation = true

        if listData[to] != current {
            moveAction(IndexSet(integer: from), to > from ? to + 1 : to)
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        hasChangedLocation = false
        current = nil
        return true
    }
}

fileprivate let allMeals = [
    // Some really yummy foods...
    Meal(carbsQuantity: carbs(55), foodType: "🥞🥚", absorptionTime: .hours(3), name: "Pancakes and Eggs"),
    Meal(carbsQuantity: carbs(35), foodType: "🍌🍞", absorptionTime: .hours(2), name: "Banana Bread"),
    Meal(carbsQuantity: carbs(63), foodType: "🍞🥜🍫🥛", absorptionTime: .hours(3), name: "The Best Lunch"),
    Meal(carbsQuantity: carbs(120), foodType: "🍕", absorptionTime: .hours(5), name: "Dad's Pizza"),
]

fileprivate func carbs(_ value: Double) -> HKQuantity {
    return HKQuantity(unit: .gram(), doubleValue: value)
}
