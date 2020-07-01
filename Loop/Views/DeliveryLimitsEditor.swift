//
//  DeliveryLimitsEditor.swift
//  Loop
//
//  Created by Michael Pangburn on 6/22/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI


struct DeliveryLimits: Equatable {
    enum Setting: Equatable {
        case maximumBasalRate
        case maximumBolus
    }

    var settings: [Setting: HKQuantity]

    init(maximumBasalRate: HKQuantity?, maximumBolus: HKQuantity?) {
        settings = [:]
        settings[.maximumBasalRate] = maximumBasalRate
        settings[.maximumBolus] = maximumBolus
    }

    var maximumBasalRate: HKQuantity? {
        get { settings[.maximumBasalRate] }
        set { settings[.maximumBasalRate] = newValue }
    }

    var maximumBolus: HKQuantity? {
        get { settings[.maximumBolus] }
        set { settings[.maximumBolus] = newValue }
    }
}


struct DeliveryLimitsEditor: View {
    var initialValue: DeliveryLimits
    var supportedBasalRates: [Double]
    var selectableBasalRates: [Double]
    var scheduledBasalRange: ClosedRange<Double>?
    var supportedBolusVolumes: [Double]
    var save: (_ deliveryLimits: DeliveryLimits) -> Void

    @State var value: DeliveryLimits

    @State var settingBeingEdited: DeliveryLimits.Setting?

    @State var showingConfirmationAlert = false
    @Environment(\.dismiss) var dismiss

    static let recommendedMaximumScheduledBasalScaleFactor: Double = 6

    init(
        value: DeliveryLimits,
        supportedBasalRates: [Double],
        scheduledBasalRange: ClosedRange<Double>?,
        supportedBolusVolumes: [Double],
        onSave save: @escaping (_ deliveryLimits: DeliveryLimits) -> Void
    ) {
        self._value = State(initialValue: value)
        self.initialValue = value
        self.supportedBasalRates = supportedBasalRates
        if let maximumScheduledBasalRate = scheduledBasalRange?.upperBound {
            self.selectableBasalRates = Array(supportedBasalRates.drop(while: { $0 < maximumScheduledBasalRate }))
        } else {
            self.selectableBasalRates = supportedBasalRates
        }
        self.scheduledBasalRange = scheduledBasalRange
        self.supportedBolusVolumes = supportedBolusVolumes
        self.save = save
    }

