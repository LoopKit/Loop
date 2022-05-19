//
//  ManualEntryDoseView.swift
//  Loop
//
//  Created by Pete Schwamb on 12/29/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Combine
import HealthKit
import SwiftUI
import LoopKit
import LoopKitUI
import LoopUI


struct ManualEntryDoseView: View {
    @ObservedObject var viewModel: ManualEntryDoseViewModel

    @State private var enteredBolusString = ""
    @State private var shouldBolusEntryBecomeFirstResponder = false

    @State private var isInteractingWithChart = false
    @State private var isKeyboardVisible = false

    @Environment(\.dismissAction) var dismiss

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
        }
    }
    
    private var title: Text {
        return Text("Log Dose", comment: "Title for dose logging screen")
    }

    private func shouldAutoScroll(basedOn geometry: GeometryProxy) -> Bool {
        // Taking a guess of 640 to cover iPhone SE, iPod Touch, and other smaller devices.
        // Devices such as the iPhone 11 Pro Max do not need to auto-scroll.
        shouldBolusEntryBecomeFirstResponder && geometry.size.height < 640
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

                datePicker
            }
            .padding(.top, 8)
            
            insulinTypePicker

            bolusEntryRow
        }
    }
    
    private var titleText: Text {
        return Text("Dose Summary", comment: "Title for card to log dose")
    }

    private var glucoseFormatter: NumberFormatter {
        QuantityFormatter(for: viewModel.glucoseUnit).numberFormatter
    }

    private static let doseAmountFormatter: NumberFormatter = {
        let quantityFormatter = QuantityFormatter()
        quantityFormatter.setPreferredNumberFormatter(for: .internationalUnit())
        return quantityFormatter.numberFormatter
    }()
    
    private var insulinTypePicker: some View {
        ExpandablePicker(
            with: viewModel.insulinTypePickerOptions,
            selectedValue: $viewModel.selectedInsulinType,
            label: NSLocalizedString("Insulin Type", comment: "Insulin type label")
        )
    }
    private var datePicker: some View {
        // Allow 6 hours before & after due to longest DIA
        ZStack(alignment: .topLeading) {
            DatePicker(
                "",
                selection: $viewModel.selectedDoseDate,
                in: Date().addingTimeInterval(-.hours(6))...Date().addingTimeInterval(.hours(6)),
                displayedComponents: [.date, .hourAndMinute]
            )
            .pickerStyle(WheelPickerStyle())
            
            Text(NSLocalizedString("Date", comment: "Date picker label"))
        }
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
                    textColor: .loopAccent,
                    textAlignment: .right,
                    keyboardType: .decimalPad,
                    shouldBecomeFirstResponder: shouldBolusEntryBecomeFirstResponder,
                    maxLength: 5
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

    private var typedBolusEntry: Binding<String> {
        Binding(
            get: { self.enteredBolusString },
            set: { newValue in
                self.viewModel.enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: Self.doseAmountFormatter.number(from: newValue)?.doubleValue ?? 0)
                self.enteredBolusString = newValue
            }
        )
    }

    private var enteredBolusAmount: Double {
        Self.doseAmountFormatter.number(from: enteredBolusString)?.doubleValue ?? 0
    }

    private var actionButtonDisabled: Bool {
        enteredBolusAmount <= 0
    }

    private var actionArea: some View {
        VStack(spacing: 0) {
            actionButton.disabled(actionButtonDisabled)
        }
        .padding(.bottom) // FIXME: unnecessary on iPhone 8 size devices
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }
            
    private var actionButton: some View {
        Button<Text>(
            action: {
                self.viewModel.saveManualDose(onSuccess: self.dismiss)
            },
            label: {
                return Text("Log Dose", comment: "Button text to log a dose")
            }
        )
        .buttonStyle(ActionButtonStyle(.primary))
        .padding()
    }
}

extension InsulinType: Labeled {
    public var label: String {
        return title
    }
}
