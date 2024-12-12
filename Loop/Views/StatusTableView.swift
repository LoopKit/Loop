//
//  StatusTableView.swift
//  Loop
//
//  Created by Cameron Ingham on 12/10/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

private struct WrappedStatusTableViewController: UIViewControllerRepresentable {
    
    private let alertPermissionsChecker: AlertPermissionsChecker
    private let alertMuter: AlertMuter
    private let automaticDosingStatus: AutomaticDosingStatus
    private let deviceDataManager: DeviceDataManager
    private let onboardingManager: OnboardingManager
    private let supportManager: SupportManager
    private let testingScenariosManager: TestingScenariosManager?
    private let settingsManager: SettingsManager
    private let temporaryPresetsManager: TemporaryPresetsManager
    private let loopDataManager: LoopDataManager
    private let diagnosticReportGenerator: DiagnosticReportGenerator
    private let simulatedData: SimulatedData
    private let analyticsServicesManager: AnalyticsServicesManager
    private let servicesManager: ServicesManager
    private let carbStore: CarbStore
    private let doseStore: DoseStore
    private let criticalEventLogExportManager: CriticalEventLogExportManager
    private let bluetoothStateManager: BluetoothStateManager
    
    let viewController: StatusTableViewController
    
    init(alertPermissionsChecker: AlertPermissionsChecker, alertMuter: AlertMuter, automaticDosingStatus: AutomaticDosingStatus, deviceDataManager: DeviceDataManager, onboardingManager: OnboardingManager, supportManager: SupportManager, testingScenariosManager: TestingScenariosManager?, settingsManager: SettingsManager, temporaryPresetsManager: TemporaryPresetsManager, loopDataManager: LoopDataManager, diagnosticReportGenerator: DiagnosticReportGenerator, simulatedData: SimulatedData, analyticsServicesManager: AnalyticsServicesManager, servicesManager: ServicesManager, carbStore: CarbStore, doseStore: DoseStore, criticalEventLogExportManager: CriticalEventLogExportManager, bluetoothStateManager: BluetoothStateManager) {
        self.alertPermissionsChecker = alertPermissionsChecker
        self.alertMuter = alertMuter
        self.automaticDosingStatus = automaticDosingStatus
        self.deviceDataManager = deviceDataManager
        self.onboardingManager = onboardingManager
        self.supportManager = supportManager
        self.testingScenariosManager = testingScenariosManager
        self.settingsManager = settingsManager
        self.temporaryPresetsManager = temporaryPresetsManager
        self.loopDataManager = loopDataManager
        self.diagnosticReportGenerator = diagnosticReportGenerator
        self.simulatedData = simulatedData
        self.analyticsServicesManager = analyticsServicesManager
        self.servicesManager = servicesManager
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.criticalEventLogExportManager = criticalEventLogExportManager
        self.bluetoothStateManager = bluetoothStateManager
        
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: StatusTableViewController.self))
        let statusTableViewController = storyboard.instantiateViewController(withIdentifier: "MainStatusViewController") as! StatusTableViewController
        statusTableViewController.alertPermissionsChecker = alertPermissionsChecker
        statusTableViewController.alertMuter = alertMuter
        statusTableViewController.automaticDosingStatus = automaticDosingStatus
        statusTableViewController.deviceManager = deviceDataManager
        statusTableViewController.onboardingManager = onboardingManager
        statusTableViewController.supportManager = supportManager
        statusTableViewController.testingScenariosManager = testingScenariosManager
        statusTableViewController.settingsManager = settingsManager
        statusTableViewController.temporaryPresetsManager = temporaryPresetsManager
        statusTableViewController.loopManager = loopDataManager
        statusTableViewController.diagnosticReportGenerator = diagnosticReportGenerator
        statusTableViewController.simulatedData = simulatedData
        statusTableViewController.analyticsServicesManager = analyticsServicesManager
        statusTableViewController.servicesManager = servicesManager
        statusTableViewController.carbStore = carbStore
        statusTableViewController.doseStore = doseStore
        statusTableViewController.criticalEventLogExportManager = criticalEventLogExportManager
        bluetoothStateManager.addBluetoothObserver(statusTableViewController)
        
        self.viewController = statusTableViewController
    }
    
    func makeUIViewController(context: Context) -> some UIViewController {
        viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
}

