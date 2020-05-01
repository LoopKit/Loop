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

    var body: some View {
        VStack {
            HStack {
                Spacer()
                GuardrailConstrainedQuantityView(value: value, unit: unit, guardrail: .suspendThreshold, isEditing: isEditing)
            }
            .contentShape(Rectangle())
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
}

fileprivate extension AnyTransition {
    static let expandFromTop = move(edge: .top)
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0, anchor: .top))
}
