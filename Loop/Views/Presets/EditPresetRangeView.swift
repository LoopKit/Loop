//
//  EditPressRangeView.swift
//  Loop
//
//  Created by Pete Schwamb on 12/17/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//
import SwiftUI
import LoopKit
import LoopKitUI

struct EditPresetRangeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    @Binding var range: ClosedRange<LoopQuantity>?
    var guardrail: Guardrail<LoopQuantity>
    private var scheduledRange: ClosedRange<LoopQuantity>
    @State private var editedRange: ClosedRange<LoopQuantity>?
    private var isPreMeal: Bool

    init(range: Binding<ClosedRange<LoopQuantity>?>, guardrail: Guardrail<LoopQuantity>, scheduledRange: ClosedRange<LoopQuantity>, isPreMeal: Bool) {
        self._range = range
        self.guardrail = guardrail
        self.scheduledRange = scheduledRange
        self.isPreMeal = isPreMeal
    }

    var displayedRange: ClosedRange<LoopQuantity> {
        return editedRange ?? range ?? scheduledRange
    }

    func boundText(for bound: LoopQuantity) -> Text {
        let color = guardrail.color(for: bound, guidanceColors: guidanceColors)
        let text = displayGlucosePreference.format(bound, includeUnit: false)
        switch guardrail.classification(for: bound) {
        case .withinRecommendedRange:
            return Text(text)
                .foregroundColor(.accentColor)
                .font(.system(size: 42, weight: .semibold))
        case .outsideRecommendedRange:
            return (
                Text(Image(systemName: "exclamationmark.triangle.fill"))
                    .font(.system(size: 29, weight: .regular))
                    .baselineOffset(3.0)
                    .foregroundColor(color) +
                Text(text)
                    .foregroundColor(color)
                    .font(.system(size: 42, weight: .semibold))
                )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Correction Range")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                            Image(systemName: "info.circle")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(.accentColor)
                                .frame(width: UIFontMetrics.default.scaledValue(for: 14), height: UIFontMetrics.default.scaledValue(for: 14))
                        }
                        .padding(.top, 10)


                        Text("Set your correction range")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)

                        Text("To reduce the risk of highs or lows, you may want to set an adjusted range if you think your glucose will vary more than usual.")
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 0) {
                        Text("Adjusted Range")

                        (
                            boundText(for: (displayedRange).lowerBound) +
                            Text("-").foregroundColor(.secondary)
                                .font(.system(size: 42, weight: .light))
                            +
                            boundText(for: (displayedRange).upperBound)
                        )


                        Text(displayGlucosePreference.unit.localizedShortUnitString)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    GlucoseRangePicker(range: Binding(
                        get: { displayedRange },
                        set: { editedRange = $0 }),
                                       unit: displayGlucosePreference.unit,
                                       minValue: nil,
                                       guardrail: guardrail)
                    .padding(.vertical, -20)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.accentColor)

                        tipText.font(.system(size: 14))
                    }
                    .padding()
                    .overlay( /// apply a rounded border
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.gray, lineWidth: 1)
                    )
                }
            }
            actionArea
        }
        .navigationBarBackButtonHidden(editedRange != nil)
        .navigationBarItems(
            trailing: cancelButton
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Edit Preset")
        .edgesIgnoringSafeArea(.bottom)
    }

    private var tipText: some View {
        Group {
            if isPreMeal {
                Text("To help avoid post-meal highs, set a range ")
                 + Text("lower")
                    .italic()
                    .bold()
                 + Text(" than your typical correction range.")
            } else {
                Text("To help avoid lows, set a range ")
                 + Text("higher")
                    .italic()
                    .bold()
                 + Text(" than your typical correction range.")
            }
        }
    }

    private var cancelButton: some View {
        Group {
            if editedRange != nil {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.blue)
            }
        }
    }


    private var actionArea: some View {
        VStack(spacing: 0) {
            guardrailWarningIfNecessary
            actionButton
        }
        .background(Color(.secondarySystemGroupedBackground).shadow(radius: 5))
    }

    private var actionButton: some View {
        Button("Save") {
            range = editedRange
            dismiss()
        }
        .disabled(editedRange == nil)
        .buttonStyle(ActionButtonStyle(.primary))
        .padding()
    }


    var crossedThresholds: [SafetyClassification.Threshold] {
        if let range = editedRange ?? range {
            let lowerBound = range.lowerBound
            let upperBound = range.upperBound
            return [lowerBound, upperBound].compactMap { (bound) -> SafetyClassification.Threshold? in
                switch guardrail.classification(for: bound) {
                case .withinRecommendedRange:
                    return nil
                case .outsideRecommendedRange(let threshold):
                    return threshold
                }
            }
        } else {
            return []
        }
    }

    var guardrailWarningIfNecessary: some View {
        let crossedThresholds = self.crossedThresholds
        return Group {
            if !crossedThresholds.isEmpty {
                CorrectionRangeGuardrailWarning(crossedThresholds: crossedThresholds)
            }
        }.padding()
    }
}

private struct CorrectionRangeGuardrailWarning: View {
    var crossedThresholds: [SafetyClassification.Threshold]

    var body: some View {
        assert(!crossedThresholds.isEmpty)
        return GuardrailWarning(
            therapySetting: .glucoseTargetRange,
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
