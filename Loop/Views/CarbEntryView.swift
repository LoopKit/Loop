//
//  CarbEntryView.swift
//  Loop
//
//  Created by Noah Brauner on 7/19/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit

struct CarbEntryView: View, HorizontalSizeClassOverride {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors

    @ObservedObject var viewModel: CarbEntryViewModel
        
    @State private var expandedRow: Row?
    
    @State private var showHowAbsorptionTimeWorks = false
    @State private var showAddFavoriteFood = false
    @State private var showFavoriteFoodInsights = false
    
    private let isNewEntry: Bool

    init(viewModel: CarbEntryViewModel) {
        if viewModel.shouldBeginEditingQuantity {
            expandedRow = .amountConsumed
        }
        isNewEntry = viewModel.originalCarbEntry == nil
        self.viewModel = viewModel
    }
    
    var body: some View {
        if isNewEntry {
            NavigationView {
                let title = NSLocalizedString("carb-entry-title-add", value: "Add Carb Entry", comment: "The title of the view controller to create a new carb entry")
                content
                    .navigationBarTitle(title, displayMode: .inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            dismissButton
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            continueButton
                        }
                    }
            }
            .navigationViewStyle(.stack)
        }
        else {
            content
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        continueButton
                    }
                }
        }
    }
    
    private var content: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                warningsCard

                mainCard
                    .padding(.top, 8)
                
                continueActionButton
                
                if isNewEntry, FeatureFlags.allowExperimentalFeatures {
                    favoriteFoodsCard
                }
                
                if viewModel.selectedFavoriteFoodLastEaten != nil, FeatureFlags.allowExperimentalFeatures {
                    FavoriteFoodInsightsCardView(
                        showFavoriteFoodInsights: $showFavoriteFoodInsights,
                        foodName: viewModel.selectedFavoriteFood?.name,
                        lastEatenDate: viewModel.selectedFavoriteFoodLastEaten,
                        relativeDateFormatter: viewModel.relativeDateFormatter
                    )
                    .padding(.top, 8)
                }
                
                let isBolusViewActive = Binding(get: { viewModel.bolusViewModel != nil }, set: { _, _ in viewModel.bolusViewModel = nil })
                NavigationLink(destination: bolusView, isActive: isBolusViewActive) {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibility(hidden: true)
            }
        }
        .alert(item: $viewModel.alert, content: alert(for:))
        .sheet(isPresented: $showAddFavoriteFood, onDismiss: clearExpandedRow) {
            FavoriteFoodAddEditView(carbsQuantity: $viewModel.carbsQuantity.wrappedValue, foodType: $viewModel.foodType.wrappedValue, absorptionTime: $viewModel.absorptionTime.wrappedValue, onSave: onFavoriteFoodSave(_:))
        }
        .sheet(isPresented: $showHowAbsorptionTimeWorks) {
            HowAbsorptionTimeWorksView()
        }
        .sheet(isPresented: $showFavoriteFoodInsights) {
            if let food = viewModel.selectedFavoriteFood {
                FavoriteFoodInsightsView(viewModel: FavoriteFoodInsightsViewModel(delegate: viewModel.delegate, food: food))
            }
        }
    }
    
    private var mainCard: some View {
        VStack(spacing: 10) {
            let amountConsumedFocused: Binding<Bool> = Binding(get: { expandedRow == .amountConsumed }, set: { expandedRow = $0 ? .amountConsumed : nil })
            let timeFocused: Binding<Bool> = Binding(get: { expandedRow == .time }, set: { expandedRow = $0 ? .time : nil })
            let foodTypeFocused: Binding<Bool> = Binding(get: { expandedRow == .foodType }, set: { expandedRow = $0 ? .foodType : nil })
            let absorptionTimeFocused: Binding<Bool> = Binding(get: { expandedRow == .absorptionTime }, set: { expandedRow = $0 ? .absorptionTime : nil })
            // Food type row shows an x button next to favorite food chip that clears favorite food by setting this binding to nil
            let selectedFavoriteFoodBinding = Binding(
                get: { viewModel.selectedFavoriteFood },
                set: { food in
                    guard food == nil else { return }
                    viewModel.selectedFavoriteFoodIndex = -1
                }
            )
            
            CarbQuantityRow(quantity: $viewModel.carbsQuantity, isFocused: amountConsumedFocused, title: NSLocalizedString("Amount Consumed", comment: "Label for carb quantity entry row on carb entry screen"), preferredCarbUnit: viewModel.preferredCarbUnit)

            CardSectionDivider()
            
            DatePickerRow(date: $viewModel.time, isFocused: timeFocused, minimumDate: viewModel.minimumDate, maximumDate: viewModel.maximumDate)
            
            CardSectionDivider()
            
            FoodTypeRow(selectedFavoriteFood: selectedFavoriteFoodBinding, foodType: $viewModel.foodType, absorptionTime: $viewModel.absorptionTime, selectedDefaultAbsorptionTimeEmoji: $viewModel.selectedDefaultAbsorptionTimeEmoji, usesCustomFoodType: $viewModel.usesCustomFoodType, absorptionTimeWasEdited: $viewModel.absorptionTimeWasEdited, isFocused: foodTypeFocused, showClearFavoriteFoodButton: !isNewEntry, defaultAbsorptionTimes: viewModel.defaultAbsorptionTimes)
            
            CardSectionDivider()
            
            AbsorptionTimePickerRow(absorptionTime: $viewModel.absorptionTime, isFocused: absorptionTimeFocused, validDurationRange: viewModel.absorptionRimesRange, showHowAbsorptionTimeWorks: $showHowAbsorptionTimeWorks)
                .padding(.bottom, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .background(CardBackground())
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var bolusView: some View {
        if let viewModel = viewModel.bolusViewModel {
            BolusEntryView(viewModel: viewModel)
                .environmentObject(displayGlucosePreference)
                .environment(\.dismissAction, dismiss)
                .environment(\.guidanceColors, guidanceColors)
        }
    }
    
    private func clearExpandedRow() {
        self.expandedRow = nil
    }
}

// MARK: - Warnings & Alerts
extension CarbEntryView {
    private var warningsCard: some View {
        ForEach(Array(viewModel.warnings).sorted(by: { $0.priority < $1.priority })) { warning in
            warningView(for: warning)
                .padding(.vertical, 8)
                .padding(.horizontal)
                .background(CardBackground())
                .padding(.horizontal)
                .padding(.top, 8)
        }
    }
    
    private func warningView(for warning: CarbEntryViewModel.Warning) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(triangleColor(for: warning))
            
            Text(warningText(for: warning))
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func triangleColor(for warning: CarbEntryViewModel.Warning) -> Color {
        switch warning {
        case .entryIsMissedMeal:
            return .critical
        case .overrideInProgress:
            return .warning
        case .glucoseRisingRapidly:
            return .critical
        }
    }
    
    private func warningText(for warning: CarbEntryViewModel.Warning) -> String {
        switch warning {
        case .entryIsMissedMeal:
            return NSLocalizedString("Loop has detected an missed meal and estimated its size. Edit the carb amount to match the amount of any carbs you may have eaten.", comment: "Warning displayed when user is adding a meal from an missed meal notification")
        case .overrideInProgress:
            return NSLocalizedString("An active override is modifying your carb ratio and insulin sensitivity. If you don't want this to affect your bolus calculation and projected glucose, consider turning off the override.", comment: "Warning to ensure the carb entry is accurate during an override")
        case .glucoseRisingRapidly:
            return NSLocalizedString("Your glucose is rapidly rising. Check that any carbs you've eaten were logged. If you logged carbs, check that the time you entered lines up with when you started eating.", comment: "Warning to ensure the carb entry is accurate")
        }
    }
    
    private func alert(for alert: CarbEntryViewModel.Alert) -> SwiftUI.Alert {
        switch alert {
        case .maxQuantityExceded:
            let message = String(
                format: NSLocalizedString("The maximum allowed amount is %@ grams.", comment: "Alert body displayed for quantity greater than max (1: maximum quantity in grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: viewModel.maxCarbEntryQuantity.doubleValue(for: viewModel.preferredCarbUnit)), number: .none)
            )
            let okMessage = NSLocalizedString("com.loudnate.LoopKit.errorAlertActionTitle", value: "OK", comment: "The title of the action used to dismiss an error alert")
            return SwiftUI.Alert(
                title: Text("Large Meal Entered", comment: "Title of the warning shown when a large meal was entered"),
                message: Text(message),
                dismissButton: .cancel(Text(okMessage), action: viewModel.clearAlert)
            )
        case .warningQuantityValidation:
            let message = String(
                format: NSLocalizedString("Did you intend to enter %1$@ grams as the amount of carbohydrates for this meal?", comment: "Alert body when entered carbohydrates is greater than threshold (1: entered quantity in grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: viewModel.carbsQuantity ?? 0), number: .none)
            )
            return SwiftUI.Alert(
                title: Text("Large Meal Entered", comment: "Title of the warning shown when a large meal was entered"),
                message: Text(message),
                primaryButton: .default(Text("No, edit amount", comment: "The title of the action used when rejecting the the amount of carbohydrates entered."), action: viewModel.clearAlert),
                secondaryButton: .cancel(Text("Yes", comment: "The title of the action used when confirming entered amount of carbohydrates."), action: viewModel.clearAlertAndContinueToBolus)
            )
        }
    }
}

// MARK: - Favorite Foods Card
extension CarbEntryView {
    private var favoriteFoodsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FAVORITE FOODS")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 26)
            
            VStack(spacing: 10) {
                if !viewModel.favoriteFoods.isEmpty {
                    VStack {
                        HStack {
                            Text("Choose Favorite:")
                            
                            let selectedFavorite = favoritedFoodTextFromIndex(viewModel.selectedFavoriteFoodIndex)
                            Text(selectedFavorite)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        
                        if expandedRow == .favoriteFoodSelection {
                            Picker("", selection: $viewModel.selectedFavoriteFoodIndex) {
                                ForEach(-1..<viewModel.favoriteFoods.count, id: \.self) { index in
                                    Text(favoritedFoodTextFromIndex(index))
                                        .tag(index)
                                }
                            }
                            .pickerStyle(.wheel)
                        }
                    }
                    .onTapGesture {
                        withAnimation {
                            if expandedRow == .favoriteFoodSelection {
                                expandedRow = nil
                            }
                            else {
                                expandedRow = .favoriteFoodSelection
                            }
                        }
                    }
                    
                    if viewModel.selectedFavoriteFood == nil {
                        CardSectionDivider()
                    }
                }
                
                if viewModel.selectedFavoriteFood == nil {
                    Button(action: saveAsFavoriteFood) {
                        Text("Save as favorite food")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.saveFavoriteFoodButtonDisabled)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            .background(CardBackground())
            .padding(.horizontal)
            .onChange(of: viewModel.selectedFavoriteFoodIndex, perform: collapseFavoriteFoodsRowIfNeeded(_:))
        }
    }
    
    private func collapseFavoriteFoodsRowIfNeeded(_ newIndex: Int) {
        if newIndex != -1 {
            withAnimation {
                clearExpandedRow()
            }
        }
    }
    
    private func favoritedFoodTextFromIndex(_ index: Int) -> String {
        if index == -1 {
            return "None"
        }
        else {
            let food = viewModel.favoriteFoods[index]
            return "\(food.name) \(food.foodType)"
        }
    }
    
    private func saveAsFavoriteFood() {
        self.showAddFavoriteFood = true
    }
    
    private func onFavoriteFoodSave(_ food: NewFavoriteFood) {
        clearExpandedRow()
        self.showAddFavoriteFood = false
        viewModel.onFavoriteFoodSave(food)
    }
}

// MARK: - Other UI Elements
extension CarbEntryView {
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Cancel")
        }
    }
    
    private var continueButton: some View {
        Button(action: viewModel.continueToBolus) {
            Text("Continue")
        }
        .disabled(viewModel.continueButtonDisabled)
    }
    
    private var continueActionButton: some View {
        Button(action: viewModel.continueToBolus) {
            Text("Continue")
        }
        .buttonStyle(ActionButtonStyle())
        .padding()
        .disabled(viewModel.continueButtonDisabled)
    }
    
}

extension CarbEntryView {
    enum Row {
        case amountConsumed, time, foodType, absorptionTime, favoriteFoodSelection
    }
}