struct StatusTableView: View {
    
    private let alertPermissionsChecker: AlertPermissionsChecker
    private let alertMuter: AlertMuter
    private let automaticDosingStatus: AutomaticDosingStatus
    private let deviceDataManager: DeviceDataManager
    private let displayGlucosePreference: DisplayGlucosePreference
    private let onboardingManager: OnboardingManager
    private let supportManager: SupportManager
    private let testingScenariosManager: TestingScenariosManager?
    private let settingsManager: SettingsManager
    private let loopDataManager: LoopDataManager
    private let diagnosticReportGenerator: DiagnosticReportGenerator
    private let simulatedData: SimulatedData
    private let analyticsServicesManager: AnalyticsServicesManager
    private let servicesManager: ServicesManager
    private let carbStore: CarbStore
    private let doseStore: DoseStore
    private let criticalEventLogExportManager: CriticalEventLogExportManager
    private let bluetoothStateManager: BluetoothStateManager
    
    @Bindable var settingsViewModel: SettingsViewModel
    
    private let wrapped: WrappedStatusTableViewController
    
    var viewController: StatusTableViewController {
        wrapped.viewController
    }
    
    init(displayGlucosePreference: DisplayGlucosePreference, alertPermissionsChecker: AlertPermissionsChecker, alertMuter: AlertMuter, automaticDosingStatus: AutomaticDosingStatus, deviceDataManager: DeviceDataManager, onboardingManager: OnboardingManager, supportManager: SupportManager, testingScenariosManager: TestingScenariosManager?, settingsManager: SettingsManager, temporaryPresetsManager: TemporaryPresetsManager, loopDataManager: LoopDataManager, diagnosticReportGenerator: DiagnosticReportGenerator, simulatedData: SimulatedData, analyticsServicesManager: AnalyticsServicesManager, servicesManager: ServicesManager, carbStore: CarbStore, doseStore: DoseStore, criticalEventLogExportManager: CriticalEventLogExportManager, bluetoothStateManager: BluetoothStateManager) {
        self.displayGlucosePreference = displayGlucosePreference
        self.alertPermissionsChecker = alertPermissionsChecker
        self.alertMuter = alertMuter
        self.automaticDosingStatus = automaticDosingStatus
        self.deviceDataManager = deviceDataManager
        self.onboardingManager = onboardingManager
        self.supportManager = supportManager
        self.testingScenariosManager = testingScenariosManager
        self.settingsManager = settingsManager
        self.loopDataManager = loopDataManager
        self.diagnosticReportGenerator = diagnosticReportGenerator
        self.simulatedData = simulatedData
        self.analyticsServicesManager = analyticsServicesManager
        self.servicesManager = servicesManager
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.criticalEventLogExportManager = criticalEventLogExportManager
        self.bluetoothStateManager = bluetoothStateManager
        
        self.wrapped = WrappedStatusTableViewController(alertPermissionsChecker: alertPermissionsChecker, alertMuter: alertMuter, automaticDosingStatus: automaticDosingStatus, deviceDataManager: deviceDataManager, onboardingManager: onboardingManager, supportManager: supportManager, testingScenariosManager: testingScenariosManager, settingsManager: settingsManager, temporaryPresetsManager: temporaryPresetsManager, loopDataManager: loopDataManager, diagnosticReportGenerator: diagnosticReportGenerator, simulatedData: simulatedData, analyticsServicesManager: analyticsServicesManager, servicesManager: servicesManager, carbStore: carbStore, doseStore: doseStore, criticalEventLogExportManager: criticalEventLogExportManager, bluetoothStateManager: bluetoothStateManager)
        
        self.settingsViewModel = wrapped.viewController.settingsViewModel
    }
    
