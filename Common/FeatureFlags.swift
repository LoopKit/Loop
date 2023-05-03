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
    let automaticBolusEnabled: Bool
    let cgmManagerCategorizeManualGlucoseRangeEnabled: Bool
    let criticalAlertsEnabled: Bool
    let entryDeletionEnabled: Bool
    let fiaspInsulinModelEnabled: Bool
    let lyumjevInsulinModelEnabled: Bool
    let afrezzaInsulinModelEnabled: Bool
    let includeServicesInSettingsEnabled: Bool
    let manualDoseEntryEnabled: Bool
    let insulinDeliveryReservoirViewEnabled: Bool
    let mockTherapySettingsEnabled: Bool
    let nonlinearCarbModelEnabled: Bool
    let observeHealthKitCarbSamplesFromOtherApps: Bool
    let observeHealthKitDoseSamplesFromOtherApps: Bool
    let observeHealthKitGlucoseSamplesFromOtherApps: Bool
    let remoteCommandsEnabled: Bool
    let predictedGlucoseChartClampEnabled: Bool
    let scenariosEnabled: Bool
    let sensitivityOverridesEnabled: Bool
    let showEventualBloodGlucoseOnWatchEnabled: Bool
    let simulatedCoreDataEnabled: Bool
    let siriEnabled: Bool
    let simpleBolusCalculatorEnabled: Bool
    let usePositiveMomentumAndRCForManualBoluses: Bool
    let dynamicCarbAbsorptionEnabled: Bool
    let adultChildInsulinModelSelectionEnabled: Bool
    let profileExpirationSettingsViewEnabled: Bool
    let missedMealNotifications: Bool


    fileprivate init() {
        // Swift compiler config is inverse, since the default state is enabled.
        #if AUTOMATIC_BOLUS_DISABLED
        self.automaticBolusEnabled = false
        #else
        self.automaticBolusEnabled = true
        #endif

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
        #if LYUMJEV_INSULIN_MODEL_DISABLED
        self.lyumjevInsulinModelEnabled = false
        #else
        self.lyumjevInsulinModelEnabled = true
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if AFREZZA_INSULIN_MODEL_DISABLED
        self.afrezzaInsulinModelEnabled = false
        #else
        self.afrezzaInsulinModelEnabled = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if INCLUDE_SERVICES_IN_SETTINGS_DISABLED
        self.includeServicesInSettingsEnabled = false
        #else
        self.includeServicesInSettingsEnabled = true
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if MANUAL_DOSE_ENTRY_DISABLED
        self.manualDoseEntryEnabled = false
        #else
        self.manualDoseEntryEnabled = true
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if INSULIN_DELIVERY_RESERVOIR_VIEW_DISABLED
        self.insulinDeliveryReservoirViewEnabled = false
        #else
        self.insulinDeliveryReservoirViewEnabled = true
        #endif

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
        
        #if OBSERVE_HEALTH_KIT_CARB_SAMPLES_FROM_OTHER_APPS_ENABLED
        self.observeHealthKitCarbSamplesFromOtherApps = true
        #else
        self.observeHealthKitCarbSamplesFromOtherApps = false
        #endif
        
        // Swift compiler config is inverse, since the default state is enabled.
        #if OBSERVE_HEALTH_KIT_SAMPLES_FROM_OTHER_APPS_DISABLED
        self.observeHealthKitDoseSamplesFromOtherApps = false
        self.observeHealthKitGlucoseSamplesFromOtherApps = false
        #else
        self.observeHealthKitDoseSamplesFromOtherApps = true
        self.observeHealthKitGlucoseSamplesFromOtherApps = true
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if OBSERVE_HEALTH_KIT_DOSE_SAMPLES_FROM_OTHER_APPS_DISABLED
        self.observeHealthKitDoseSamplesFromOtherApps = false
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if OBSERVE_HEALTH_KIT_GLUCOSE_SAMPLES_FROM_OTHER_APPS_DISABLED
        self.observeHealthKitGlucoseSamplesFromOtherApps = false
        #endif
        
        #if PREDICTED_GLUCOSE_CHART_CLAMP_ENABLED
        self.predictedGlucoseChartClampEnabled = true
        #else
        self.predictedGlucoseChartClampEnabled = false
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if REMOTE_COMMANDS_DISABLED || REMOTE_OVERRIDES_DISABLED //REMOTE_OVERRIDES_DISABLED: backwards compatibility of Loop 3 & prior
        self.remoteCommandsEnabled = false
        #else
        self.remoteCommandsEnabled = true
        #endif
        
        #if SCENARIOS_ENABLED
        self.scenariosEnabled = true
        #else
        self.scenariosEnabled = false
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if SHOW_EVENTUAL_BLOOD_GLUCOSE_ON_WATCH_DISABLED
        self.showEventualBloodGlucoseOnWatchEnabled = false
        #else
        self.showEventualBloodGlucoseOnWatchEnabled = true
        #endif
        
        #if SIMULATED_CORE_DATA_ENABLED
        self.simulatedCoreDataEnabled = true
        #else
        self.simulatedCoreDataEnabled = false
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if SIRI_DISABLED
        self.siriEnabled = false
        #else
        self.siriEnabled = true
        #endif
        
        #if SIMPLE_BOLUS_CALCULATOR_ENABLED
        self.simpleBolusCalculatorEnabled = true
        #else
        self.simpleBolusCalculatorEnabled = false
        #endif

        // Swift compiler config is inverse, since the default state is enabled.
        #if DISABLE_POSITIVE_MOMENTUM_AND_RC_FOR_MANUAL_BOLUSES
        self.usePositiveMomentumAndRCForManualBoluses = false
        #else
        self.usePositiveMomentumAndRCForManualBoluses = true
        #endif

        #if ADULT_CHILD_INSULIN_MODEL_SELECTION_ENABLED
        self.adultChildInsulinModelSelectionEnabled = true
        #else
        self.adultChildInsulinModelSelectionEnabled = false
        #endif

        self.dynamicCarbAbsorptionEnabled = true

        // ProfileExpirationSettingsView is inverse, since the default state is enabled.
        #if PROFILE_EXPIRATION_SETTINGS_VIEW_DISABLED
        self.profileExpirationSettingsViewEnabled = false
        #else
        self.profileExpirationSettingsViewEnabled = true
        #endif

        // Missed meal notifications compiler flag is inverse, since the default state is enabled.
        #if MISSED_MEAL_NOTIFICATIONS_DISABLED
        self.missedMealNotifications = false
        #else
        self.missedMealNotifications = true
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
            "* lyumjevInsulinModelEnabled: \(lyumjevInsulinModelEnabled)",
            "* afrezzaInsulinModelEnabled: \(afrezzaInsulinModelEnabled)",
            "* includeServicesInSettingsEnabled: \(includeServicesInSettingsEnabled)",
            "* mockTherapySettingsEnabled: \(mockTherapySettingsEnabled)",
            "* nonlinearCarbModelEnabled: \(nonlinearCarbModelEnabled)",
            "* observeHealthKitCarbSamplesFromOtherApps: \(observeHealthKitCarbSamplesFromOtherApps)",
            "* observeHealthKitDoseSamplesFromOtherApps: \(observeHealthKitDoseSamplesFromOtherApps)",
            "* observeHealthKitGlucoseSamplesFromOtherApps: \(observeHealthKitGlucoseSamplesFromOtherApps)",
            "* predictedGlucoseChartClampEnabled: \(predictedGlucoseChartClampEnabled)",
            "* remoteCommandsEnabled: \(remoteCommandsEnabled)",
            "* scenariosEnabled: \(scenariosEnabled)",
            "* sensitivityOverridesEnabled: \(sensitivityOverridesEnabled)",
            "* showEventualBloodGlucoseOnWatchEnabled: \(showEventualBloodGlucoseOnWatchEnabled)",
            "* simulatedCoreDataEnabled: \(simulatedCoreDataEnabled)",
            "* siriEnabled: \(siriEnabled)",
            "* automaticBolusEnabled: \(automaticBolusEnabled)",
            "* manualDoseEntryEnabled: \(manualDoseEntryEnabled)",
            "* allowDebugFeatures: \(allowDebugFeatures)",
            "* simpleBolusCalculatorEnabled: \(simpleBolusCalculatorEnabled)",
            "* usePositiveMomentumAndRCForManualBoluses: \(usePositiveMomentumAndRCForManualBoluses)",
            "* dynamicCarbAbsorptionEnabled: \(dynamicCarbAbsorptionEnabled)",
            "* adultChildInsulinModelSelectionEnabled: \(adultChildInsulinModelSelectionEnabled)",
            "* profileExpirationSettingsViewEnabled: \(profileExpirationSettingsViewEnabled)",
            "* missedMealNotifications: \(missedMealNotifications)"
        ].joined(separator: "\n")
    }
}

extension FeatureFlagConfiguration {
    var allowDebugFeatures: Bool {
        #if DEBUG_FEATURES_ENABLED
        return true
        #elseif DEBUG_FEATURES_ENABLED_CONDITIONALLY
        if debugEnabled {
            return true
        } else {
            if UserDefaults.appGroup?.allowDebugFeatures ?? false {
                return true
            } else {
                return false
            }
        }
        #else
        return false
        #endif
    }
    
    var allowSimulators: Bool {
        #if SIMULATORS_ENABLED
        return true
        #elseif SIMULATORS_ENABLED_CONDITIONALLY
        if debugEnabled {
            return true
        } else {
            if UserDefaults.appGroup?.allowSimulators ?? false {
                return true
            } else {
                return false
            }
        }
        #else
        return false
        #endif
    }
}
