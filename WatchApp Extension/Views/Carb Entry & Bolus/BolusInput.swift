//
//  BolusInput.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/24/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI


struct BolusInput: View {
    @Binding var amount: Double
    var isComputingRecommendedAmount: Bool
    var recommendedAmount: Double?
    var maxBolus: Double
    var isEditable: Bool

    private var pickerValues: BolusPickerValues {
        BolusPickerValues(maxBolus: maxBolus)
    }

    private var pickerValue: Binding<Int> {
        Binding(
            get: { self.pickerValues.index(of: self.amount) },
            set: { self.amount = self.pickerValues[$0] }
        )
    }

    private static let formatter = NumberFormatter.bolus

    var body: some View {
        VStack(spacing: 0) {
            DoseVolumeInput(
                volume: amount,
                isEditable: isEditable,
                increment: { self.amount = self.pickerValues.incrementing(self.amount, by: 10) },
                decrement: { self.amount = self.pickerValues.decrementing(self.amount, by: 10) },
                formatVolume: Self.formatter.string(fromBolusValue:)
            )
            .focusable(isEditable)
            .digitalCrownRotation(
                pickerValue,
                over: ClosedRange(pickerValues.indices),
                rotationsPerIncrement: 1/24
            )

            if isEditable {
                recommendedAmountLabel
            }
        }
    }

    private var recommendedAmountLabel: some View {
        recommendedAmountLabelText
            .font(Font.footnote)
            .foregroundColor(.insulin)
            .transition(.opacity)
    }

    private var recommendedAmountLabelText: Text {
        if isComputingRecommendedAmount {
            return Text("REC: Calculating...", comment: "Indicator that recommended bolus computation is in progress on Apple Watch")
        } else {
            let value = recommendedAmount ?? 0
            let valueString = Self.formatter.string(from: value as NSNumber) ?? String(value)
            return Text("REC: \(valueString) U", comment: "Recommended bolus amount label on Apple Watch")
        }
    }
}
