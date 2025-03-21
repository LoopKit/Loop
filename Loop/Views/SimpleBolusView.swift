//
//  SimpleBolusView.swift
//  Loop
//
//  Created by Pete Schwamb on 9/23/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit
import LoopCore
import LoopAlgorithm

struct SimpleBolusView: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismissAction) var dismiss
    
    @State private var shouldGlucoseEntryBecomeFirstResponder = false
    @State private var isKeyboardVisible = false
    @State private var isClosedLoopOffInformationalModalVisible = false

    @ObservedObject var viewModel: SimpleBolusViewModel

    private var enteredManualGlucose: Binding<String> {
        Binding(
            get: { return viewModel.manualGlucoseString },
            set: { newValue in viewModel.manualGlucoseString = newValue }
        )
    }

    init(viewModel: SimpleBolusViewModel) {
        self.viewModel = viewModel
    }
    
    var title: String {
        if viewModel.displayMealEntry {
            return NSLocalizedString("Simple Meal Calculator", comment: "Title of simple bolus view when displaying meal entry")
        } else {
            return NSLocalizedString("Simple Bolus Calculator", comment: "Title of simple bolus view when not displaying meal entry")
        }
    }
        
    var body: some View {
        VStack(spacing: 0) {
            List() {
                self.infoSection
                self.summarySection
            }
            .insetGroupedListStyle()
            .navigationBarTitle(Text(self.title), displayMode: .inline)
            
            self.actionArea
                .frame(height: self.isKeyboardVisible ? 0 : nil)
                .opacity(self.isKeyboardVisible ? 0 : 1)
        }
        .onKeyboardStateChange { state in
            self.isKeyboardVisible = state.height > 0
            
            if state.height == 0 {
                // Ensure tapping 'Enter Bolus' can make the text field the first responder again
                self.shouldGlucoseEntryBecomeFirstResponder = false
            }
        }
        .keyboardAware()
        .edgesIgnoringSafeArea(self.isKeyboardVisible ? [] : .bottom)
        .alert(item: self.$viewModel.activeAlert, content: self.alert(for:))
    }
    
    private func formatGlucose(_ quantity: HKQuantity) -> String {
        return displayGlucosePreference.format(quantity)
    }
    
    private var infoSection: some View {
        HStack {
            Image("Open Loop")
            Text("When out of Closed Loop mode, the app uses a simplified bolus calculator like a typical pump.")
                .font(.footnote)
                .foregroundColor(.secondary)
            infoButton
        }
    }
    
    private var infoButton: some View {
        Button(
            action: {
                self.viewModel.activeAlert = .infoPopup
            },
            label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 25))
                    .foregroundColor(.accentColor)
            }
        )
    }
    
    private var summarySection: some View {
        Section {
            glucoseEntryRow
            if viewModel.displayMealEntry {
                carbEntryRow
            }
            recommendedBolusRow
            bolusEntryRow
        }
    }
    
    private var carbEntryRow: some View {
        HStack(alignment: .center) {
            Text("Carbohydrates", comment: "Label for carbohydrates entry row on simple bolus screen")
            Spacer()
            HStack {
                DismissibleKeyboardTextField(
                    text: $viewModel.enteredCarbString,
                    placeholder: viewModel.carbPlaceholder,
                    textAlignment: .right,
                    keyboardType: .decimalPad,
                    maxLength: 5,
                    doneButtonColor: .loopAccent
                )
                carbUnitsLabel
            }
            .padding([.top, .bottom], 5)
            .fixedSize()
            .modifier(LabelBackground())
        }
    }

    private var glucoseEntryRow: some View {
        HStack {
            Text("Current Glucose", comment: "Label for glucose entry row on simple bolus screen")
            Spacer()
            HStack(alignment: .firstTextBaseline) {
                DismissibleKeyboardTextField(
                    text: enteredManualGlucose,
                    placeholder: NSLocalizedString("– – –", comment: "No glucose value representation (3 dashes for mg/dL)"),
                    font: .heavy(.title1),
                    textAlignment: .right,
                    keyboardType: .decimalPad,
                    shouldBecomeFirstResponder: shouldGlucoseEntryBecomeFirstResponder,
                    maxLength: 4,
                    doneButtonColor: .loopAccent
                )
                .onAppear {
                    shouldGlucoseEntryBecomeFirstResponder = true
                }

                glucoseUnitsLabel
            }
            .fixedSize()
            .modifier(LabelBackground())
        }
    }
    
    private var recommendedBolusRow: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Recommended Bolus", comment: "Label for recommended bolus row on simple bolus screen")
                Spacer()
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.recommendedBolus)
                        .font(.title)
                        .foregroundColor(Color(.label))
                        .padding([.top, .bottom], 4)
                    bolusUnitsLabel
                }
            }
            .padding(.trailing, 8)
            if let activeInsulin = viewModel.activeInsulin {
                HStack(alignment: .center, spacing: 3) {
                    Text("Adjusted for")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("Active Insulin")
                        .font(.footnote)
                        .bold()
                    Text(activeInsulin)
                        .font(.footnote)
                        .bold()
                        .foregroundColor(.secondary)
                    bolusUnitsLabel
                        .font(.footnote)
                        .bold()
                }
            }
        }
    }
    
    private var bolusEntryRow: some View {
        HStack {
            Text("Bolus", comment: "Label for bolus entry row on simple bolus screen")
            Spacer()
            HStack(alignment: .firstTextBaseline) {
                DismissibleKeyboardTextField(
                    text: $viewModel.enteredBolusString,
                    placeholder: "0",
                    font: .preferredFont(forTextStyle: .title1),
                    textColor: .loopAccent,
                    textAlignment: .right,
                    keyboardType: .decimalPad,
                    maxLength: 5,
                    doneButtonColor: .loopAccent
                )
                
                bolusUnitsLabel
            }
            .fixedSize()
            .modifier(LabelBackground())
        }
    }

    private var carbUnitsLabel: some View {
        Text(QuantityFormatter(for: .gram()).localizedUnitStringWithPlurality())
            .foregroundColor(Color(.secondaryLabel))
    }
    
    private var glucoseUnitsLabel: some View {
        Text(displayGlucosePreference.formatter.localizedUnitStringWithPlurality())
            .fixedSize()
            .foregroundColor(Color(.secondaryLabel))
    }

    private var bolusUnitsLabel: Text {
        Text(QuantityFormatter(for: .internationalUnit()).localizedUnitStringWithPlurality())
            .foregroundColor(Color(.secondaryLabel))
    }

    private var actionArea: some View {
        VStack(spacing: 0) {
            if viewModel.isNoticeVisible {
                warning(for: viewModel.activeNotice!)
                    .padding([.top, .horizontal])
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
            }
            actionButton
        }
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }
    
    private var actionButton: some View {
        Button<Text>(
            action: {
                if self.viewModel.actionButtonAction == .enterBolus {
                    self.shouldGlucoseEntryBecomeFirstResponder = true
                } else {
                    Task {
                        if await viewModel.saveAndDeliver() {
                            self.dismiss()
                        }
                    }
                }
            },
            label: {
                switch viewModel.actionButtonAction {
                case .saveWithoutBolusing:
                    return Text("Save without Bolusing", comment: "Button text to save carbs and/or manual glucose entry without a bolus")
                case .saveAndDeliver:
                    return Text("Save and Deliver", comment: "Button text to save carbs and/or manual glucose entry and deliver a bolus")
                case .enterBolus:
                    return Text("Enter Bolus", comment: "Button text to begin entering a bolus")
                case .deliver:
                    return Text("Deliver", comment: "Button text to deliver a bolus")
                }
            }
        )
        .disabled(viewModel.actionButtonDisabled)
        .buttonStyle(ActionButtonStyle(.primary))
        .padding()
    }
    
    private func alert(for alert: SimpleBolusViewModel.Alert) -> SwiftUI.Alert {
        switch alert {
        case .carbEntryPersistenceFailure:
            return SwiftUI.Alert(
                title: Text("Unable to Save Carb Entry", comment: "Alert title for a carb entry persistence error"),
                message: Text("An error occurred while trying to save your carb entry.", comment: "Alert message for a carb entry persistence error")
            )
        case .manualGlucoseEntryPersistenceFailure:
            return SwiftUI.Alert(
                title: Text("Unable to Save Manual Glucose Entry", comment: "Alert title for a manual glucose entry persistence error"),
                message: Text("An error occurred while trying to save your manual glucose entry.", comment: "Alert message for a manual glucose entry persistence error")
            )
        case .infoPopup:
            return closedLoopOffInformationalModal()
        }
        
    }
        
    private func warning(for notice: SimpleBolusViewModel.Notice) -> some View {
        
        switch notice {
        case .glucoseBelowSuspendThreshold:
            let title: Text
            if viewModel.bolusRecommended {
                title = Text("Low Glucose", comment: "Title for bolus screen warning when glucose is below suspend threshold, but a bolus is recommended")
            } else {
                title = Text("No Bolus Recommended", comment: "Title for bolus screen warning when glucose is below suspend threshold, and a bolus is not recommended")
            }
            let suspendThresholdString = formatGlucose(viewModel.suspendThreshold!)
            return WarningView(
                title: title,
                caption: Text(String(format: NSLocalizedString("Your glucose is below your glucose safety limit, %1$@.", comment: "Format string for bolus screen warning when no bolus is recommended due input value below glucose safety limit. (1: suspendThreshold)"), suspendThresholdString))
            )
        case .glucoseWarning:
            let warningThresholdString = formatGlucose(LoopConstants.simpleBolusCalculatorGlucoseWarningLimit)
            return WarningView(
                title: Text("Low Glucose", comment: "Title for bolus screen warning when glucose is below glucose warning limit."),
                caption: Text(String(format: NSLocalizedString("Your glucose is below %1$@. Are you sure you want to bolus?", comment: "Format string for simple bolus screen warning when glucose is below glucose warning limit."), warningThresholdString))
            )
        case .glucoseBelowRecommendationLimit:
            let caption: String
            if viewModel.displayMealEntry {
                caption = NSLocalizedString("Your glucose is low. Eat carbs and consider waiting to bolus until your glucose is in a safe range.", comment: "Format string for meal bolus screen warning when no bolus is recommended due to glucose input value below recommendation threshold")
            } else {
                caption = NSLocalizedString("Your glucose is low. Eat carbs and monitor closely.", comment: "Bolus screen warning when no bolus is recommended due to glucose input value below recommendation threshold for meal bolus")
            }
            return WarningView(
                title: Text("No Bolus Recommended", comment: "Title for bolus screen warning when no bolus is recommended"),
                caption: Text(caption)
            )
        case .glucoseOutOfAllowedInputRange:
            let glucoseMinString = formatGlucose(LoopConstants.validManualGlucoseEntryRange.lowerBound)
            let glucoseMaxString = formatGlucose(LoopConstants.validManualGlucoseEntryRange.upperBound)
            return WarningView(
                title: Text("Glucose Entry Out of Range", comment: "Title for bolus screen warning when glucose entry is out of range"),
                caption: Text(String(format: NSLocalizedString("A manual glucose entry must be between %1$@ and %2$@.", comment: "Warning for simple bolus when glucose entry is out of range. (1: upper bound) (2: lower bound)"), glucoseMinString, glucoseMaxString)))
        case .maxBolusExceeded:
            return WarningView(
                title: Text("Maximum Bolus Exceeded", comment: "Title for bolus screen warning when max bolus is exceeded"),
                caption: Text(String(format: NSLocalizedString("Your maximum bolus amount is %1$@.", comment: "Warning for simple bolus when max bolus is exceeded. (1: maximum bolus)"), viewModel.maximumBolusAmountString )))
        case .recommendationExceedsMaxBolus:
            return WarningView(
                title: Text("Recommended Bolus Exceeds Maximum Bolus", comment: "Title for bolus screen warning when recommended bolus exceeds max bolus"),
                caption: Text(String(format: NSLocalizedString("Your recommended bolus exceeds your maximum bolus amount of %1$@.", comment: "Warning for simple bolus when recommended bolus exceeds max bolus. (1: maximum bolus)"), viewModel.maximumBolusAmountString )))
        case .carbohydrateEntryTooLarge:
            let maximumCarbohydrateString = QuantityFormatter(for: .gram()).string(from: LoopConstants.maxCarbEntryQuantity)!
            return WarningView(
                title: Text("Carbohydrate Entry Too Large", comment: "Title for bolus screen warning when carbohydrate entry is too large"),
                caption: Text(String(format: NSLocalizedString("The maximum amount allowed is %1$@.", comment: "Warning for simple bolus when carbohydrate entry is too large. (1: maximum carbohydrate entry)"), maximumCarbohydrateString)))
        }
    }
    
    private func closedLoopOffInformationalModal() -> SwiftUI.Alert {
        return SwiftUI.Alert(
            title: Text("Closed Loop OFF", comment: "Alert title for closed loop off informational modal"),
            message: Text(String(format: NSLocalizedString("%1$@ is operating with Closed Loop in the OFF position. Your pump and CGM will continue operating, but the app will not adjust dosing automatically.", comment: "Alert message for closed loop off informational modal. (1: app name)"), Bundle.main.bundleDisplayName))
        )
    }

}


