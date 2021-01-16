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

struct SimpleBolusView: View {

    @Environment(\.dismiss) var dismiss
    
    @State private var shouldBolusEntryBecomeFirstResponder = false
    @State private var isKeyboardVisible = false
    @State private var isClosedLoopOffInformationalModalVisible = false

    var displayMealEntry: Bool
    @ObservedObject var viewModel: SimpleBolusViewModel
    
    init(displayMealEntry: Bool, viewModel: SimpleBolusViewModel) {
        self.displayMealEntry = displayMealEntry
        self.viewModel = viewModel
    }
    
    var title: String {
        if displayMealEntry {
            return NSLocalizedString("Simple Meal Calculator", comment: "Title of simple bolus view when displaying meal entry")
        } else {
            return NSLocalizedString("Simple Bolus Calculator", comment: "Title of simple bolus view when not displaying meal entry")
        }
    }
        
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                List() {
                    self.infoSection
                    self.summarySection
                }
                // As of iOS 13, we can't programmatically scroll to the Bolus entry text field.  This ugly hack scoots the
                // list up instead, so the summarySection is visible and the keyboard shows when you tap "Enter Bolus".
                // Unfortunately, after entry, the field scoots back down and remains hidden.  So this is not a great solution.
                // TODO: Fix this in Xcode 12 when we're building for iOS 14.
                .padding(.top, self.shouldAutoScroll(basedOn: geometry) ? -200 : 0)
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
                    self.shouldBolusEntryBecomeFirstResponder = false
                }
            }
            .keyboardAware()
            .edgesIgnoringSafeArea(self.isKeyboardVisible ? [] : .bottom)
            .alert(item: self.$viewModel.activeAlert, content: self.alert(for:))
        }
    }
    
    private func shouldAutoScroll(basedOn geometry: GeometryProxy) -> Bool {
        // Taking a guess of 640 to cover iPhone SE, iPod Touch, and other smaller devices.
        // Devices such as the iPhone 11 Pro Max do not need to auto-scroll.
        shouldBolusEntryBecomeFirstResponder && geometry.size.height < 640
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
            if displayMealEntry {
                carbEntryRow
            }
            glucoseEntryRow
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
                    text: $viewModel.enteredCarbAmount,
                    placeholder: viewModel.carbPlaceholder,
                    textAlignment: .right,
                    keyboardType: .decimalPad,
                    maxLength: 5
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
                    text: $viewModel.enteredGlucoseAmount,
                    placeholder: NSLocalizedString("– – –", comment: "No glucose value representation (3 dashes for mg/dL)"),
                    // The heavy title is ending up clipped due to a bug that is fixed in iOS 14.  Uncomment the following when we can build for iOS 14.
                    font: .preferredFont(forTextStyle: .title1), // .heavy(.title1),
                    textAlignment: .right,
                    keyboardType: .decimalPad,
                    maxLength: 3
                )

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
                    text: $viewModel.enteredBolusAmount,
                    placeholder: "",
                    font: .preferredFont(forTextStyle: .title1),
                    textColor: .loopAccent,
                    textAlignment: .right,
                    keyboardType: .decimalPad,
                    shouldBecomeFirstResponder: shouldBolusEntryBecomeFirstResponder,
                    maxLength: 5
                )
                
                bolusUnitsLabel
            }
            .fixedSize()
            .modifier(LabelBackground())
        }
    }

    private var carbUnitsLabel: some View {
        Text(QuantityFormatter().string(from: .gram()))
    }
    
    private var glucoseUnitsLabel: some View {
        Text(QuantityFormatter().string(from: viewModel.glucoseUnit))
            .fixedSize()
            .foregroundColor(Color(.secondaryLabel))
    }

    private var bolusUnitsLabel: Text {
        Text(QuantityFormatter().string(from: .internationalUnit()))
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
                    self.shouldBolusEntryBecomeFirstResponder = true
                } else {
                    self.viewModel.saveAndDeliver { (success) in
                        if success {
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
        .buttonStyle(ActionButtonStyle(.primary))
        .padding()
    }
    
    private func alert(for alert: SimpleBolusViewModel.Alert) -> SwiftUI.Alert {
        switch alert {
        case .maxBolusExceeded:
            guard let maximumBolusAmountString = viewModel.maximumBolusAmountString else {
                fatalError("Impossible to exceed max bolus without a configured max bolus")
            }
            return SwiftUI.Alert(
                title: Text("Exceeds Maximum Bolus", comment: "Alert title for a maximum bolus validation error"),
                message: Text(String(format: NSLocalizedString("The maximum bolus amount is %1$@ U.", comment: "Format string for maximum bolus exceeded alert (1: maximumBolusAmount)"), maximumBolusAmountString))
            )
        case .carbEntryPersistenceFailure:
            return SwiftUI.Alert(
                title: Text("Unable to Save Carb Entry", comment: "Alert title for a carb entry persistence error"),
                message: Text("An error occurred while trying to save your carb entry.", comment: "Alert message for a carb entry persistence error")
            )
        case .carbEntrySizeTooLarge:
            let message = String(
                format: NSLocalizedString("The maximum allowed amount is %1$@ grams", comment: "Alert body displayed for quantity greater than max (1: maximum quantity in grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: LoopConstants.maxCarbEntryQuantity.doubleValue(for: .gram())), number: .none)
            )
            return SwiftUI.Alert(
                title: Text("Carb Entry Too Large", comment: "Alert title for a carb entry too large error"),
                message: Text(message)
            )
        case .manualGlucoseEntryOutOfAcceptableRange:
            let formatter = QuantityFormatter(for: viewModel.glucoseUnit)
            let acceptableLowerBound = formatter.string(from: LoopConstants.validManualGlucoseEntryRange.lowerBound, for: viewModel.glucoseUnit) ?? String(describing: LoopConstants.validManualGlucoseEntryRange.lowerBound)
            let acceptableUpperBound = formatter.string(from: LoopConstants.validManualGlucoseEntryRange.upperBound, for: viewModel.glucoseUnit) ?? String(describing: LoopConstants.validManualGlucoseEntryRange.upperBound)
            return SwiftUI.Alert(
                title: Text("Glucose Entry Out of Range", comment: "Alert title for a manual glucose entry out of range error"),
                message: Text(String(format: NSLocalizedString("A manual glucose entry must be between %1$@ and %2$@", comment: "Alert message for a manual glucose entry out of range error. (1: acceptable lower bound) (2: acceptable upper bound)"), acceptableLowerBound, acceptableUpperBound))
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
            let suspendThresholdString = QuantityFormatter().string(from: viewModel.suspendThreshold, for: viewModel.glucoseUnit) ?? String(describing: viewModel.suspendThreshold)
            return WarningView(
                title: Text("No Bolus Recommended", comment: "Title for bolus screen notice when no bolus is recommended"),
                caption: Text(String(format: NSLocalizedString("Your glucose is below your glucose safety limit, %1$@.", comment: "Format string for bolus screen notice when no bolus is recommended due input value below glucose safety limit. (1: suspendThreshold)"), suspendThresholdString))
            )
        }
    }
    
    private func closedLoopOffInformationalModal() -> SwiftUI.Alert {
        return SwiftUI.Alert(
            title: Text("Closed Loop OFF", comment: "Alert title for closed loop off informational modal"),
            message: Text(String(format: NSLocalizedString("%1$@ is operating with Closed Loop in the OFF position. Your pump and CGM will continue operating, but your basal insulin will not adjust automatically.\n\n", comment: "Alert message for closed loop off informational modal. (1: app name)"), Bundle.main.bundleDisplayName))
        )
    }

}


struct SimpleBolusCalculatorView_Previews: PreviewProvider {
    class MockSimpleBolusViewDelegate: SimpleBolusViewModelDelegate {
        func addGlucose(_ samples: [NewGlucoseSample], completion: (Error?) -> Void) {
            completion(nil)
        }
        
        func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry?, completion: @escaping (Result<StoredCarbEntry>) -> Void) {
            
            let storedCarbEntry = StoredCarbEntry(
                uuid: UUID(),
                provenanceIdentifier: UUID().uuidString,
                syncIdentifier: UUID().uuidString,
                syncVersion: 1,
                startDate: carbEntry.startDate,
                quantity: carbEntry.quantity,
                foodType: carbEntry.foodType,
                absorptionTime: carbEntry.absorptionTime,
                createdByCurrentApp: true,
                userCreatedDate: Date(),
                userUpdatedDate: nil)
            completion(.success(storedCarbEntry))
        }
        
        func enactBolus(units: Double, at startDate: Date) {
        }
        
        func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
            completion(.success(InsulinValue(startDate: date, value: 2.0)))
        }
        
        func computeSimpleBolusRecommendation(at date: Date, mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> BolusDosingDecision? {
            var decision = BolusDosingDecision()
            decision.recommendedBolus = ManualBolusRecommendation(amount: 3, pendingInsulin: 0)
            return decision
        }
        
        func storeBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        }
        
        var preferredGlucoseUnit: HKUnit {
            return .milligramsPerDeciliter
        }
        
        var maximumBolus: Double {
            return 6
        }
        
        var suspendThreshold: HKQuantity {
            return HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 75)
        }
    }

    static var viewModel: SimpleBolusViewModel = SimpleBolusViewModel(delegate: MockSimpleBolusViewDelegate())
    
    static var previews: some View {
        NavigationView {
            SimpleBolusView(displayMealEntry: true, viewModel: viewModel)
        }
        .previewDevice("iPod touch (7th generation)")
    }
}
