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
    private let settingsViewModel: SettingsViewModel
    private let statusTableViewModel: StatusTableViewModel
    
    let viewController: StatusTableViewController
    
    init(alertPermissionsChecker: AlertPermissionsChecker, alertMuter: AlertMuter, automaticDosingStatus: AutomaticDosingStatus, deviceDataManager: DeviceDataManager, onboardingManager: OnboardingManager, supportManager: SupportManager, testingScenariosManager: TestingScenariosManager?, settingsManager: SettingsManager, temporaryPresetsManager: TemporaryPresetsManager, loopDataManager: LoopDataManager, diagnosticReportGenerator: DiagnosticReportGenerator, simulatedData: SimulatedData, analyticsServicesManager: AnalyticsServicesManager, servicesManager: ServicesManager, carbStore: CarbStore, doseStore: DoseStore, criticalEventLogExportManager: CriticalEventLogExportManager, bluetoothStateManager: BluetoothStateManager, settingsViewModel: SettingsViewModel, statusTableViewModel: StatusTableViewModel) {
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
        self.settingsViewModel = settingsViewModel
        self.statusTableViewModel = statusTableViewModel
        
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
        statusTableViewController.settingsViewModel = settingsViewModel
        statusTableViewController.statusTableViewModel = statusTableViewModel
        bluetoothStateManager.addBluetoothObserver(statusTableViewController)
        
        self.viewController = statusTableViewController
    }
    
    func makeUIViewController(context: Context) -> some UIViewController {
        viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
}

@MainActor
@Observable
class StatusTableViewModel {
    let alertPermissionsChecker: AlertPermissionsChecker
    let alertMuter: AlertMuter
    let deviceDataManager: DeviceDataManager
    let supportManager: SupportManager
    let testingScenariosManager: TestingScenariosManager?
    let loopDataManager: LoopDataManager
    let diagnosticReportGenerator: DiagnosticReportGenerator
    let simulatedData: SimulatedData
    let analyticsServicesManager: AnalyticsServicesManager
    let servicesManager: ServicesManager
    let carbStore: CarbStore
    let doseStore: DoseStore
    let criticalEventLogExportManager: CriticalEventLogExportManager
    let bluetoothStateManager: BluetoothStateManager
    let settingsManager: SettingsManager
    let automaticDosingStatus: AutomaticDosingStatus
    let onboardingManager: OnboardingManager
    let temporaryPresetsManager: TemporaryPresetsManager
    let settingsViewModel: SettingsViewModel
    
    var pendingPreset: SelectablePreset? {
        didSet {
            settingsViewModel.presetsViewModel.pendingPreset = pendingPreset
        }
    }
    
    init(alertPermissionsChecker: AlertPermissionsChecker, alertMuter: AlertMuter, automaticDosingStatus: AutomaticDosingStatus, deviceDataManager: DeviceDataManager, onboardingManager: OnboardingManager, supportManager: SupportManager, testingScenariosManager: TestingScenariosManager?, settingsManager: SettingsManager, temporaryPresetsManager: TemporaryPresetsManager, loopDataManager: LoopDataManager, diagnosticReportGenerator: DiagnosticReportGenerator, simulatedData: SimulatedData, analyticsServicesManager: AnalyticsServicesManager, servicesManager: ServicesManager, carbStore: CarbStore, doseStore: DoseStore, criticalEventLogExportManager: CriticalEventLogExportManager, bluetoothStateManager: BluetoothStateManager, settingsViewModel: SettingsViewModel) {
        self.alertPermissionsChecker = alertPermissionsChecker
        self.alertMuter = alertMuter
        self.automaticDosingStatus = automaticDosingStatus
        self.deviceDataManager = deviceDataManager
        self.onboardingManager = onboardingManager
        self.supportManager = supportManager
        self.testingScenariosManager = testingScenariosManager
        self.temporaryPresetsManager = temporaryPresetsManager
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
        self.settingsViewModel = settingsViewModel
    }
}

struct StatusTableView: View {
    
    private let wrapped: WrappedStatusTableViewController
    
    var viewController: StatusTableViewController {
        wrapped.viewController
    }
    
    @ViewBuilder
    var wrappedView: some View { wrapped }
    
    @Bindable var viewModel: StatusTableViewModel
    
    init(viewModel: StatusTableViewModel) {
        self.viewModel = viewModel
        
        self.wrapped = WrappedStatusTableViewController(
            alertPermissionsChecker: viewModel.alertPermissionsChecker,
            alertMuter: viewModel.alertMuter,
            automaticDosingStatus: viewModel.automaticDosingStatus,
            deviceDataManager: viewModel.deviceDataManager,
            onboardingManager: viewModel.onboardingManager,
            supportManager: viewModel.supportManager,
            testingScenariosManager: viewModel.testingScenariosManager,
            settingsManager: viewModel.settingsManager,
            temporaryPresetsManager: viewModel.temporaryPresetsManager,
            loopDataManager: viewModel.loopDataManager,
            diagnosticReportGenerator: viewModel.diagnosticReportGenerator,
            simulatedData: viewModel.simulatedData,
            analyticsServicesManager: viewModel.analyticsServicesManager,
            servicesManager: viewModel.servicesManager,
            carbStore: viewModel.carbStore,
            doseStore: viewModel.doseStore,
            criticalEventLogExportManager: viewModel.criticalEventLogExportManager,
            bluetoothStateManager: viewModel.bluetoothStateManager,
            settingsViewModel: viewModel.settingsViewModel,
            statusTableViewModel: viewModel
        )
    }
    
    func isActive(action: ToolbarAction) -> Bool {
        switch action {
        case .addCarbs, .bolus, .settings: // No active states for these actions
            return false
        case .presets:
            return viewModel.settingsViewModel.presetsViewModel.activeOverride != nil
        }
    }
    
    func isDisabled(action: ToolbarAction) -> Bool {
        switch action {
        case .addCarbs, .bolus, .settings:
            false
        case .presets:
            !viewModel.onboardingManager.isComplete
        }
    }
    
    var body: some View {
        wrappedView
            .sheet(item: $viewModel.pendingPreset) { _ in
                PresetDetentView(
                    viewModel: viewModel.settingsViewModel.presetsViewModel
                )
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack(alignment: .bottom) {
                        ForEach(ToolbarAction.allCases) { action in
                            action.button(
                                showTitle: true,
                                isActive: isActive(action: action),
                                disabled: isDisabled(action: action)
                            ) {
                                switch action {
                                case .addCarbs:
                                    viewController.userTappedAddCarbs()
                                case .bolus:
                                    viewController.presentBolusScreen()
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
    case bolus
    case presets
    case settings
    
    var id: String { self.rawValue }
    
    var accessibilityIdentifier: String {
        switch self {
        case .addCarbs:
            "statusTableViewControllerCarbsButton"
        case .bolus:
            "statusTableViewControllerBolusButton"
        case .presets:
            "statusTableViewPresetsButton"
        case .settings:
            "statusTableViewControllerSettingsButton"
        }
    }
    
    @ViewBuilder
    func icon(isActive: Bool) -> some View {
        Group {
            switch self {
            case .addCarbs:
                Image("carbs")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.carbs)
            case .bolus:
                Image("bolus")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.insulin)
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
            case .bolus:
                Text("Bolus", comment: "The label of the bolus entry button")
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
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
