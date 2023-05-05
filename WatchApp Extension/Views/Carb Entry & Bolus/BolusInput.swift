//
//  BolusInput.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/24/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit


struct BolusInput: View {
    @Binding var amount: Double
    var isComputingRecommendedAmount: Bool
    var recommendedAmount: Double?
    var pickerValues: BolusPickerValues
    var isEditable: Bool

    private var pickerValue: Binding<Int> {
        Binding(
            get: { self.pickerValues.index(of: self.amount) },
            set: { self.amount = self.pickerValues[$0] }
        )
    }

    private static let amountFormatter: NumberFormatter = {
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: .internationalUnit())
        return formatter.numberFormatter
    }()

    private static let recommendedAmountFormatter: NumberFormatter = {
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: .internationalUnit())
        return formatter.numberFormatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            DoseVolumeInput(
                volume: amount,
                isEditable: isEditable,
                increment: { self.amount = self.pickerValues[self.pickerValues.index(of: self.amount+0.5)] },
                decrement: { self.amount = self.pickerValues[self.pickerValues.index(of: self.amount-0.5)] },
                formatVolume: formatVolume
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
            let valueString = recommendedAmount.map { value in Self.recommendedAmountFormatter.string(from: value) ?? String(value) } ?? "–"
            return Text("REC: \(valueString) U", comment: "Recommended bolus amount label on Apple Watch")
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        // Look at surrounding bolus volumes to determine precision
        let previous = pickerValues.decrementing(volume, by: 1)
        let next = pickerValues.incrementing(volume, by: 1)
        let maxPrecision = 3
        let requiredPrecision = [previous, volume, next]
            .map { Decimal($0) }
            .deltaScale(boundedBy: maxPrecision)
        Self.amountFormatter.minimumFractionDigits = requiredPrecision
        return Self.amountFormatter.string(from: volume) ?? String(volume)
    }
}

fileprivate extension Decimal {
    func rounded(toPlaces scale: Int, roundingMode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var result = Decimal()
        var localCopy = self
        NSDecimalRound(&result, &localCopy, scale, roundingMode)
        return result
    }
}

fileprivate extension Collection where Element == Decimal {
    /// Returns the maximum number of decimal places necessary to meaningfully distinguish between adjacent values.
    /// - Precondition: The collection is sorted in ascending order.
    func deltaScale(boundedBy maxScale: Int) -> Int {
        let roundedToMaxScale = lazy.map { $0.rounded(toPlaces: maxScale) }
        guard let minDelta = roundedToMaxScale.adjacentPairs().map(-).map(abs).min() else {
            return 0
        }

        return abs(Swift.min(minDelta.exponent, 0))
    }
}