    func isActive(action: ToolbarAction) -> Bool {
        switch action {
        case .addCarbs, .bolus, .settings: // No active states for these actions
            return false
        case .preMealPreset:
            return settingsViewModel.presetsViewModel.temporaryPresetsManager.preMealTargetEnabled()
        case .workoutPreset:
            return settingsViewModel.presetsViewModel.temporaryPresetsManager.nonPreMealOverrideEnabled()
        case .presets:
            return settingsViewModel.presetsViewModel.activeOverride != nil
        }
    }
    
    func isDisabled(action: ToolbarAction) -> Bool {
        switch action {
        case .addCarbs, .bolus, .presets, .settings:
            false
        case .preMealPreset:
            !(onboardingManager.isComplete &&
            (automaticDosingStatus.automaticDosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled)
            && settingsManager.settings.preMealTargetRange != nil)
        case .workoutPreset:
            viewController.workoutMode != nil && onboardingManager.isComplete
        }
    }
    
    var body: some View {
        wrapped
            .sheet(item: $settingsViewModel.presetsViewModel.pendingPreset) { preset in
                PresetDetentView(
                    viewModel: settingsViewModel.presetsViewModel,
                    preset: preset
                )
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack(alignment: .bottom) {
                        ForEach(ToolbarAction.new) { action in
                            action.button(
                                showTitle: true,
                                isActive: isActive(action: action),
                                disabled: isDisabled(action: action)
                            ) {
                                switch action {
                                case .addCarbs:
                                    viewController.userTappedAddCarbs()
                                case .preMealPreset:
                                    viewController.togglePreMealMode()
                                case .bolus:
                                    viewController.presentBolusScreen()
                                case .workoutPreset:
                                    viewController.presentCustomPresets()
                                case .presets:
                                    viewController.presentPresets()
                                case .settings:
                                    viewController.presentSettings()
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, -8)
                }
            }
    }
}

enum ToolbarAction: String, Identifiable, CaseIterable {
    case addCarbs
    case preMealPreset
    case bolus
    case workoutPreset
    case presets
    case settings
    
    static var legacy: [ToolbarAction] = [
        .addCarbs,
        .preMealPreset,
        .bolus,
        .workoutPreset,
        .settings
    ]
    
    static var new: [ToolbarAction] = [
        .addCarbs,
        .bolus,
        .presets,
        .settings
    ]
    
    var id: String { self.rawValue }
    
    @ViewBuilder
    func icon(isActive: Bool) -> some View {
        Group {
            switch self {
            case .addCarbs:
                Image("carbs")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.carbs)
            case .preMealPreset:
                Image(isActive ? "Pre-Meal Selected" : "Pre-Meal")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.carbs)
            case .bolus:
                Image("bolus")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.insulin)
            case .workoutPreset:
                Image(isActive ? "workout-selected" : "workout")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.glucose)
            case .presets:
                Image(isActive ? "presets-selected" : "presets")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.presets)
            case .settings:
                Image("settings")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color(UIColor.secondaryLabel))
            }
        }
        .frame(width: 32, height: 32)
        .aspectRatio(contentMode: .fit)
    }
    
    @ViewBuilder
    var title: some View {
        Group {
            switch self {
            case .addCarbs:
                Text("Add Carbs", comment: "The label of the carb entry button")
            case .preMealPreset:
                Text("Pre-Meal Preset", comment: "The label of the pre-meal mode toggle button")
            case .bolus:
                Text("Bolus", comment: "The label of the bolus entry button")
            case .workoutPreset:
                Text("Workout Preset", comment: "The label of the workout mode toggle button")
            case .presets:
                Text("Presets", comment: "The label of the presets button")
            case .settings:
                Text("Settings", comment: "The label of the settings button")
            }
        }
        .foregroundStyle(.secondary)
        .font(.footnote)
    }
    
    @ViewBuilder
    func button(showTitle: Bool, isActive: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon(isActive: isActive)
                
                if showTitle {
                    title
                }
            }
            .animation(.default, value: isActive)
            .padding(.vertical)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .contentShape(Rectangle())
    }
}
