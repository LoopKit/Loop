//
//  SuspendThresholdPicker.swift
//  Loop
//
//  Created by Michael Pangburn on 4/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI


struct SuspendThresholdPicker: View {
    @Binding var value: HKQuantity
    var unit: HKUnit
    @Binding var isEditing: Bool

    private var formatter: NumberFormatter

    init(value: Binding<HKQuantity>, unit: HKUnit, isEditing: Binding<Bool>) {
        self._value = value
        self.unit = unit
        self._isEditing = isEditing
        self.formatter = {
            let quantityFormatter = QuantityFormatter()
            quantityFormatter.setPreferredNumberFormatter(for: unit)
            return quantityFormatter.numberFormatter
        }()
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()

                if Guardrail.suspendThreshold.classification(for: value) != .withinRecommendedRange {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(accentColor)
                        .transition(.springInScaleOut)
                }

                Text(formatter.string(from: value.doubleValue(for: unit)) ?? "\(value.doubleValue(for: unit))")
                    .foregroundColor(accentColor)
                    .animation(nil)

                Text(unit.shortLocalizedUnitString())
                    .foregroundColor(.gray)
            }
            .onTapGesture {
                withAnimation {
                    self.isEditing.toggle()
                }
            }

            if isEditing {
                GlucoseValuePicker(value: $value.animation(), unit: unit, guardrail: .suspendThreshold)
                    .padding(.horizontal, -8)
                    .transition(.expandFromTop)
            }
        }
    }

    private var accentColor: Color {
        switch Guardrail.suspendThreshold.classification(for: value) {
        case .withinRecommendedRange:
            return isEditing ? .accentColor : .primary
        case .outsideRecommendedRange(let threshold):
            switch threshold {
            case .minimum, .maximum:
                return .severeWarning
            case .belowRecommended, .aboveRecommended:
                return .warning
            }
        }
    }
}

fileprivate extension AnyTransition {
    static let expandFromTop = move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0, anchor: .top))

    static let springInScaleOut = asymmetric(
        insertion: AnyTransition.scale.animation(.spring(dampingFraction: 0.5)),
        removal: AnyTransition.scale.combined(with: .opacity)
    )
}
