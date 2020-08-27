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
    let sensitivityOverridesEnabled: Bool
    let nonlinearCarbModelEnabled: Bool
    let remoteOverridesEnabled: Bool
    let criticalAlertsEnabled: Bool
    let scenariosEnabled: Bool
    let simulatedCoreDataEnabled: Bool
    let walshInsulinModelEnabled: Bool
    let fiaspInsulinModelEnabled: Bool
    let observeHealthKitSamplesFromOtherApps: Bool
    let includeServicesInSettingsEnabled: Bool
    let mockTherapySettingsEnabled: Bool
    let deleteAllButtonEnabled: Bool

    fileprivate init() {
        // Swift compiler config is inverse, since the default state is enabled.
        #if FEATURE_OVERRIDES_DISABLED
        self.sensitivityOverridesEnabled = false
        #else
        self.sensitivityOverridesEnabled = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if NONLINEAR_CARB_MODEL_DISABLED
        self.nonlinearCarbModelEnabled = false
        #else
        self.nonlinearCarbModelEnabled = true
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if REMOTE_OVERRIDES_DISABLED
        self.remoteOverridesEnabled = false
        #else
        self.remoteOverridesEnabled = true
        #endif
        
        #if CRITICAL_ALERTS_ENABLED
        self.criticalAlertsEnabled = true
        #else
        self.criticalAlertsEnabled = false
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
        #if FIASP_INSULIN_MODEL_DISABLED
        self.fiaspInsulinModelEnabled = false
        #else
        self.fiaspInsulinModelEnabled = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if OBSERVE_HEALTH_KIT_SAMPLES_FROM_OTHER_APPS_DISABLED
        self.observeHealthKitSamplesFromOtherApps = false
        #else
        self.observeHealthKitSamplesFromOtherApps = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if INCLUDE_SERVICES_IN_SETTINGS_DISABLED
        self.includeServicesInSettingsEnabled = false
        #else
        self.includeServicesInSettingsEnabled = true
        #endif

        #if MOCK_THERAPY_SETTINGS_ENABLED
        self.mockTherapySettingsEnabled = true
        #else
        self.mockTherapySettingsEnabled = false
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if DELETE_ALL_BUTTON_DISABLED
        self.deleteAllButtonEnabled = false
        #else
        self.deleteAllButtonEnabled = true
        #endif
    }
}


extension FeatureFlagConfiguration : CustomDebugStringConvertible {
    var debugDescription: String {
        return [
            "* sensitivityOverridesEnabled: \(sensitivityOverridesEnabled)",
            "* nonlinearCarbModelEnabled: \(nonlinearCarbModelEnabled)",
            "* remoteOverridesEnabled: \(remoteOverridesEnabled)",
            "* criticalAlertsEnabled: \(criticalAlertsEnabled)",
            "* scenariosEnabled: \(scenariosEnabled)",
            "* simulatedCoreDataEnabled: \(simulatedCoreDataEnabled)",
            "* walshInsulinModelEnabled: \(walshInsulinModelEnabled)",
            "* fiaspInsulinModelEnabled: \(fiaspInsulinModelEnabled)",
            "* observeHealthKitSamplesFromOtherApps: \(observeHealthKitSamplesFromOtherApps)",
            "* includeServicesInSettingsEnabled: \(includeServicesInSettingsEnabled)",
            "* mockTherapySettingsEnabled: \(mockTherapySettingsEnabled)",
            "* deleteAllButtonEnabled: \(deleteAllButtonEnabled)"
        ].joined(separator: "\n")
    }
}
