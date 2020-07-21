//
//  InsulinModelSelection.swift
//  Loop
//
//  Created by Michael Pangburn on 7/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import SwiftUI
import LoopCore
import LoopKit
import LoopKitUI
import LoopUI


final class InsulinModelSelectionViewModel: ObservableObject {
    @Published var insulinModelSettings: InsulinModelSettings
    var insulinSensitivitySchedule: InsulinSensitivitySchedule

    static let defaultInsulinSensitivitySchedule = InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue<Double>(startTime: 0, value: 40)])!

    static let defaultWalshInsulinModelDuration = TimeInterval(hours: 6)
    static let validWalshModelDurationRange = InsulinModelSettings.validWalshModelDurationRange

    var walshActionDuration: TimeInterval {
        get {
            if case .walsh(let walshModel) = insulinModelSettings {
                return walshModel.actionDuration
            } else {
                return Self.defaultWalshInsulinModelDuration
            }
        }
        set {
            precondition(Self.validWalshModelDurationRange.contains(newValue))
            insulinModelSettings = .walsh(WalshInsulinModel(actionDuration: newValue))
        }
    }

    init(insulinModelSettings: InsulinModelSettings, insulinSensitivitySchedule: InsulinSensitivitySchedule?) {
        self._insulinModelSettings = Published(wrappedValue: insulinModelSettings)
        self.insulinSensitivitySchedule = insulinSensitivitySchedule ?? Self.defaultInsulinSensitivitySchedule
    }
}

struct InsulinModelSelection: View, HorizontalSizeClassOverride {

    @ObservedObject var viewModel: InsulinModelSelectionViewModel
    var glucoseUnit: HKUnit
    var supportedModelSettings: SupportedInsulinModelSettings

    let chartManager: ChartsManager = {
        let chartManager = ChartsManager(
            colors: .default,
            settings: .default,
            charts: [InsulinModelChart()],
            traitCollection: .current
        )

        chartManager.startDate = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(minute: 0),
            matchingPolicy: .strict,
            direction: .backward
        ) ?? Date()

