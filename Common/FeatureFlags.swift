//
//  FeatureFlags.swift
//  Loop
//
//  Created by Michael Pangburn on 5/19/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

let FeatureFlags = FeatureFlagConfiguration()

struct FeatureFlagConfiguration: Decodable {
    let cgmManagerCategorizeManualGlucoseRangeEnabled: Bool
    let criticalAlertsEnabled: Bool
    let entryDeletionEnabled: Bool
    let fiaspInsulinModelEnabled: Bool
    let includeServicesInSettingsEnabled: Bool
    let mockTherapySettingsEnabled: Bool
    let nonlinearCarbModelEnabled: Bool
    let observeHealthKitSamplesFromOtherApps: Bool
    let remoteOverridesEnabled: Bool
    let predictedGlucoseChartClampEnabled: Bool
    let scenariosEnabled: Bool
    let sensitivityOverridesEnabled: Bool
    let simulatedCoreDataEnabled: Bool
    let walshInsulinModelEnabled: Bool
    let siriEnabled: Bool

    fileprivate init() {
        #if CGM_MANAGER_CATEGORIZE_GLUCOSE_RANGE_ENABLED
        self.cgmManagerCategorizeManualGlucoseRangeEnabled = true
        #else
        self.cgmManagerCategorizeManualGlucoseRangeEnabled = false
        #endif
        
        #if CRITICAL_ALERTS_ENABLED
        self.criticalAlertsEnabled = true
        #else
        self.criticalAlertsEnabled = false
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if ENTRY_DELETION_DISABLED
        self.entryDeletionEnabled = false
        #else
        self.entryDeletionEnabled = true
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if FEATURE_OVERRIDES_DISABLED
        self.sensitivityOverridesEnabled = false
        #else
        self.sensitivityOverridesEnabled = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if FIASP_INSULIN_MODEL_DISABLED
        self.fiaspInsulinModelEnabled = false
        #else
        self.fiaspInsulinModelEnabled = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if INCLUDE_SERVICES_IN_SETTINGS_DISABLED
        self.includeServicesInSettingsEnabled = false
        #else
        self.includeServicesInSettingsEnabled = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if MOCK_THERAPY_SETTINGS_ENABLED
        self.mockTherapySettingsEnabled = true
        #else
        self.mockTherapySettingsEnabled = false
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if NONLINEAR_CARB_MODEL_DISABLED
        self.nonlinearCarbModelEnabled = false
        #else
        self.nonlinearCarbModelEnabled = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if OBSERVE_HEALTH_KIT_SAMPLES_FROM_OTHER_APPS_DISABLED
        self.observeHealthKitSamplesFromOtherApps = false
        #else
        self.observeHealthKitSamplesFromOtherApps = true
        #endif

        #if PREDICTED_GLUCOSE_CHART_CLAMP_ENABLED
        self.predictedGlucoseChartClampEnabled = true
        #else
        self.predictedGlucoseChartClampEnabled = false
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if REMOTE_OVERRIDES_DISABLED
        self.remoteOverridesEnabled = false
        #else
        self.remoteOverridesEnabled = true
        #endif
        
        #if SCENARIOS_ENABLED
        self.scenariosEnabled = true
        #else
        self.scenariosEnabled = false
        #endif

        #if SIMULATED_CORE_DATA_ENABLED
        self.simulatedCoreDataEnabled = true
        #else
        self.simulatedCoreDataEnabled = false
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if WALSH_INSULIN_MODEL_DISABLED
        self.walshInsulinModelEnabled = false
        #else
        self.walshInsulinModelEnabled = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if SIRI_DISABLED
        self.siriEnabled = false
        #else
        self.siriEnabled = true
        #endif
    }
}


extension FeatureFlagConfiguration : CustomDebugStringConvertible {
    var debugDescription: String {
        return [
            "* cgmManagerCategorizeManualGlucoseRangeEnabled: \(cgmManagerCategorizeManualGlucoseRangeEnabled)",
            "* criticalAlertsEnabled: \(criticalAlertsEnabled)",
            "* entryDeletionEnabled: \(entryDeletionEnabled)",
            "* fiaspInsulinModelEnabled: \(fiaspInsulinModelEnabled)",
            "* includeServicesInSettingsEnabled: \(includeServicesInSettingsEnabled)",
            "* mockTherapySettingsEnabled: \(mockTherapySettingsEnabled)",
            "* nonlinearCarbModelEnabled: \(nonlinearCarbModelEnabled)",
            "* observeHealthKitSamplesFromOtherApps: \(observeHealthKitSamplesFromOtherApps)",
            "* predictedGlucoseChartClampEnabled: \(predictedGlucoseChartClampEnabled)",
            "* remoteOverridesEnabled: \(remoteOverridesEnabled)",
            "* scenariosEnabled: \(scenariosEnabled)",
            "* sensitivityOverridesEnabled: \(sensitivityOverridesEnabled)",
            "* simulatedCoreDataEnabled: \(simulatedCoreDataEnabled)",
            "* walshInsulinModelEnabled: \(walshInsulinModelEnabled)",
            "* siriEnabled: \(siriEnabled)",
        ].joined(separator: "\n")
    }
}
