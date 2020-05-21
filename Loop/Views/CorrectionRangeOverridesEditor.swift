//
//  CorrectionRangeOverridesEditor.swift
//  Loop
//
//  Created by Michael Pangburn on 5/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI


struct CorrectionRangeOverrides: Equatable {
    enum Preset: Hashable {
        case preMeal
        case workout
    }

    var ranges: [Preset: ClosedRange<HKQuantity>]

    init(preMeal: DoubleRange?, workout: DoubleRange?, unit: HKUnit) {
        ranges = [:]
        ranges[.preMeal] = preMeal?.quantityRange(for: unit)
        ranges[.workout] = workout?.quantityRange(for: unit)
    }

    var preMeal: ClosedRange<HKQuantity>? { ranges[.preMeal] }
    var workout: ClosedRange<HKQuantity>? { ranges[.workout] }
}

struct CorrectionRangeOverridesEditor: View {
    var initialValue: CorrectionRangeOverrides
    var unit: HKUnit
    var minValue: HKQuantity?
    var save: (_ overrides: CorrectionRangeOverrides) -> Void

    @State var value: CorrectionRangeOverrides

    @State var presetBeingEdited: CorrectionRangeOverrides.Preset? {
        didSet {
            if let presetBeingEdited = presetBeingEdited, value.ranges[presetBeingEdited] == nil {
                value.ranges[presetBeingEdited] = guardrail(for: presetBeingEdited).recommendedBounds
            }
        }
    }

    @State var showingConfirmationAlert = false
    @Environment(\.dismiss) var dismiss

    init(
        value: CorrectionRangeOverrides,
        unit: HKUnit,
        minValue: HKQuantity?,
        onSave save: @escaping (_ overrides: CorrectionRangeOverrides) -> Void
    ) {
        self._value = State(initialValue: value)
        self.initialValue = value
        self.unit = unit
        self.minValue = minValue
        self.save = save
    }

    var body: some View {
        ConfigurationPage(
            title: Text("Temporary\nCorrection Ranges", comment: "Title for temporary correction ranges page"),
            isSaveButtonEnabled: value != initialValue,
            cards: {
                card(for: .preMeal)
                if !FeatureFlags.sensitivityOverridesEnabled {
                    card(for: .workout)
                }
            },
            actionAreaContent: {
                guardrailWarningIfNecessary
            },
            onSave: {
                if self.crossedThresholds.isEmpty {
                    self.saveAndDismiss()
                } else {
                    self.showingConfirmationAlert = true
                }
            }
        )
        .alert(isPresented: $showingConfirmationAlert, content: confirmationAlert)
    }

    private func card(for preset: CorrectionRangeOverrides.Preset) -> Card {
        Card {
            SettingDescription(text: description(of: preset))
            ExpandableSetting(
                isEditing: Binding(
                    get: { self.presetBeingEdited == preset },
                    set: { isEditing in
                        withAnimation {
                            self.presetBeingEdited = isEditing ? preset : nil
                        }
                    }
                ),
                leadingValueContent: {
                    HStack {
                        icon(for: preset)
                        name(of: preset)
                    }
                },
                trailingValueContent: {
                    GuardrailConstrainedQuantityRangeView(
                        range: value.ranges[preset],
                        unit: unit,
                        guardrail: self.guardrail(for: preset),
                        isEditing: presetBeingEdited == preset,
                        forceDisableAnimations: true
                    )
                },
                expandedContent: {
                    GlucoseRangePicker(
                        range: Binding(
                            get: { self.value.ranges[preset] ?? self.guardrail(for: preset).recommendedBounds },
                            set: { newValue in
                                withAnimation {
                                    self.value.ranges[preset] = newValue
                                }
                            }
                        ),
                        unit: unit,
                        minValue: minValue,
                        guardrail: self.guardrail(for: preset)
                    )
                }
            )
        }
    }

    private func description(of preset: CorrectionRangeOverrides.Preset) -> Text {
        switch preset {
        case .preMeal:
            return Text("Temporarily lower your glucose target before a meal to impact post-meal glucose spikes.", comment: "Description of pre-meal mode")
        case .workout:
            return Text("Temporarily raise your glucose target before, during, or after physical activity to reduce the risk of low glucose events.", comment: "Description of workout mode")
        }
    }

    private func name(of preset: CorrectionRangeOverrides.Preset) -> Text {
        switch preset {
        case .preMeal:
            return Text("Pre-Meal", comment: "Title for pre-meal mode configuration section")
        case .workout:
            return Text("Workout", comment: "Title for workout mode configuration section")
        }
    }

    private func icon(for preset: CorrectionRangeOverrides.Preset) -> some View {
        switch preset {
        case .preMeal:
            return icon(named: "Pre-Meal", tinted: Color(.COBTintColor))
        case .workout:
            return icon(named: "workout", tinted: Color(.glucoseTintColor))
        }
    }

    private func icon(named name: String, tinted color: Color) -> some View {
        Image(name)
            .renderingMode(.template)
            .foregroundColor(color)
    }

    private func guardrail(for preset: CorrectionRangeOverrides.Preset) -> Guardrail<HKQuantity> {
        // TODO: Guardrail bounds not yet finalized.
        switch preset {
        case .preMeal:
            return Guardrail(absoluteBounds: 60...180, recommendedBounds: 80...120, unit: .milligramsPerDeciliter)
        case .workout:
            return Guardrail(absoluteBounds: 60...180, recommendedBounds: 100...160, unit: .milligramsPerDeciliter)
        }
    }

    private var guardrailWarningIfNecessary: some View {
        let crossedThresholds = self.crossedThresholds
        return Group {
            if !crossedThresholds.isEmpty {
                CorrectionRangeOverridesGuardrailWarning(crossedThresholds: crossedThresholds)
            }
        }
    }

    private var crossedThresholds: [SafetyClassification.Threshold] {
        return value.ranges
            .flatMap { (preset, range) -> [SafetyClassification.Threshold] in
                let guardrail = self.guardrail(for: preset)
                return [range.lowerBound, range.upperBound].compactMap { bound in
                    switch guardrail.classification(for: bound) {
                    case .withinRecommendedRange:
                        return nil
                    case .outsideRecommendedRange(let threshold):
                        return threshold
                    }
                }
            }
    }

    private func confirmationAlert() -> Alert {
        Alert(
            title: Text("Save Correction Range Overrides?", comment: "Alert title for confirming correction range overrides outside the recommended range"),
            message: Text("One or more of the values you have entered are outside of what Tidepool generally recommends.", comment: "Alert message for confirming correction range overrides outside the recommended range"),
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

private struct CorrectionRangeOverridesGuardrailWarning: View {
    var crossedThresholds: [SafetyClassification.Threshold]

    var body: some View {
        assert(!crossedThresholds.isEmpty)
        return GuardrailWarning(
            title: crossedThresholds.count == 1 ? singularWarningTitle(for: crossedThresholds.first!) : multipleWarningTitle,
            thresholds: crossedThresholds
        )
    }

    private func singularWarningTitle(for threshold: SafetyClassification.Threshold) -> Text {
        switch threshold {
        case .minimum, .belowRecommended:
            return Text("Low Correction Value", comment: "Title text for the low correction value warning")
        case .aboveRecommended, .maximum:
            return Text("High Correction Value", comment: "Title text for the high correction value warning")
        }
    }

    private var multipleWarningTitle: Text {
        Text("Correction Values", comment: "Title text for multi-value correction value warning")
    }
}
