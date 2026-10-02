//
//  StatusTableViewModel.swift
//  Loop
//
//  Created by Pete Schwamb on 3/19/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopCore

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
    let onboardingManager: OnboardingManager
    let temporaryPresetsManager: TemporaryPresetsManager
    let settingsViewModel: SettingsViewModel

    var pendingPreset: SelectablePreset?
    var isPodLoanedToWatch = false

    init(alertPermissionsChecker: AlertPermissionsChecker, alertMuter: AlertMuter, deviceDataManager: DeviceDataManager, onboardingManager: OnboardingManager, supportManager: SupportManager, testingScenariosManager: TestingScenariosManager?, settingsManager: SettingsManager, temporaryPresetsManager: TemporaryPresetsManager, loopDataManager: LoopDataManager, diagnosticReportGenerator: DiagnosticReportGenerator, simulatedData: SimulatedData, analyticsServicesManager: AnalyticsServicesManager, servicesManager: ServicesManager, carbStore: CarbStore, doseStore: DoseStore, criticalEventLogExportManager: CriticalEventLogExportManager, bluetoothStateManager: BluetoothStateManager, settingsViewModel: SettingsViewModel) {
        self.alertPermissionsChecker = alertPermissionsChecker
        self.alertMuter = alertMuter
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