struct SimpleBolusCalculatorView_Previews: PreviewProvider {
    class MockSimpleBolusViewDelegate: SimpleBolusViewModelDelegate {
        func saveGlucose(sample: NewGlucoseSample) async throws -> StoredGlucoseSample {
            return StoredGlucoseSample(startDate: sample.date, quantity: sample.quantity)
        }
        
        func addCarbEntry(_ carbEntry: LoopKit.NewCarbEntry, replacing replacingEntry: StoredCarbEntry?) async throws -> StoredCarbEntry {
            StoredCarbEntry(
                startDate: carbEntry.startDate,
                quantity: carbEntry.quantity,
                uuid: UUID(),
                provenanceIdentifier: UUID().uuidString,
                syncIdentifier: UUID().uuidString,
                syncVersion: 1,
                foodType: carbEntry.foodType,
                absorptionTime: carbEntry.absorptionTime,
                createdByCurrentApp: true,
                userCreatedDate: Date(),
                userUpdatedDate: nil)
        }
        
        func insulinOnBoard(at date: Date) async -> InsulinValue? {
            return nil
        }

        func enactBolus(units: Double, activationType: BolusActivationType) {
        }
        
        func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
            completion(.success(InsulinValue(startDate: date, value: 2.0)))
        }
        
        func computeSimpleBolusRecommendation(at date: Date, mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> BolusDosingDecision? {
            var decision = BolusDosingDecision(for: .simpleBolus)
            decision.manualBolusRecommendation = ManualBolusRecommendationWithDate(recommendation: ManualBolusRecommendation(amount: 3),
                                                                                   date: Date())
            return decision
        }
        
        func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        }
        
        var displayGlucosePreference: DisplayGlucosePreference {
            return DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
        }
        
        var maximumBolus: Double? {
            return 6
        }
        
        var suspendThreshold: HKQuantity? {
            return HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 75)
        }
    }

    static var previewViewModel: SimpleBolusViewModel = SimpleBolusViewModel(
        delegate: MockSimpleBolusViewDelegate(),
        displayMealEntry: true,
        displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
    )

    static var previews: some View {
        NavigationView {
            SimpleBolusView(viewModel: previewViewModel)
        }
        .previewDevice("iPod touch (7th generation)")
        .environmentObject(DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter))
    }
}