        return chartManager
    }()

    @Environment(\.appName) var appName
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    SettingDescription(
                        text: insulinModelSettingDescription,
                        informationalContent: {
                            // TODO: Implement informational content
                            Text("Not implemented")
                        }
                    )
                    .padding(4)
                    .padding(.top, 4)

                    VStack {
                        InsulinModelChartView(
                            chartManager: chartManager,
                            glucoseUnit: glucoseUnit,
                            selectedInsulinModelValues: selectedInsulinModelValues,
                            unselectedInsulinModelValues: unselectedInsulinModelValues,
                            glucoseDisplayRange: endingGlucoseQuantity...startingGlucoseQuantity
                        )
                        .frame(height: 170)

                        CheckmarkListItem(
                            title: Text(InsulinModelSettings.exponentialPreset(.humalogNovologAdult).title),
                            description: Text(InsulinModelSettings.exponentialPreset(.humalogNovologAdult).subtitle),
                            isSelected: isSelected(.exponentialPreset(.humalogNovologAdult))
                        )
                        .padding(.vertical, 4)
                    }

                    CheckmarkListItem(
                        title: Text(InsulinModelSettings.exponentialPreset(.humalogNovologChild).title),
                        description: Text(InsulinModelSettings.exponentialPreset(.humalogNovologChild).subtitle),
                        isSelected: isSelected(.exponentialPreset(.humalogNovologChild))
                    )
                    .padding(.vertical, 4)
                    .padding(.bottom, supportedModelSettings.fiaspModelEnabled ? 0 : 4)

                    if supportedModelSettings.fiaspModelEnabled {
                        CheckmarkListItem(
                            title: Text(InsulinModelSettings.exponentialPreset(.fiasp).title),
                            description: Text(InsulinModelSettings.exponentialPreset(.fiasp).subtitle),
                            isSelected: isSelected(.exponentialPreset(.fiasp))
                        )
                        .padding(.vertical, 4)
                    }

                    if supportedModelSettings.walshModelEnabled {
                        DurationBasedCheckmarkListItem(
                            title: Text(WalshInsulinModel.title),
                            description: Text(WalshInsulinModel.subtitle),
                            isSelected: isWalshModelSelected,
                            duration: $viewModel.walshActionDuration,
                            validDurationRange: InsulinModelSelectionViewModel.validWalshModelDurationRange
                        )
                        .padding(.vertical, 4)
                        .padding(.bottom, 4)
                    }
                }
                .buttonStyle(PlainButtonStyle()) // Disable row highlighting on selection
            }
            .listStyle(GroupedListStyle())
            .environment(\.horizontalSizeClass, horizontalOverride)
            .navigationBarTitle(Text(TherapySetting.insulinModel.title), displayMode: .large)
            .navigationBarItems(leading: dismissButton)
        }
    }

    var insulinModelSettingDescription: Text {
        let spellOutFormatter = NumberFormatter()
        spellOutFormatter.numberStyle = .spellOut
        return Text("\(appName) assumes insulin is actively working for 6 hours. You can choose from \(selectableInsulinModelSettings.count as NSNumber, formatter: spellOutFormatter) different models for how the app measures the insulin’s peak activity.", comment: "Insulin model setting description (1: app name) (2: number of models)")
    }

    var insulinModelChart: InsulinModelChart {
        chartManager.charts.first! as! InsulinModelChart
    }

    var selectableInsulinModelSettings: [InsulinModelSettings] {
        var options: [InsulinModelSettings] =  [
            .exponentialPreset(.humalogNovologAdult),
            .exponentialPreset(.humalogNovologChild)
        ]

        if supportedModelSettings.fiaspModelEnabled {
            options.append(.exponentialPreset(.fiasp))
        }

        if supportedModelSettings.walshModelEnabled {
            options.append(.walsh(WalshInsulinModel(actionDuration: viewModel.walshActionDuration)))
        }

        return options
    }

    private var selectedInsulinModelValues: [GlucoseValue] {
        oneUnitBolusEffectPrediction(using: viewModel.insulinModelSettings.model)
    }

    private var unselectedInsulinModelValues: [[GlucoseValue]] {
        selectableInsulinModelSettings
            .filter { $0 != viewModel.insulinModelSettings }
            .map { oneUnitBolusEffectPrediction(using: $0.model) }
    }

    private func oneUnitBolusEffectPrediction(using model: InsulinModel) -> [GlucoseValue] {
        let bolus = DoseEntry(type: .bolus, startDate: chartManager.startDate, value: 1, unit: .units)
        let startingGlucoseSample = HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!, quantity: startingGlucoseQuantity, start: chartManager.startDate, end: chartManager.startDate)
        let effects = [bolus].glucoseEffects(insulinModel: model, insulinSensitivity: viewModel.insulinSensitivitySchedule)
        return LoopMath.predictGlucose(startingAt: startingGlucoseSample, effects: effects)
    }

    private var startingGlucoseQuantity: HKQuantity {
        let startingGlucoseValue = viewModel.insulinSensitivitySchedule.quantity(at: chartManager.startDate).doubleValue(for: glucoseUnit) + glucoseUnit.glucoseExampleTargetValue
        return HKQuantity(unit: glucoseUnit, doubleValue: startingGlucoseValue)
    }

    private var endingGlucoseQuantity: HKQuantity {
        HKQuantity(unit: glucoseUnit, doubleValue: glucoseUnit.glucoseExampleTargetValue)
    }

    private func isSelected(_ settings: InsulinModelSettings) -> Binding<Bool> {
        Binding(
            get: { self.viewModel.insulinModelSettings == settings },
            set: { isSelected in
                if isSelected {
                    withAnimation {
                        self.viewModel.insulinModelSettings = settings
                    }
                }
            }
        )
    }

    private var isWalshModelSelected: Binding<Bool> {
        Binding(
            get: { self.viewModel.insulinModelSettings.model is WalshInsulinModel },
            set: { isSelected in
                if isSelected {
                    withAnimation {
                        self.viewModel.insulinModelSettings = .walsh(WalshInsulinModel(actionDuration: self.viewModel.walshActionDuration))
                    }
                }
            }
        )
    }

    var dismissButton: some View {
        Button(action: dismiss) {
            Text("Close", comment: "Button text to close a modal")
        }
    }
}

fileprivate extension HKUnit {
    /// An example value for the "ideal" target
    var glucoseExampleTargetValue: Double {
        if self == .milligramsPerDeciliter {
            return 100
        } else {
            return 5.5
        }
    }
}

fileprivate extension AnyTransition {
    static let fadeInFromTop = move(edge: .top).combined(with: .opacity)
        .delayingInsertion(by: 0.1)
        .speedingUpRemoval(by: 1.8)

    func delayingInsertion(by delay: TimeInterval) -> AnyTransition {
        .asymmetric(insertion: animation(Animation.default.delay(delay)), removal: self)
    }

    func speedingUpRemoval(by factor: Double) -> AnyTransition {
        .asymmetric(insertion: self, removal: animation(Animation.default.speed(factor)))
    }
}
