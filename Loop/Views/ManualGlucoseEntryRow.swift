//
//  ManualGlucoseEntryRow.swift
//  Loop
//
//  Created by Pete Schwamb on 12/8/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit
import LoopKitUI
import Combine
import HealthKit

struct ManualGlucoseEntryRow: View {
    @EnvironmentObject private var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable

    @State private var valueText = ""

    @Binding var quantity: HKQuantity?

    let glucoseQuantityFormatter = QuantityFormatter()

    @State private var isManualGlucoseEntryRowVisible = false

    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        HStack {
            Text("Fingerstick Glucose", comment: "Label for manual glucose entry row on bolus screen")
            Spacer()

            HStack(alignment: .firstTextBaseline) {
                DismissibleKeyboardTextField(
                    text: $valueText,
                    placeholder: NSLocalizedString("– – –", comment: "No glucose value representation (3 dashes for mg/dL)"),
                    font: .heavy(.title1),
                    textAlignment: .right,
                    keyboardType: .decimalPad,
                    shouldBecomeFirstResponder: isManualGlucoseEntryRowVisible,
                    maxLength: 4,
                    doneButtonColor: .loopAccent
                )
                .onChange(of: valueText, perform: { value in
                    if let manualGlucoseValue = glucoseQuantityFormatter.numberFormatter.number(from: valueText)?.doubleValue {
                        quantity = HKQuantity(unit: displayGlucoseUnitObservable.displayGlucoseUnit, doubleValue: manualGlucoseValue)
                    } else {
                        quantity = nil
                    }
                })
                .onChange(of: displayGlucoseUnitObservable.displayGlucoseUnit, perform: { value in
                    unitsChanged()
                })

                Text(QuantityFormatter().string(from: displayGlucoseUnitObservable.displayGlucoseUnit))
                    .foregroundColor(Color(.secondaryLabel))
            }
        }
        .onKeyboardStateChange { state in
            if state.animationDuration > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + state.animationDuration) {
                     self.isManualGlucoseEntryRowVisible = true
                }
            }
        }
    }

    func unitsChanged() {
        glucoseQuantityFormatter.setPreferredNumberFormatter(for: displayGlucoseUnitObservable.displayGlucoseUnit)
        if let quantity = quantity {
            valueText = glucoseQuantityFormatter.string(from: quantity, for: displayGlucoseUnitObservable.displayGlucoseUnit, includeUnit: false) ?? ""
        }
    }
}
