//
//  BolusEntryView.swift
//  Loop
//
//  Created by Michael Pangburn on 7/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Combine
import HealthKit
import SwiftUI
import LoopKit
import LoopKitUI
import LoopUI


struct BolusEntryView: View {
    @EnvironmentObject private var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable
    @Environment(\.dismissAction) var dismiss
    @Environment(\.appName) var appName
    
    @ObservedObject var viewModel: BolusEntryViewModel

    @State private var enteredBolusString = ""
    @State private var shouldBolusEntryBecomeFirstResponder = false

    @State private var isInteractingWithChart = false
    @State private var isKeyboardVisible = false
    @State private var pickerShouldExpand = false
    @State private var editedBolusAmount = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                List {
                    self.chartSection
                    self.summarySection
                }
                // As of iOS 13, we can't programmatically scroll to the Bolus entry text field.  This ugly hack scoots the
                // list up instead, so the summarySection is visible and the keyboard shows when you tap "Enter Bolus".
                // Unfortunately, after entry, the field scoots back down and remains hidden.  So this is not a great solution.
                // TODO: Fix this in Xcode 12 when we're building for iOS 14.
                .padding(.top, self.shouldAutoScroll(basedOn: geometry) ? -200 : -28)
                .insetGroupedListStyle()
                
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
            .navigationBarTitle(self.title)
            .supportedInterfaceOrientations(.portrait)
            .alert(item: self.$viewModel.activeAlert, content: self.alert(for:))
            .onReceive(self.viewModel.$recommendedBolus) { recommendation in
                // If the recommendation changes, and the user has not edited the bolus amount, update the bolus amount
                let amount = recommendation?.doubleValue(for: .internationalUnit()) ?? 0
                if !editedBolusAmount {
                    var newEnteredBolusString: String
                    if amount == 0 {
                        newEnteredBolusString = ""
                    } else {
                        newEnteredBolusString = viewModel.formatBolusAmount(amount)
                    }
                    enteredBolusStringBinding.wrappedValue = newEnteredBolusString
                }
            }
        }
    }
    
    private var title: Text {
        if viewModel.potentialCarbEntry == nil {
            return Text("Bolus", comment: "Title for bolus entry screen")
        }
        return Text("Meal Bolus", comment: "Title for bolus entry screen when also entering carbs")
    }

    private func shouldAutoScroll(basedOn geometry: GeometryProxy) -> Bool {
        // Taking a guess of 640 to cover iPhone SE, iPod Touch, and other smaller devices.
        // Devices such as the iPhone 11 Pro Max do not need to auto-scroll.
        return shouldBolusEntryBecomeFirstResponder && geometry.size.height > 640
    }
    
    private var chartSection: some View {
        Section {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    activeCarbsLabel
                    Spacer(minLength: 8)
                    activeInsulinLabel
                }

                // Use a ZStack to allow horizontally clipping the predicted glucose chart,
                // without clipping the point label on highlight, which draws outside the view's bounds.
                ZStack(alignment: .topLeading) {
                    Text("Glucose", comment: "Title for predicted glucose chart on bolus screen")
                        .font(.subheadline)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(isInteractingWithChart ? 0 : 1)

                    predictedGlucoseChart
                        .padding(.horizontal, -4)
                        .padding(.top, UIFont.preferredFont(forTextStyle: .subheadline).lineHeight + 8) // Leave space for the 'Glucose' label + spacing
                        .clipped()
                }
                .frame(height: ceil(UIScreen.main.bounds.height / 4))

                if !FeatureFlags.usePositiveMomentumAndRCForManualBoluses {
                    Divider()
                    Button(action: {
                        viewModel.activeAlert = .forecastInfo
                    }) {
                        HStack {
                            Text("Forecasted blood glucose may still be higher than target range.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "info.circle")
                                .font(.system(size: 25))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

            }
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var activeCarbsLabel: some View {
        LabeledQuantity(
            label: Text("Active Carbs", comment: "Title describing quantity of still-absorbing carbohydrates"),
            quantity: viewModel.activeCarbs,
            unit: .gram()
        )
    }
    
    @ViewBuilder
    private var activeInsulinLabel: some View {
        LabeledQuantity(
            label: Text("Active Insulin", comment: "Title describing quantity of still-absorbing insulin"),
            quantity: viewModel.activeInsulin,
            unit: .internationalUnit(),
            maxFractionDigits: 2
        )
    }

    private var predictedGlucoseChart: some View {
        PredictedGlucoseChartView(
            chartManager: viewModel.chartManager,
            glucoseUnit: displayGlucoseUnitObservable.displayGlucoseUnit,
            glucoseValues: viewModel.glucoseValues,
            predictedGlucoseValues: viewModel.predictedGlucoseValues,
            targetGlucoseSchedule: viewModel.targetGlucoseSchedule,
            preMealOverride: viewModel.preMealOverride,
            scheduleOverride: viewModel.scheduleOverride,
            dateInterval: viewModel.chartDateInterval,
            isInteractingWithChart: $isInteractingWithChart
        )
    }

    private var summarySection: some View {
        Section {
            VStack(spacing: 16) {
                titleText
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.isManualGlucoseEntryEnabled {
                    ManualGlucoseEntryRow(quantity: $viewModel.manualGlucoseQuantity)
                } else if viewModel.potentialCarbEntry != nil {
                    potentialCarbEntryRow
                } else {
                    recommendedBolusRow
                }
            }
            .padding(.top, 8)
            
            if viewModel.isManualGlucoseEntryEnabled && viewModel.potentialCarbEntry != nil {
                potentialCarbEntryRow
            }

            if viewModel.isManualGlucoseEntryEnabled || viewModel.potentialCarbEntry != nil {
                recommendedBolusRow
            }

            bolusEntryRow
        }
    }
    
    private var titleText: Text {
        return Text("Bolus Summary", comment: "Title for card displaying carb entry and bolus recommendation")
    }

    private var glucoseFormatter: NumberFormatter {
        QuantityFormatter(for: displayGlucoseUnitObservable.displayGlucoseUnit).numberFormatter
    }


    @ViewBuilder
    private var potentialCarbEntryRow: some View {
        if viewModel.carbEntryAmountAndEmojiString != nil && viewModel.carbEntryDateAndAbsorptionTimeString != nil {
            HStack {
                Text("Carb Entry", comment: "Label for carb entry row on bolus screen")

                Text(viewModel.carbEntryAmountAndEmojiString!)
                    .foregroundColor(Color(.carbTintColor))
                    .modifier(LabelBackground())

                Spacer()

                Text(viewModel.carbEntryDateAndAbsorptionTimeString!)
                    .foregroundColor(Color(.secondaryLabel))
            }
        }
    }

    private var recommendedBolusRow: some View {
        HStack {
            Text("Recommended Bolus", comment: "Label for recommended bolus row on bolus screen")
            Spacer()
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.recommendedBolusString)
                    .font(.title)
                    .foregroundColor(Color(.label))
                bolusUnitsLabel
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func didBeginEditing() {
        if !editedBolusAmount {
            enteredBolusStringBinding.wrappedValue = ""
            editedBolusAmount = true
        }
    }

    private var bolusEntryRow: some View {
        HStack {
            Text("Bolus", comment: "Label for bolus entry row on bolus screen")
            Spacer()
            HStack(alignment: .firstTextBaseline) {
                DismissibleKeyboardTextField(
                    text: enteredBolusStringBinding,
                    placeholder: viewModel.formatBolusAmount(0.0),
                    font: .preferredFont(forTextStyle: .title1),
                    textColor: .loopAccent,
                    textAlignment: .right,
                    keyboardType: .decimalPad,
                    shouldBecomeFirstResponder: shouldBolusEntryBecomeFirstResponder,
                    maxLength: 5,
                    doneButtonColor: .loopAccent,
                    textFieldDidBeginEditing: didBeginEditing
                )
                bolusUnitsLabel
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var bolusUnitsLabel: some View {
        Text(QuantityFormatter().string(from: .internationalUnit()))
            .foregroundColor(Color(.secondaryLabel))
    }

    private var enteredBolusStringBinding: Binding<String> {
        Binding(
            get: { enteredBolusString },
            set: { newValue in
                viewModel.updateEnteredBolus(newValue)
                enteredBolusString = newValue
            }
        )
    }

    private var actionArea: some View {
        VStack(spacing: 0) {
            if viewModel.isNoticeVisible {
                warning(for: viewModel.activeNotice!)
                    .padding([.top, .horizontal])
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
            }

            if viewModel.isManualGlucosePromptVisible {
                enterManualGlucoseButton
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
            }

            actionButton
        }
        .padding(.bottom) // FIXME: unnecessary on iPhone 8 size devices
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }

    private func warning(for notice: BolusEntryViewModel.Notice) -> some View {
        switch notice {
        case .predictedGlucoseBelowSuspendThreshold(suspendThreshold: let suspendThreshold):
            let suspendThresholdString = QuantityFormatter().string(from: suspendThreshold, for: displayGlucoseUnitObservable.displayGlucoseUnit) ?? String(describing: suspendThreshold)
            return WarningView(
                title: Text("No Bolus Recommended", comment: "Title for bolus screen notice when no bolus is recommended"),
                caption: Text("Your glucose is below or predicted to go below your glucose safety limit, \(suspendThresholdString).", comment: "Caption for bolus screen notice when no bolus is recommended due to prediction dropping below glucose safety limit")
            )
        case .staleGlucoseData:
            return WarningView(
                title: Text("No Recent Glucose Data", comment: "Title for bolus screen notice when glucose data is missing or stale"),
                caption: Text("Enter a blood glucose from a meter for a recommended bolus amount.", comment: "Caption for bolus screen notice when glucose data is missing or stale")
            )
        case .futureGlucoseData:
            return WarningView(
                title: Text("Invalid Future Glucose", comment: "Title for bolus screen notice when glucose data is in the future"),
                caption: Text("Check your device time and/or remove any invalid data from Apple Health.", comment: "Caption for bolus screen notice when glucose data is in the future")
            )
        case .stalePumpData:
            return WarningView(
                title: Text("No Recent Pump Data", comment: "Title for bolus screen notice when pump data is missing or stale"),
                caption: Text(String(format: NSLocalizedString("Your pump data is stale. %1$@ cannot recommend a bolus amount.", comment: "Caption for bolus screen notice when pump data is missing or stale"), appName)),
                severity: .critical
            )
        case .predictedGlucoseInRange, .glucoseBelowTarget:
            return WarningView(
                title: Text("No Bolus Recommended", comment: "Title for bolus screen notice when no bolus is recommended"),
                caption: Text("Based on your predicted glucose, no bolus is recommended.", comment: "Caption for bolus screen notice when no bolus is recommended for the predicted glucose")
            )
        }
    }
            
    private var enterManualGlucoseButton: some View {
        Button(
            action: {
                withAnimation {
                    self.viewModel.isManualGlucoseEntryEnabled = true
                }
            },
            label: { Text("Enter Fingerstick Glucose", comment: "Button text prompting manual glucose entry on bolus screen") }
        )
        .buttonStyle(ActionButtonStyle(viewModel.primaryButton == .manualGlucoseEntry ? .primary : .secondary))
        .padding([.top, .horizontal])
    }

    private var actionButton: some View {
        Button<Text>(
            action: {
                if self.viewModel.actionButtonAction == .enterBolus {
                    self.shouldBolusEntryBecomeFirstResponder = true
                } else {
                    Task {
                        if await self.viewModel.didPressActionButton() {
                            dismiss()
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
        .buttonStyle(ActionButtonStyle(viewModel.primaryButton == .actionButton ? .primary : .secondary))
        .disabled(viewModel.enacting)
        .padding()
    }

    private func alert(for alert: BolusEntryViewModel.Alert) -> SwiftUI.Alert {
        switch alert {
        case .recommendationChanged:
            return SwiftUI.Alert(
                title: Text("Bolus Recommendation Updated", comment: "Alert title for an updated bolus recommendation"),
                message: Text("The bolus recommendation has updated. Please reconfirm the bolus amount.", comment: "Alert message for an updated bolus recommendation")
            )
        case .maxBolusExceeded:
            guard let maximumBolusAmountString = viewModel.maximumBolusAmountString else {
                fatalError("Impossible to exceed max bolus without a configured max bolus")
            }
            return SwiftUI.Alert(
                title: Text("Exceeds Maximum Bolus", comment: "Alert title for a maximum bolus validation error"),
                message: Text("The maximum bolus amount is \(maximumBolusAmountString) U.", comment: "Alert message for a maximum bolus validation error (1: max bolus value)")
            )
        case .bolusTooSmall:
            return SwiftUI.Alert(
                title: Text("Bolus Too Small", comment: "Alert title for a bolus too small validation error"),
                message: Text("The bolus amount entered is smaller than the minimum deliverable.", comment: "Alert message for a bolus too small validation error")
            )
        case .noPumpManagerConfigured:
            return SwiftUI.Alert(
                title: Text("No Pump Configured", comment: "Alert title for a missing pump error"),
                message: Text("A pump must be configured before a bolus can be delivered.", comment: "Alert message for a missing pump error")
            )
        case .noMaxBolusConfigured:
            return SwiftUI.Alert(
                title: Text("No Maximum Bolus Configured", comment: "Alert title for a missing maximum bolus setting error"),
                message: Text("The maximum bolus setting must be configured before a bolus can be delivered.", comment: "Alert message for a missing maximum bolus setting error")
            )
        case .carbEntryPersistenceFailure:
            return SwiftUI.Alert(
                title: Text("Unable to Save Carb Entry", comment: "Alert title for a carb entry persistence error"),
                message: Text("An error occurred while trying to save your carb entry.", comment: "Alert message for a carb entry persistence error")
            )
        case .manualGlucoseEntryOutOfAcceptableRange:
            let formatter = QuantityFormatter(for: displayGlucoseUnitObservable.displayGlucoseUnit)
            let acceptableLowerBound = formatter.string(from: LoopConstants.validManualGlucoseEntryRange.lowerBound, for: displayGlucoseUnitObservable.displayGlucoseUnit) ?? String(describing: LoopConstants.validManualGlucoseEntryRange.lowerBound)
            let acceptableUpperBound = formatter.string(from: LoopConstants.validManualGlucoseEntryRange.upperBound, for: displayGlucoseUnitObservable.displayGlucoseUnit) ?? String(describing: LoopConstants.validManualGlucoseEntryRange.upperBound)
            return SwiftUI.Alert(
                title: Text("Glucose Entry Out of Range", comment: "Alert title for a manual glucose entry out of range error"),
                message: Text("A manual glucose entry must be between \(acceptableLowerBound) and \(acceptableUpperBound)", comment: "Alert message for a manual glucose entry out of range error")
            )
        case .manualGlucoseEntryPersistenceFailure:
            return SwiftUI.Alert(
                title: Text("Unable to Save Manual Glucose Entry", comment: "Alert title for a manual glucose entry persistence error"),
                message: Text("An error occurred while trying to save your manual glucose entry.", comment: "Alert message for a manual glucose entry persistence error")
            )
        case .glucoseNoLongerStale:
            return SwiftUI.Alert(
                title: Text("Glucose Data Now Available", comment: "Alert title when glucose data returns while on bolus screen"),
                message: Text("An updated bolus recommendation is available.", comment: "Alert message when glucose data returns while on bolus screen")
            )
        case .forecastInfo:
            return SwiftUI.Alert(
                title: Text("Forecasted Glucose", comment: "Title for forecast explanation modal on bolus view"),
                message: Text("The bolus dosing algorithm uses a more conservative estimate of forecasted blood glucose than what is used to adjust your basal rate.\n\nAs a result, your forecasted blood glucose after a bolus may still be higher than your target range.", comment: "Forecast explanation modal on bolus view")
            )
        }
    }
}

struct LabeledQuantity: View {
    var label: Text
    var quantity: HKQuantity?
    var unit: HKUnit
    var maxFractionDigits: Int?

    var body: some View {
        HStack(spacing: 4) {
            label
                .bold()
            valueText
                .foregroundColor(Color(.secondaryLabel))
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
        .font(.subheadline)
        .modifier(LabelBackground())
    }

    var valueText: Text {
        guard let quantity = quantity else {
            return Text("– –")
        }
        
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: unit)

        if let maxFractionDigits = maxFractionDigits {
            formatter.numberFormatter.maximumFractionDigits = maxFractionDigits
        }

        guard let string = formatter.string(from: quantity, for: unit) else {
            assertionFailure("Unable to format \(String(describing: quantity)) \(unit)")
            return Text("")
        }

        return Text(string)
    }
}

struct LabelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(.systemGray6))
            )
    }
}