    var body: some View {
        ConfigurationPage(
            title: Text("Delivery Limits", comment: "Title for delivery limits page"),
            saveButtonState: saveButtonState,
            cards: {
                maximumBasalRateCard
                maximumBolusCard
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

    var saveButtonState: ConfigurationPageActionButtonState {
        guard value.maximumBasalRate != nil, value.maximumBolus != nil else {
            return .disabled
        }

        return value == initialValue ? .disabled : .enabled
    }

    var maximumBasalRateGuardrail: Guardrail<HKQuantity> {
        let minimumSupportedBasalRate = supportedBasalRates.first!
        let recommendedLowerBound = minimumSupportedBasalRate == 0 ? supportedBasalRates.dropFirst().first! : minimumSupportedBasalRate
        let recommendedUpperBound: Double
        if let maximumScheduledBasalRate = scheduledBasalRange?.upperBound {
            recommendedUpperBound = Self.recommendedMaximumScheduledBasalScaleFactor * maximumScheduledBasalRate
        } else {
            recommendedUpperBound = supportedBasalRates.last!
        }
        return Guardrail(
            absoluteBounds: supportedBasalRates.first!...supportedBasalRates.last!,
            recommendedBounds: recommendedLowerBound...recommendedUpperBound,
            unit: .internationalUnitsPerHour
        )
    }

    var maximumBasalRateCard: Card {
        Card {
            SettingDescription(text: Text("Maximum basal rate is the highest temporary basal rate Tidepool Loop is allowed to set automatically.", comment: "Maximum bolus setting description"))
            ExpandableSetting(
                isEditing: Binding(
                    get: { self.settingBeingEdited == .maximumBasalRate },
                    set: { isEditing in
                        withAnimation {
                            self.settingBeingEdited = isEditing ? .maximumBasalRate : nil
                        }
                    }
                ),
                leadingValueContent: {
                    Text("Maximum Basal Rate", comment: "Title text for maximum basal rate configuration")
                },
                trailingValueContent: {
                    GuardrailConstrainedQuantityView(
                        value: value.maximumBasalRate,
                        unit: .internationalUnitsPerHour,
                        guardrail: maximumBasalRateGuardrail,
                        isEditing: settingBeingEdited == .maximumBasalRate,
                        forceDisableAnimations: true
                    )
                },
                expandedContent: {
                    FractionalQuantityPicker(
                        value: Binding(
                            get: { self.value.maximumBasalRate ?? self.maximumBasalRateGuardrail.recommendedBounds.upperBound },
                            set: { newValue in
                                withAnimation {
                                    self.value.maximumBasalRate = newValue
                                }
                            }
                        ),
                        unit: .internationalUnitsPerHour,
                        guardrail: self.maximumBasalRateGuardrail,
                        selectableValues: self.selectableBasalRates,
                        usageContext: .independent
                    )
                }
            )
        }
    }

    var maximumBolusGuardrail: Guardrail<HKQuantity> {
        let maxBolusWarningThresholdUnits: Double = 20
        let minimumSupportedBolusVolume = supportedBolusVolumes.first!
        let recommendedLowerBound = minimumSupportedBolusVolume == 0 ? supportedBolusVolumes.dropFirst().first! : minimumSupportedBolusVolume
        let recommendedUpperBound = min(maxBolusWarningThresholdUnits.nextDown, supportedBolusVolumes.last!)
        return Guardrail(
            absoluteBounds: supportedBolusVolumes.first!...supportedBolusVolumes.last!,
            recommendedBounds: recommendedLowerBound...recommendedUpperBound,
            unit: .internationalUnit()
        )
    }

    var maximumBolusCard: Card {
        Card {
            SettingDescription(
                text: Text("Maximum bolus is the highest bolus amount you can deliver at one time.", comment: "Maximum basal rate setting description"))
            ExpandableSetting(
                isEditing: Binding(
                    get: { self.settingBeingEdited == .maximumBolus },
                    set: { isEditing in
                        withAnimation {
                            self.settingBeingEdited = isEditing ? .maximumBolus : nil
                        }
                    }
                ),
                leadingValueContent: {
                    Text("Maximum Bolus", comment: "Title text for maximum bolus configuration")
                },
                trailingValueContent: {
                    GuardrailConstrainedQuantityView(
                        value: value.maximumBolus,
                        unit: .internationalUnit(),
                        guardrail: maximumBolusGuardrail,
                        isEditing: settingBeingEdited == .maximumBolus,
                        forceDisableAnimations: true
                    )
                },
                expandedContent: {
                    FractionalQuantityPicker(
                        value: Binding(
                            get: { self.value.maximumBolus ?? self.maximumBolusGuardrail.recommendedBounds.upperBound },
                            set: { newValue in
                                withAnimation {
                                    self.value.maximumBolus = newValue
                                }
                            }
                        ),
                        unit: .internationalUnit(),
                        guardrail: self.maximumBolusGuardrail,
                        selectableValues: self.supportedBolusVolumes,
                        usageContext: .independent
                    )
                }
            )
        }
    }

    private var guardrailWarningIfNecessary: some View {
        let crossedThresholds = self.crossedThresholds
        return Group {
            if !crossedThresholds.isEmpty {
                DeliveryLimitsGuardrailWarning(crossedThresholds: crossedThresholds, maximumScheduledBasalRate: scheduledBasalRange?.upperBound)
            }
        }
    }

    private var crossedThresholds: [DeliveryLimits.Setting: SafetyClassification.Threshold] {
        var crossedThresholds: [DeliveryLimits.Setting: SafetyClassification.Threshold] = [:]

        switch value.maximumBasalRate.map(maximumBasalRateGuardrail.classification(for:)) {
        case nil, .withinRecommendedRange:
            break
        case .outsideRecommendedRange(let threshold):
            crossedThresholds[.maximumBasalRate] = threshold
        }

        switch value.maximumBolus.map(maximumBolusGuardrail.classification(for:)) {
        case nil, .withinRecommendedRange:
            break
        case .outsideRecommendedRange(let threshold):
            crossedThresholds[.maximumBolus] = threshold
        }

        return crossedThresholds
    }

    private func confirmationAlert() -> SwiftUI.Alert {
        SwiftUI.Alert(
            title: Text("Save Delivery Limits?", comment: "Alert title for confirming delivery limits outside the recommended range"),
            message: Text("One or more of the values you have entered are outside of what Tidepool generally recommends.", comment: "Alert message for confirming delivery limits outside the recommended range"),
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


struct DeliveryLimitsGuardrailWarning: View {
    var crossedThresholds: [DeliveryLimits.Setting: SafetyClassification.Threshold]
    var maximumScheduledBasalRate: Double?

    private static let scheduledBasalRateMultiplierFormatter = NumberFormatter()

    private static let basalRateFormatter: NumberFormatter = {
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: .internationalUnitsPerHour)
        return formatter.numberFormatter
    }()

    var body: some View {
        switch crossedThresholds.count {
        case 0:
            preconditionFailure("A guardrail warning requires at least one crossed threshold")
        case 1:
            let (setting, threshold) = crossedThresholds.first!
            let title: Text, caption: Text?
            switch setting {
            case .maximumBasalRate:
                switch threshold {
                case .minimum, .belowRecommended:
                    title = Text("Low Maximum Basal Rate", comment: "Title text for low maximum basal rate warning")
                    caption = Text("A setting of 0 U/hr means Tidepool Loop will not automatically administer insulin.", comment: "Caption text for low maximum basal rate warning")
                case .aboveRecommended, .maximum:
                    guard let maximumScheduledBasalRate = maximumScheduledBasalRate else {
                        preconditionFailure("No maximum basal rate warning can be generated without a maximum scheduled basal rate")
                    }

                    title = Text("High Maximum Basal Rate", comment: "Title text for high maximum basal rate warning")
                    let scheduledBasalRateMultiplierString = Self.scheduledBasalRateMultiplierFormatter.string(from: DeliveryLimitsEditor.recommendedMaximumScheduledBasalScaleFactor) ?? String(describing: DeliveryLimitsEditor.recommendedMaximumScheduledBasalScaleFactor)
                    let maximumScheduledBasalRateString = Self.basalRateFormatter.string(from: maximumScheduledBasalRate) ?? String(describing: maximumScheduledBasalRate)
                    caption = Text("The value you have entered exceeds \(scheduledBasalRateMultiplierString) times your highest scheduled basal rate of \(maximumScheduledBasalRateString) U/hr, which is higher than Tidepool generally recommends.", comment: "Caption text for high maximum basal rate warning")
                }
            case .maximumBolus:
                switch threshold {
                case .minimum, .belowRecommended:
                    title = Text("Low Maximum Bolus", comment: "Title text for low maximum bolus warning")
                    caption = Text("A setting of 0 U means you will not be able to bolus.", comment: "Caption text for zero maximum bolus setting warning")
                case .aboveRecommended, .maximum:
                    title = Text("High Maximum Bolus", comment: "Title text for high maximum bolus warning")
                    caption = nil
                }
            }

            return GuardrailWarning(title: title, threshold: threshold, caption: caption)
        case 2:
            return GuardrailWarning(
                title: Text("Delivery Limits"),
                thresholds: Array(crossedThresholds.values),
                caption: Text("The values you have entered are outside of what Tidepool generally recommends.", comment: "Caption text for warning where both delivery limits are outside the recommended range")
            )
        default:
            preconditionFailure("Unreachable: only two delivery limit settings exist")
        }
    }
}
