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
    var correctionRangeScheduleRange: ClosedRange<HKQuantity>
    var minValue: HKQuantity?
    var save: (_ overrides: CorrectionRangeOverrides) -> Void

    @State var value: CorrectionRangeOverrides

    @State var presetBeingEdited: CorrectionRangeOverrides.Preset? {
        didSet {
            if let presetBeingEdited = presetBeingEdited, value.ranges[presetBeingEdited] == nil {
                value.ranges[presetBeingEdited] = initiallySelectedValue(for: presetBeingEdited)
            }
        }
    }

    @State var showingConfirmationAlert = false
    @Environment(\.dismiss) var dismiss

    init(
        value: CorrectionRangeOverrides,
        unit: HKUnit,
        correctionRangeScheduleRange: ClosedRange<HKQuantity>,
        minValue: HKQuantity?,
        onSave save: @escaping (_ overrides: CorrectionRangeOverrides) -> Void
    ) {
        self._value = State(initialValue: value)
        self.initialValue = value
        self.unit = unit
        self.correctionRangeScheduleRange = correctionRangeScheduleRange
        self.minValue = minValue
        self.save = save
    }

    var body: some View {
        ConfigurationPage(
            title: Text("Temporary\nCorrection Ranges", comment: "Title for temporary correction ranges page"),
            saveButtonState: value != initialValue ? .enabled : .disabled,
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
            SettingDescription(text: description(of: preset), informationalContent: {Text("To be implemented")})
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
                            get: { self.value.ranges[preset] ?? self.initiallySelectedValue(for: preset) },
                            set: { newValue in
                                withAnimation {
                                    self.value.ranges[preset] = newValue
                                }
                            }
                        ),
                        unit: self.unit,
                        minValue: self.selectableBounds(for: preset).lowerBound,
                        maxValue: self.selectableBounds(for: preset).upperBound,
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
        switch preset {
        case .preMeal:
            return Guardrail(
                absoluteBounds: Guardrail.correctionRange.absoluteBounds,
                recommendedBounds: Guardrail.correctionRange.recommendedBounds.lowerBound...max(correctionRangeScheduleRange.lowerBound, Guardrail.correctionRange.recommendedBounds.lowerBound)
            )
        case .workout:
            return Guardrail(
                absoluteBounds: Guardrail.correctionRange.absoluteBounds,
                recommendedBounds: max(Guardrail.correctionRange.recommendedBounds.lowerBound, correctionRangeScheduleRange.lowerBound)...Guardrail.correctionRange.absoluteBounds.upperBound
            )
        }
    }

    private func selectableBounds(for preset: CorrectionRangeOverrides.Preset) -> ClosedRange<HKQuantity> {
        switch preset {
        case .preMeal:
            if let minValue = minValue {
                return max(minValue, Guardrail.correctionRange.absoluteBounds.lowerBound)...correctionRangeScheduleRange.upperBound
            } else {
                return Guardrail.correctionRange.absoluteBounds.lowerBound...correctionRangeScheduleRange.upperBound
            }
        case .workout:
            if let minValue = minValue {
                return max(minValue, correctionRangeScheduleRange.upperBound)...Guardrail.correctionRange.absoluteBounds.upperBound
            } else {
                return correctionRangeScheduleRange.upperBound...Guardrail.correctionRange.absoluteBounds.upperBound
            }
        }
    }

    private func initiallySelectedValue(for preset: CorrectionRangeOverrides.Preset) -> ClosedRange<HKQuantity> {
        guardrail(for: preset).recommendedBounds.clamped(to: selectableBounds(for: preset))
    }

    private var guardrailWarningIfNecessary: some View {
        let crossedThresholds = self.crossedThresholds
        return Group {
            if !crossedThresholds.isEmpty {
                CorrectionRangeOverridesGuardrailWarning(crossedThresholds: crossedThresholds)
            }
        }
    }

    private var crossedThresholds: [CorrectionRangeOverrides.Preset: [SafetyClassification.Threshold]] {
        value.ranges
            .compactMapValuesWithKeys { preset, range in
                let guardrail = self.guardrail(for: preset)
                let thresholds: [SafetyClassification.Threshold] = [range.lowerBound, range.upperBound].compactMap { bound in
                    switch guardrail.classification(for: bound) {
                    case .withinRecommendedRange:
                        return nil
                    case .outsideRecommendedRange(let threshold):
                        return threshold
                    }
                }

                return thresholds.isEmpty ? nil : thresholds
            }
    }

    private func confirmationAlert() -> SwiftUI.Alert {
        SwiftUI.Alert(
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
    var crossedThresholds: [CorrectionRangeOverrides.Preset: [SafetyClassification.Threshold]]

    var body: some View {
        assert(!crossedThresholds.isEmpty)
        return GuardrailWarning(
            title: title,
            thresholds: Array(crossedThresholds.values.flatMap { $0 }),
            caption: caption
        )
    }

    private var title: Text {
        if crossedThresholds.count == 1, crossedThresholds.values.first!.count == 1 {
            return singularWarningTitle(for: crossedThresholds.values.first!.first!)
        } else {
            return multipleWarningTitle
        }
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

    var caption: Text? {
        guard
            crossedThresholds.count == 1,
            let crossedPreMealThresholds = crossedThresholds[.preMeal]
        else {
            return nil
        }

        return crossedPreMealThresholds.allSatisfy { $0 == .aboveRecommended || $0 == .maximum }
            ? Text("The value you have entered for this range is higher than your usual correction range. Tidepool typically recommends your pre-meal range be lower than your usual correction range.", comment: "Warning text for high pre-meal target value")
            : nil
    }
}
