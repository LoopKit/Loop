//
//  SettingsManager.swift
//  Loop
//
//  Created by Pete Schwamb on 2/27/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import UserNotifications
import UIKit
import HealthKit
import Combine
import LoopCore
import LoopKitUI

protocol DeviceStatusProvider {
    var pumpManagerStatus: PumpManagerStatus? { get }
    var cgmManagerStatus: CGMManagerStatus? { get }
}

class SettingsManager {

    let settingsStore: SettingsStore

    var remoteDataServicesManager: RemoteDataServicesManager?

    var deviceStatusProvider: DeviceStatusProvider?

    var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable?

    public var latestSettings: StoredSettings? {
        return settingsStore.latestSettings
    }

    // Push Notifications (do not persist)
    private var deviceToken: Data?

    private var cancellables: Set<AnyCancellable> = []


    init(cacheStore: PersistenceController, expireAfter: TimeInterval)
    {
        settingsStore = SettingsStore(store: cacheStore, expireAfter: expireAfter)
        settingsStore.delegate = self

        NotificationCenter.default
            .publisher(for: .LoopDataUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let context = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopDataManager.LoopUpdateContext.RawValue
                if case .preferences = LoopDataManager.LoopUpdateContext(rawValue: context), let loopDataManager = note.object as? LoopDataManager {
                    self?.storeSettings(newLoopSettings: loopDataManager.settings)
                }
            }
            .store(in: &cancellables)

        // Migrate old settings from UserDefaults
        if var legacyLoopSettings = UserDefaults.appGroup?.legacyLoopSettings {
            legacyLoopSettings.insulinSensitivitySchedule = UserDefaults.appGroup?.legacyInsulinSensitivitySchedule
            legacyLoopSettings.basalRateSchedule = UserDefaults.appGroup?.legacyBasalRateSchedule
            legacyLoopSettings.carbRatioSchedule = UserDefaults.appGroup?.legacyCarbRatioSchedule
            legacyLoopSettings.defaultRapidActingModel = UserDefaults.appGroup?.legacyDefaultRapidActingModel

            storeSettings(newLoopSettings: legacyLoopSettings)

            UserDefaults.appGroup?.removeLegacyLoopSettings()
        }
    }

    var loopSettings: LoopSettings {
        get {
            guard let storedSettings = latestSettings else {
                return LoopSettings()
            }

            return LoopSettings(
                dosingEnabled: storedSettings.dosingEnabled,
                glucoseTargetRangeSchedule: storedSettings.glucoseTargetRangeSchedule,
                insulinSensitivitySchedule: storedSettings.insulinSensitivitySchedule,
                basalRateSchedule: storedSettings.basalRateSchedule,
                carbRatioSchedule: storedSettings.carbRatioSchedule,
                preMealTargetRange: storedSettings.preMealTargetRange,
                legacyWorkoutTargetRange: storedSettings.workoutTargetRange,
                overridePresets: storedSettings.overridePresets,
                scheduleOverride: storedSettings.scheduleOverride,
                preMealOverride: storedSettings.preMealOverride,
                maximumBasalRatePerHour: storedSettings.maximumBasalRatePerHour,
                maximumBolus: storedSettings.maximumBolus,
                suspendThreshold: storedSettings.suspendThreshold,
                automaticDosingStrategy: storedSettings.automaticDosingStrategy,
                defaultRapidActingModel: storedSettings.defaultRapidActingModel?.presetForRapidActingInsulin)
        }
    }

