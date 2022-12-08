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

    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        HStack {
            Text("Fingerstick Glucose", comment: "Label for manual glucose entry row on bolus screen")
            Spacer()
            HStack(alignment: .firstTextBaseline) {
                SwiftUI.TextField(
                    NSLocalizedString("Fingerstick Glucose", comment: "Label for manual glucose entry row on bolus screen"),
                    text: $valueText,
                    prompt: Text("– – –", comment: "No glucose value representation (3 dashes for mg/dL)")
                )
                .multilineTextAlignment(.trailing)
                .onReceive(Just(valueText)) { _ in valueText = String(valueText.prefix(4)) }
                .onReceive(Just(displayGlucoseUnitObservable)) { _ in unitsChanged() }
                .font(Font(UIFont.heavy(.title1)))
                .keyboardType(.decimalPad)
//                .toolbar {
//                    ToolbarItemGroup(placement: .keyboard) {
//                        Spacer()
//                        Button("Done") {
//                            fieldIsFocused = false
//                        }
//                    }
//                }
                Text(QuantityFormatter().string(from: displayGlucoseUnitObservable.displayGlucoseUnit))
                    .foregroundColor(Color(.secondaryLabel))
            }
        }
    }

    func unitsChanged() {
        print("Here")
    }

//    private var enteredManualGlucose: Binding<String> {
//        Binding(
//            get: {
//                let displayGlucoseUnit = displayGlucoseUnitObservable.displayGlucoseUnit
//                viewModel.glucoseQuantityFormatter.setPreferredNumberFormatter(for: displayGlucoseUnit) // TODO: set this on units change
//                guard let manualGlucoseQuantity = viewModel.manualGlucoseQuantity,
//                      let manualGlucoseString = viewModel.glucoseQuantityFormatter.string(from: manualGlucoseQuantity, for: displayGlucoseUnit, includeUnit: false)
//                else {
//                    return ""
//                }
//                return  manualGlucoseString
//            },
//            set: { newValue in
//                viewModel.userDidChangeManualGlucose(newGlucose: newValue, unit: displayGlucoseUnitObservable.displayGlucoseUnit)
//            }
//        )
//    }


}
