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

protocol DeviceStatusProvider {
    var pumpManagerStatus: PumpManagerStatus? { get }
    var cgmManagerStatus: CGMManagerStatus? { get }
}

class SettingsManager {

    let settingsStore: SettingsStore

    var remoteDataServicesManager: RemoteDataServicesManager?

    var deviceStatusProvider: DeviceStatusProvider?

    public var latestSettings: StoredSettings? {
        return settingsStore.latestSettings
    }

    // Push Notifications (do not persist)
    private var deviceToken: Data?

    private var cancellables: Set<AnyCancellable> = []

    init(cacheStore: PersistenceController, expireAfter: TimeInterval) {
        settingsStore = SettingsStore(store: cacheStore, expireAfter: expireAfter)
        settingsStore.delegate = self

        NotificationCenter.default
            .publisher(for: .LoopDataUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let context = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as! LoopDataManager.LoopUpdateContext.RawValue
                if case .preferences = LoopDataManager.LoopUpdateContext(rawValue: context) {
                    self?.storeSettings()
                }
            }
            .store(in: &cancellables)
    }

    func storeSettings(notificationSettings: NotificationSettings? = nil,
                       controllerDevice: StoredSettings.ControllerDevice? = nil,
                       cgmDevice: HKDevice? = nil,
                       pumpDevice: HKDevice? = nil)
    {
        guard let appGroup = UserDefaults.appGroup, let loopSettings = appGroup.loopSettings, let deviceToken = deviceToken else {
            return
        }

        let settings = StoredSettings(date: Date(),
                                      dosingEnabled: loopSettings.dosingEnabled,
                                      glucoseTargetRangeSchedule: loopSettings.glucoseTargetRangeSchedule,
                                      preMealTargetRange: loopSettings.preMealTargetRange,
                                      workoutTargetRange: loopSettings.legacyWorkoutTargetRange,
                                      overridePresets: loopSettings.overridePresets,
                                      scheduleOverride: loopSettings.scheduleOverride,
                                      preMealOverride: loopSettings.preMealOverride,
                                      maximumBasalRatePerHour: loopSettings.maximumBasalRatePerHour,
                                      maximumBolus: loopSettings.maximumBolus,
                                      suspendThreshold: loopSettings.suspendThreshold,
                                      deviceToken: deviceToken.hexadecimalString,
                                      insulinType: deviceStatusProvider?.pumpManagerStatus?.insulinType,
                                      defaultRapidActingModel: appGroup.defaultRapidActingModel.map(StoredInsulinModel.init),
                                      basalRateSchedule: appGroup.basalRateSchedule,
                                      insulinSensitivitySchedule: appGroup.insulinSensitivitySchedule,
                                      carbRatioSchedule: appGroup.carbRatioSchedule,
                                      notificationSettings: notificationSettings ?? settingsStore.latestSettings?.notificationSettings,
                                      controllerDevice: controllerDevice ?? UIDevice.current.controllerDevice,
                                      cgmDevice: cgmDevice ?? deviceStatusProvider?.cgmManagerStatus?.device,
                                      pumpDevice: pumpDevice ?? deviceStatusProvider?.pumpManagerStatus?.device,
                                      bloodGlucoseUnit: loopSettings.glucoseUnit)

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
            let controllerDevice = UIDevice.current.controllerDevice
            let cgmDevice = self.deviceStatusProvider?.cgmManagerStatus?.device
            let pumpDevice = self.deviceStatusProvider?.pumpManagerStatus?.device

            if notificationSettings != latestSettings.notificationSettings ||
                controllerDevice != latestSettings.controllerDevice ||
                cgmDevice != latestSettings.cgmDevice ||
                pumpDevice != latestSettings.pumpDevice
            {
                self.storeSettings(notificationSettings: notificationSettings,
                                   controllerDevice: controllerDevice,
                                   cgmDevice: cgmDevice,
                                   pumpDevice: pumpDevice)
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
