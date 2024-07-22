//
//  AddEditFavoriteFoodView.swift
//  Loop
//
//  Created by Noah Brauner on 7/31/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct AddEditFavoriteFoodView: View {
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var viewModel: AddEditFavoriteFoodViewModel
    
    @State private var expandedRow: Row?
    @State private var showHowAbsorptionTimeWorks = false
    
    private var isNewEntry = true
        
    /// Initializer for adding a new favorite food or editing a `StoredFavoriteFood`
    init(originalFavoriteFood: StoredFavoriteFood? = nil, onSave: @escaping (NewFavoriteFood) -> Void) {
        self._viewModel = StateObject(wrappedValue: AddEditFavoriteFoodViewModel(originalFavoriteFood: originalFavoriteFood, onSave: onSave))
        self.isNewEntry = originalFavoriteFood == nil
    }
    
    /// Initializer for presenting the `AddEditFavoriteFoodView` prepopulated from the `CarbEntryView`
    init(carbsQuantity: Double?, foodType: String, absorptionTime: TimeInterval, onSave: @escaping (NewFavoriteFood) -> Void) {
        self._viewModel = StateObject(wrappedValue: AddEditFavoriteFoodViewModel(carbsQuantity: carbsQuantity, foodType: foodType, absorptionTime: absorptionTime, onSave: onSave))
    }
    
    var body: some View {
        if isNewEntry {
            NavigationView {
                content
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            dismissButton
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            saveButton
                        }
                    }
                    .navigationBarTitle("New Favorite Food", displayMode: .inline)
                    .onAppear {
                        expandedRow = .name
                    }
            }
        }
        else {
            content
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        if viewModel.updatedFavoriteFood != nil {
                            dismissButton
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        saveButton
                    }
                }
                .navigationBarBackButtonHidden(viewModel.updatedFavoriteFood != nil)
                .navigationBarTitle(viewModel.originalFavoriteFood?.title ?? "", displayMode: .inline)
        }
    }
    
    private var content: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                card
                    .padding(.top, 8)
                
                saveActionButton
            }
        }
        .alert(item: $viewModel.alert, content: alert(for:))
        .sheet(isPresented: $showHowAbsorptionTimeWorks) {
            HowAbsorptionTimeWorksView()
        }
    }
    
    private var card: some View {
        VStack(spacing: 10) {
            let nameFocused: Binding<Bool> = Binding(get: { expandedRow == .name }, set: { expandedRow = $0 ? .name : nil })
            let carbQuantityFocused: Binding<Bool> = Binding(get: { expandedRow == .carbQuantity }, set: { expandedRow = $0 ? .carbQuantity : nil })
            let foodTypeFocused: Binding<Bool> = Binding(get: { expandedRow == .foodType }, set: { expandedRow = $0 ? .foodType : nil })
            let absorptionTimeFocused: Binding<Bool> = Binding(get: { expandedRow == .absorptionTime }, set: { expandedRow = $0 ? .absorptionTime : nil })
            
            TextFieldRow(
                text: $viewModel.name,
                isFocused: nameFocused,
                title: NSLocalizedString("Name", comment: "Label for name in favorite food entry screen"),
                placeholder: NSLocalizedString("Apple", comment: "Placeholder for name in favorite food entry screen")
            )
            
            CardSectionDivider()

            CarbQuantityRow(
                quantity: $viewModel.carbsQuantity,
                isFocused: carbQuantityFocused,
                title: NSLocalizedString("Carb Quantity", comment: "Label for carb quantity in favorite food entry screen"),
                preferredCarbUnit: viewModel.preferredCarbUnit
            )
            
            CardSectionDivider()
            
            EmojiRow(
                text: $viewModel.foodType,
                isFocused: foodTypeFocused,
                emojiType: .food,
                title: NSLocalizedString("Food Type", comment: "Label for food type in favorite entry screen")
            )
            
            CardSectionDivider()

            AbsorptionTimePickerRow(
                absorptionTime: $viewModel.absorptionTime,
                isFocused: absorptionTimeFocused,
                validDurationRange: viewModel.absorptionRimesRange,
                showHowAbsorptionTimeWorks: $showHowAbsorptionTimeWorks
            )
            .padding(.bottom, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .background(CardBackground())
        .padding(.horizontal)
    }
    
    private func alert(for alert: AddEditFavoriteFoodViewModel.Alert) -> SwiftUI.Alert {
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
                secondaryButton: .cancel(Text("Yes", comment: "The title of the action used when confirming entered amount of carbohydrates."), action: viewModel.clearAlertAndSave)
            )
        }
    }
}

extension AddEditFavoriteFoodView {
    private var dismissButton: some View {
        Button(action: dismiss.callAsFunction) {
            Text("Cancel")
        }
    }
    
    private var saveActionButton: some View {
        Button(action: viewModel.save) {
            Text("Save")
        }
        .buttonStyle(ActionButtonStyle())
        .padding()
        .disabled(viewModel.updatedFavoriteFood == nil)
    }
    
    private var saveButton: some View {
        Button(action: viewModel.save) {
            Text("Save")
        }
        .disabled(viewModel.updatedFavoriteFood == nil)
    }
}

extension AddEditFavoriteFoodView {
    enum Row {
        case name, carbQuantity, foodType, absorptionTime
    }
}