    func storeSettings(newLoopSettings: LoopSettings? = nil, notificationSettings: NotificationSettings? = nil)
    {

#if targetEnvironment(simulator)
        let deviceToken = "mockDeviceTokenFromSimulator"
#else
        guard let deviceToken = deviceToken?.hexadecimalString else {
            return
        }
#endif

        let newLoopSettings = newLoopSettings ?? loopSettings
        let newNotificationSettings = notificationSettings ?? settingsStore.latestSettings?.notificationSettings

        let settings = StoredSettings(date: Date(),
                                      dosingEnabled: newLoopSettings.dosingEnabled,
                                      glucoseTargetRangeSchedule: newLoopSettings.glucoseTargetRangeSchedule,
                                      preMealTargetRange: newLoopSettings.preMealTargetRange,
                                      workoutTargetRange: newLoopSettings.legacyWorkoutTargetRange,
                                      overridePresets: newLoopSettings.overridePresets,
                                      scheduleOverride: newLoopSettings.scheduleOverride,
                                      preMealOverride: newLoopSettings.preMealOverride,
                                      maximumBasalRatePerHour: newLoopSettings.maximumBasalRatePerHour,
                                      maximumBolus: newLoopSettings.maximumBolus,
                                      suspendThreshold: newLoopSettings.suspendThreshold,
                                      deviceToken: deviceToken,
                                      insulinType: deviceStatusProvider?.pumpManagerStatus?.insulinType,
                                      defaultRapidActingModel: newLoopSettings.defaultRapidActingModel.map(StoredInsulinModel.init),
                                      basalRateSchedule: newLoopSettings.basalRateSchedule,
                                      insulinSensitivitySchedule: newLoopSettings.insulinSensitivitySchedule,
                                      carbRatioSchedule: newLoopSettings.carbRatioSchedule,
                                      notificationSettings: newNotificationSettings,
                                      controllerDevice: UIDevice.current.controllerDevice,
                                      cgmDevice: deviceStatusProvider?.cgmManagerStatus?.device,
                                      pumpDevice: deviceStatusProvider?.pumpManagerStatus?.device,
                                      bloodGlucoseUnit: displayGlucoseUnitObservable?.displayGlucoseUnit)

        if let latestSettings = latestSettings, latestSettings == settings {
            // Skipping unchanged settings store
            return
        }

        settingsStore.storeSettings(settings) {}
    }

    func storeSettingsCheckingNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings() { notificationSettings in
            guard let latestSettings = self.settingsStore.latestSettings else {
                return
            }

            let notificationSettings = NotificationSettings(notificationSettings)

            if notificationSettings != latestSettings.notificationSettings
            {
                self.storeSettings(notificationSettings: notificationSettings)
            }
        }
    }

    func didBecomeActive () {
        storeSettingsCheckingNotificationPermissions()
    }

    func hasNewDeviceToken(token: Data) {
        self.deviceToken = token
        storeSettings()
    }

    func purgeHistoricalSettingsObjects(completion: @escaping (Error?) -> Void) {
        settingsStore.purgeHistoricalSettingsObjects(completion: completion)
    }
}

// MARK: - SettingsStoreDelegate
extension SettingsManager: SettingsStoreDelegate {
    func settingsStoreHasUpdatedSettingsData(_ settingsStore: SettingsStore) {
        remoteDataServicesManager?.settingsStoreHasUpdatedSettingsData(settingsStore)
    }
}

private extension NotificationSettings {
    init(_ notificationSettings: UNNotificationSettings) {
        self.init(authorizationStatus: NotificationSettings.AuthorizationStatus(notificationSettings.authorizationStatus),
                  soundSetting: NotificationSettings.NotificationSetting(notificationSettings.soundSetting),
                  badgeSetting: NotificationSettings.NotificationSetting(notificationSettings.badgeSetting),
                  alertSetting: NotificationSettings.NotificationSetting(notificationSettings.alertSetting),
                  notificationCenterSetting: NotificationSettings.NotificationSetting(notificationSettings.notificationCenterSetting),
                  lockScreenSetting: NotificationSettings.NotificationSetting(notificationSettings.lockScreenSetting),
                  carPlaySetting: NotificationSettings.NotificationSetting(notificationSettings.carPlaySetting),
                  alertStyle: NotificationSettings.AlertStyle(notificationSettings.alertStyle),
                  showPreviewsSetting: NotificationSettings.ShowPreviewsSetting(notificationSettings.showPreviewsSetting),
                  criticalAlertSetting: NotificationSettings.NotificationSetting(notificationSettings.criticalAlertSetting),
                  providesAppNotificationSettings: notificationSettings.providesAppNotificationSettings,
                  announcementSetting: NotificationSettings.NotificationSetting(notificationSettings.announcementSetting))
    }
}
