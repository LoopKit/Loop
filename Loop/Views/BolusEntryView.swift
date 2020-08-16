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


struct BolusEntryView: View, HorizontalSizeClassOverride {
    @ObservedObject var viewModel: BolusEntryViewModel

    @State private var enteredBolusAmount = ""

    @State private var isManualGlucoseEntryRowVisible = false
    @State private var enteredManualGlucose = ""

    @State private var isInteractingWithChart = false
    @State private var isKeyboardVisible = false

    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            List {
                historySection
                summarySection
            }
            .padding(.top, -28) // Bring the top card up closer to the navigation bar
            .listStyle(GroupedListStyle())
            .environment(\.horizontalSizeClass, horizontalOverride)

            actionArea
                .frame(height: isKeyboardVisible ? 0 : nil)
                .opacity(isKeyboardVisible ? 0 : 1)
        }
        .onKeyboardStateChange { state in
            self.isKeyboardVisible = state.height > 0
        }
        .keyboardAware()
        .edgesIgnoringSafeArea(isKeyboardVisible ? [] : .bottom)
        .navigationBarTitle(
            title
        )
        .supportedInterfaceOrientations(.portrait)
        .alert(item: $viewModel.activeAlert, content: alert(for:))
        .onReceive(viewModel.$enteredBolus) { updatedBolusEntry in
            // The view model can update the user's entered bolus when the recommendation changes; ensure the text entry updates in tandem.
            let amount = updatedBolusEntry.doubleValue(for: .internationalUnit())
            self.enteredBolusAmount = amount == 0 ? "" : Self.doseAmountFormatter.string(from: amount) ?? String(amount)
        }
        .onReceive(viewModel.$isManualGlucoseEntryEnabled) { isManualGlucoseEntryEnabled in
            // The view model can disable manual glucose entry if CGM data returns.
            if !isManualGlucoseEntryEnabled {
                self.isManualGlucoseEntryRowVisible = false
                self.enteredManualGlucose = ""
            }
        }
    }
    
    private var title: Text {
        if viewModel.isLoggingDose {
            return Text("Log Dose", comment: "Title for dose logging screen")
        }
        return viewModel.potentialCarbEntry == nil ? Text("Bolus", comment: "Title for bolus entry screen") : Text("Meal Bolus", comment: "Title for bolus entry screen when also entering carbs")
    }

    private var historySection: some View {
        Section {
            VStack(spacing: 8) {
                HStack {
                    activeCarbsLabel
                    Spacer()
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
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var activeCarbsLabel: some View {
        if viewModel.activeCarbs != nil {
            LabeledQuantity(
                label: Text("Active Carbs", comment: "Title describing quantity of still-absorbing carbohydrates"),
                quantity: viewModel.activeCarbs!,
                unit: .gram()
            )
        }
    }

    @ViewBuilder
    private var activeInsulinLabel: some View {
        if viewModel.activeInsulin != nil {
            LabeledQuantity(
                label: Text("Active Insulin", comment: "Title describing quantity of still-absorbing insulin"),
                quantity: viewModel.activeInsulin!,
                unit: .internationalUnit(),
                maxFractionDigits: 2
            )
        }
    }

    private var predictedGlucoseChart: some View {
        PredictedGlucoseChartView(
            chartManager: viewModel.chartManager,
            glucoseUnit: viewModel.glucoseUnit,
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

                // A manual BG shouldn't be required to log a dose
                if viewModel.isLoggingDose {
                    datePicker
                } else if viewModel.isManualGlucoseEntryEnabled {
                    manualGlucoseEntryRow
                } else if viewModel.potentialCarbEntry != nil {
                    potentialCarbEntryRow
                } else {
                    recommendedBolusRow
                }
            }
            .padding(.top, 8)
            
            if viewModel.isLoggingDose {
                insulinModelPicker
            }

            if viewModel.isManualGlucoseEntryEnabled && viewModel.potentialCarbEntry != nil {
                potentialCarbEntryRow
            }

            if (viewModel.isManualGlucoseEntryEnabled && !viewModel.isLoggingDose) || viewModel.potentialCarbEntry != nil {
                recommendedBolusRow
            }

            bolusEntryRow
        }
    }
    
    private var titleText: Text {
        if viewModel.isLoggingDose {
            return Text("Dose Summary", comment: "Title for card to log dose")
        }
        return Text("Bolus Summary", comment: "Title for card displaying carb entry and bolus recommendation")
    }

    private var glucoseFormatter: NumberFormatter {
        QuantityFormatter(for: viewModel.glucoseUnit).numberFormatter
    }

    @ViewBuilder
    private var manualGlucoseEntryRow: some View {
        if viewModel.isManualGlucoseEntryEnabled {
            HStack {
                Text("Manual BG Entry", comment: "Label for manual glucose entry row on bolus screen")
                Spacer()
                HStack(alignment: .firstTextBaseline) {
                    DismissibleKeyboardTextField(
                        text: typedManualGlucoseEntry,
                        placeholder: "---",
                        font: typedManualGlucoseEntry.wrappedValue == "" ? .preferredFont(forTextStyle: .title1) : .heavy(.title1),
                        textAlignment: .right,
                        keyboardType: .decimalPad,
                        shouldBecomeFirstResponder: isManualGlucoseEntryRowVisible
                    )

                    Text(QuantityFormatter().string(from: viewModel.glucoseUnit))
                        .foregroundColor(Color(.secondaryLabel))
                }
            }
            .onAppear {
                // After the row is first made visible, make the text field the first responder
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
                    self.isManualGlucoseEntryRowVisible = true
                }
            }
        }
    }

    private var typedManualGlucoseEntry: Binding<String> {
        Binding(
            get: { self.enteredManualGlucose },
            set: { newValue in
                if let doubleValue = self.glucoseFormatter.number(from: newValue)?.doubleValue {
                    self.viewModel.enteredManualGlucose = HKQuantity(unit: self.viewModel.glucoseUnit, doubleValue: doubleValue)
                } else {
                    self.viewModel.enteredManualGlucose = nil
                }

                self.enteredManualGlucose = newValue
            }
        )
    }

    @ViewBuilder
    private var potentialCarbEntryRow: some View {
        if viewModel.carbEntryAmountAndEmojiString != nil && viewModel.carbEntryDateAndAbsorptionTimeString != nil {
            HStack {
                Text("Carb Entry", comment: "Label for carb entry row on bolus screen")

                Text(viewModel.carbEntryAmountAndEmojiString!)
                    .foregroundColor(Color(.cobTintColor))
                    .modifier(LabelBackground())

                Spacer()

                Text(viewModel.carbEntryDateAndAbsorptionTimeString!)
                    .foregroundColor(Color(.secondaryLabel))
            }
        }
    }

    private static let doseAmountFormatter: NumberFormatter = {
        let quantityFormatter = QuantityFormatter()
        quantityFormatter.setPreferredNumberFormatter(for: .internationalUnit())
        return quantityFormatter.numberFormatter
    }()

    private var recommendedBolusRow: some View {
        HStack {
            Text("Recommended Bolus", comment: "Label for recommended bolus row on bolus screen")
            Spacer()
            HStack(alignment: .firstTextBaseline) {
                Text(recommendedBolusString)
                    .font(.title)
                    .foregroundColor(viewModel.enteredBolus.doubleValue(for: .internationalUnit()) == 0 && viewModel.isBolusRecommended ? .accentColor : Color(.label))
                    .onTapGesture {
                        self.viewModel.acceptRecommendedBolus()
                    }

                bolusUnitsLabel
            }
        }
    }

    private var recommendedBolusString: String {
        let amount = viewModel.recommendedBolus?.doubleValue(for: .internationalUnit()) ?? 0
        return Self.doseAmountFormatter.string(from: amount) ?? String(amount)
    }
    
    private var insulinModelPicker: some View {
        ExpandablePicker(
            with: viewModel.insulinModelPickerOptions,
            onUpdate: { [weak viewModel] index in
                viewModel?.selectedInsulinModelIndex = index
            },
            label: NSLocalizedString("Insulin Model", comment: "Insulin model title")
        )
    }
    private var datePicker: some View {
        // Allow 6 hours before & after due to longest DIA
        ExpandableDatePicker(
            with: viewModel.selectedDoseDate,
            text: NSLocalizedString("Date", comment: "Date picker label"),
            onUpdate: { [weak viewModel] date in
                viewModel?.selectedDoseDate = date
            }
        )
    }

    private var bolusEntryRow: some View {
        HStack {
            Text("Bolus", comment: "Label for bolus entry row on bolus screen")
            Spacer()
            HStack(alignment: .firstTextBaseline) {
                DismissibleKeyboardTextField(
                    text: typedBolusEntry,
                    placeholder: Self.doseAmountFormatter.string(from: 0.0)!,
                    font: .preferredFont(forTextStyle: .title1),
                    textColor: .systemBlue,
                    textAlignment: .right,
                    keyboardType: .decimalPad
                )
                
                bolusUnitsLabel
            }
        }
    }

    private var bolusUnitsLabel: some View {
        Text(QuantityFormatter().string(from: .internationalUnit()))
            .foregroundColor(Color(.secondaryLabel))
    }

    private var typedBolusEntry: Binding<String> {
        Binding(
            get: { self.enteredBolusAmount },
            set: { newValue in
                self.viewModel.enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: Self.doseAmountFormatter.number(from: newValue)?.doubleValue ?? 0)
                self.enteredBolusAmount = newValue
            }
        )
    }

    private var actionArea: some View {
        VStack(spacing: 0) {
            if isNoticeVisible && !viewModel.isLoggingDose {
                warning(for: viewModel.activeNotice!)
                    .padding([.top, .horizontal])
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
            }

            if isManualGlucosePromptVisible && !viewModel.isLoggingDose {
                enterManualGlucoseButton
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
            }

            primaryActionButton
        }
        .padding(.bottom) // FIXME: unnecessary on iPhone 8 size devices
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }

    private var isNoticeVisible: Bool {
        if viewModel.activeNotice == nil {
            return false
        } else if viewModel.activeNotice != .staleGlucoseData {
            return true
        } else {
            return !viewModel.isManualGlucoseEntryEnabled
        }
    }

    private var isManualGlucosePromptVisible: Bool {
        viewModel.activeNotice == .staleGlucoseData && !viewModel.isManualGlucoseEntryEnabled && !viewModel.isLoggingDose
    }

    private func warning(for notice: BolusEntryViewModel.Notice) -> some View {
        switch notice {
        case .predictedGlucoseBelowSuspendThreshold(suspendThreshold: let suspendThreshold):
            let suspendThresholdString = QuantityFormatter().string(from: suspendThreshold, for: viewModel.glucoseUnit) ?? String(describing: suspendThreshold)
            return WarningView(
                title: Text("No Bolus Recommended", comment: "Title for bolus screen notice when no bolus is recommended"),
                caption: Text("Your glucose is below or predicted to go below your suspend threshold, \(suspendThresholdString).", comment: "Caption for bolus screen notice when no bolus is recommended due to prediction dropping below suspend threshold")
            )
        case .staleGlucoseData:
            return WarningView(
                title: Text("No Recent Glucose Data", comment: "Title for bolus screen notice when glucose data is missing or stale"),
                caption: Text("Enter a manual glucose for a recommended bolus amount.", comment: "Caption for bolus screen notice when glucose data is missing or stale")
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
            label: { Text("Enter Manual BG", comment: "Button text prompting manual glucose entry on bolus screen") }
        )
        .buttonStyle(ActionButtonStyle(.primary))
        .padding([.top, .horizontal])
    }

    private var primaryActionButton: some View {
        Button(
            action: {
                self.viewModel.saveAndDeliver(onSuccess: self.dismiss)
            },
            label: {
                if viewModel.isLoggingDose {
                    Text("Log Dose", comment: "Button text to log a dose")
                } else if canSaveWithoutBolusing {
                    Text("Save without Bolusing", comment: "Button text to save carbs and/or manual glucose entry without a bolus")
                } else {
                    Text("Save and Deliver", comment: "Button text to save carbs and/or manual glucose entry and deliver a bolus")
                }
            }
        )
        .buttonStyle(ActionButtonStyle(isManualGlucosePromptVisible ? .secondary : .primary))
        .padding()
        .disabled(isPrimaryActionButtonDisabled)
    }

    private var canSaveWithoutBolusing: Bool {
        (viewModel.enteredManualGlucose != nil || viewModel.potentialCarbEntry != nil)
            && viewModel.enteredBolus.doubleValue(for: .internationalUnit()) == 0
    }

    private var isPrimaryActionButtonDisabled: Bool {
        !canSaveWithoutBolusing && viewModel.enteredBolus.doubleValue(for: .internationalUnit()) == 0
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
            let formatter = QuantityFormatter(for: viewModel.glucoseUnit)
            let acceptableLowerBound = formatter.string(from: BolusEntryViewModel.validManualGlucoseEntryRange.lowerBound, for: viewModel.glucoseUnit) ?? String(describing: BolusEntryViewModel.validManualGlucoseEntryRange.lowerBound)
            let acceptableUpperBound = formatter.string(from: BolusEntryViewModel.validManualGlucoseEntryRange.upperBound, for: viewModel.glucoseUnit) ?? String(describing: BolusEntryViewModel.validManualGlucoseEntryRange.upperBound)
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
        }
    }
}

struct LabeledQuantity: View {
    var label: Text
    var quantity: HKQuantity
    var unit: HKUnit
    var maxFractionDigits: Int?

    var body: some View {
        HStack(spacing: 4) {
            label
                .bold()
            valueText
                .foregroundColor(Color(.secondaryLabel))
        }
        .font(.subheadline)
        .modifier(LabelBackground())
    }

    var valueText: Text {
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: unit)

        if let maxFractionDigits = maxFractionDigits {
            formatter.numberFormatter.maximumFractionDigits = maxFractionDigits
        }

        guard let string = formatter.string(from: quantity, for: unit) else {
            assertionFailure("Unable to format \(quantity) \(unit)")
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

extension Binding {
    func onChange(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
        return Binding(
            get: { self.wrappedValue },
            set: { selection in
                self.wrappedValue = selection
                handler(selection)
        })
    }
}
