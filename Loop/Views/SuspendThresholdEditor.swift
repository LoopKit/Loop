//
//  SuspendThresholdEditor.swift
//  Loop
//
//  Created by Michael Pangburn on 4/10/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI


struct SuspendThresholdEditor: View {
    @State private var value: HKQuantity
    @State private var isEditing = false
    @State private var showingConfirmationAlert = false

    private let originalValue: HKQuantity?
    private let unit: HKUnit
    private let save: (_ suspendThreshold: HKQuantity) -> Void

    @Environment(\.dismiss) var dismiss

    init(value: HKQuantity?, unit: HKUnit, onSave save: @escaping (_ suspendThreshold: HKQuantity) -> Void) {
        self._value = State(initialValue: value ?? Self.defaultValue(for: unit))
        self.originalValue = value
        self.unit = unit
        self.save = save
    }

    private static func defaultValue(for unit: HKUnit) -> HKQuantity {
        switch unit {
        case .milligramsPerDeciliter:
            return HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)
        case .millimolesPerLiter:
            return HKQuantity(unit: .millimolesPerLiter, doubleValue: 4.5)
        default:
            fatalError("Unsupported glucose unit \(unit)")
        }
    }

    var body: some View {
        ConfigurationPage(
            title: Text("Suspend Threshold"),
            isSaveButtonEnabled: isSaveButtonEnabled,
            cards: {
                // TODO: Remove conditional when Swift 5.3 ships
                // https://bugs.swift.org/browse/SR-11628
                if true {
                    Card {
                        SuspendThresholdDescription()
                        SuspendThresholdPicker(value: $value, unit: unit, isEditing: $isEditing)
                    }
                }
            },
            actionAreaContent: {
                if warningThreshold != nil {
                    SuspendThresholdGuardrailWarning(safetyClassificationThreshold: warningThreshold!)
                        .padding(.horizontal)
                        .transition(AnyTransition.opacity.combined(with: .move(edge: .bottom)))
                }
            },
            onSave: {
                if self.warningThreshold == nil {
                    self.saveAndDismiss()
                } else {
                    self.showingConfirmationAlert = true
                }
            }
        )
        .alert(isPresented: $showingConfirmationAlert, content: confirmationAlert)
    }

    private var isSaveButtonEnabled: Bool {
        originalValue == nil || value != originalValue!
    }

    private var warningThreshold: SafetyClassification.Threshold? {
        switch Guardrail.suspendThreshold.classification(for: value) {
        case .withinRecommendedRange:
            return nil
        case .outsideRecommendedRange(let threshold):
            return threshold
        }
    }

    private func confirmationAlert() -> Alert {
        Alert(
            title: Text("Save Suspend Threshold?", comment: "Alert title for confirming a suspend threshold outside the recommended range"),
            message: Text("The suspend threshold you have entered is outside of what Tidepool generally recommends.", comment: "Alert message for confirming a suspend threshold outside the recommended range"),
            primaryButton: .cancel(Text("Go Back")),
            secondaryButton: .default(
                Text("Continue"),
                action: saveAndDismiss
            )
        )
    }

    private func saveAndDismiss() {
        save(value)
        dismiss()
    }
}

struct SuspendThresholdDescription: View {
    let text = Text("When your glucose is predicted to go below this value, the app will recommend a basal rate of 0 U/h and will not recommend a bolus.", comment: "Suspend threshold description")

    var body: some View {
        SettingDescription(text: text)
    }
}

struct SuspendThresholdGuardrailWarning: View {
    var safetyClassificationThreshold: SafetyClassification.Threshold

    var body: some View {
        GuardrailWarning(title: title, threshold: safetyClassificationThreshold)
    }

    private var title: Text {
        switch safetyClassificationThreshold {
        case .minimum, .belowRecommended:
            return Text("Low Suspend Threshold", comment: "Title text for the low suspend threshold warning")
        case .aboveRecommended, .maximum:
            return Text("High Suspend Threshold", comment: "Title text for the high suspend threshold warning")
        }
    }
}

struct SuspendThresholdView_Previews: PreviewProvider {
    static var previews: some View {
        SuspendThresholdEditor(value: nil, unit: .milligramsPerDeciliter, onSave: { _ in })
    }
}
