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
import Combine
import LoopCore
import LoopKitUI
import os.log
import LoopAlgorithm


protocol DeviceStatusProvider {
    var pumpManagerStatus: PumpManagerStatus? { get }
    var cgmManagerStatus: CGMManagerStatus? { get }
}

@MainActor
class SettingsManager {

    let settingsStore: SettingsStore

    var remoteDataServicesManager: RemoteDataServicesManager?

    var analyticsServicesManager: AnalyticsServicesManager?

    var deviceStatusProvider: DeviceStatusProvider?

    var alertMuter: AlertMuter

    var displayGlucosePreference: DisplayGlucosePreference?

    public var settings: StoredSettings

    private var remoteNotificationRegistrationResult: Swift.Result<Data,Error>?

    private var cancellables: Set<AnyCancellable> = []

    private let log = OSLog(category: "SettingsManager")

    private var loopSettingsLock = UnfairLock()

    @Published private(set) var dosingEnabled: Bool

    init(cacheStore: PersistenceController, expireAfter: TimeInterval, alertMuter: AlertMuter, analyticsServicesManager: AnalyticsServicesManager? = nil)
    {
        self.analyticsServicesManager = analyticsServicesManager

        settingsStore = SettingsStore(store: cacheStore, expireAfter: expireAfter)
        self.alertMuter = alertMuter

        if let storedSettings = settingsStore.latestSettings {
            settings = storedSettings
        } else {
            log.default("SettingsStore has no settings: initializing empty StoredSettings.")
            settings = StoredSettings()
        }

        dosingEnabled = settings.dosingEnabled

        settingsStore.delegate = self

        // Migrate old settings from UserDefaults
        if var legacyLoopSettings = UserDefaults.appGroup?.legacyLoopSettings {
            log.default("Migrating settings from UserDefaults")
            legacyLoopSettings.insulinSensitivitySchedule = UserDefaults.appGroup?.legacyInsulinSensitivitySchedule
            legacyLoopSettings.basalRateSchedule = UserDefaults.appGroup?.legacyBasalRateSchedule
            legacyLoopSettings.carbRatioSchedule = UserDefaults.appGroup?.legacyCarbRatioSchedule
            legacyLoopSettings.defaultRapidActingModel = .rapidActingAdult

            storeSettings(newLoopSettings: legacyLoopSettings)

            UserDefaults.appGroup?.removeLegacyLoopSettings()
        }

        self.alertMuter.$configuration
            .sink { [weak self] alertMuterConfiguration in
                guard var notificationSettings = self?.settings.notificationSettings else { return }
                let newTemporaryMuteAlertsSetting = NotificationSettings.TemporaryMuteAlertSetting(enabled: alertMuterConfiguration.shouldMute, duration: alertMuterConfiguration.duration)
                if notificationSettings.temporaryMuteAlertsSetting != newTemporaryMuteAlertsSetting {
                    notificationSettings.temporaryMuteAlertsSetting = newTemporaryMuteAlertsSetting
                    self?.storeSettings(notificationSettings: notificationSettings)
                }
            }
            .store(in: &cancellables)
    }

    var loopSettings: LoopSettings {
        get {
            return LoopSettings(
                dosingEnabled: settings.dosingEnabled,
                glucoseTargetRangeSchedule: settings.glucoseTargetRangeSchedule,
                insulinSensitivitySchedule: settings.insulinSensitivitySchedule,
                basalRateSchedule: settings.basalRateSchedule,
                carbRatioSchedule: settings.carbRatioSchedule,
                preMealTargetRange: settings.preMealTargetRange,
                legacyWorkoutTargetRange: settings.workoutTargetRange,
                overridePresets: settings.overridePresets,
                maximumBasalRatePerHour: settings.maximumBasalRatePerHour,
                maximumBolus: settings.maximumBolus,
                suspendThreshold: settings.suspendThreshold,
                automaticDosingStrategy: settings.automaticDosingStrategy,
                defaultRapidActingModel: settings.defaultRapidActingModel?.presetForRapidActingInsulin)
        }
    }

    private func mergeSettings(newLoopSettings: LoopSettings? = nil, notificationSettings: NotificationSettings? = nil, deviceToken: String? = nil) -> StoredSettings
    {
        let newLoopSettings = newLoopSettings ?? loopSettings
        let newNotificationSettings = notificationSettings ?? settingsStore.latestSettings?.notificationSettings

        return StoredSettings(date: Date(),
                              dosingEnabled: newLoopSettings.dosingEnabled,
                              glucoseTargetRangeSchedule: newLoopSettings.glucoseTargetRangeSchedule,
                              preMealTargetRange: newLoopSettings.preMealTargetRange,
                              workoutTargetRange: newLoopSettings.legacyWorkoutTargetRange,
                              overridePresets: newLoopSettings.overridePresets,
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
                              bloodGlucoseUnit: displayGlucosePreference?.unit,
                              automaticDosingStrategy: newLoopSettings.automaticDosingStrategy)
    }

    func storeSettings(newLoopSettings: LoopSettings? = nil, notificationSettings: NotificationSettings? = nil) {

        var deviceTokenStr: String?

        if case .success(let deviceToken) = remoteNotificationRegistrationResult {
            deviceTokenStr = deviceToken.hexadecimalString
        }

        let mergedSettings = mergeSettings(newLoopSettings: newLoopSettings, notificationSettings: notificationSettings, deviceToken: deviceTokenStr)

        guard settings != mergedSettings else {
            // Skipping unchanged settings store
            return
        }

        settings = mergedSettings

        if remoteNotificationRegistrationResult == nil && FeatureFlags.remoteCommandsEnabled {
            // remote notification registration not finished
            return
        }

        if settings.insulinSensitivitySchedule == nil {
            log.default("Saving settings with no ISF schedule.")
        }

        settingsStore.storeSettings(settings) { error in
            if let error = error {
                self.log.error("Error storing settings: %{public}@", error.localizedDescription)
            }
        }
    }

    /// Sets a new time zone for a the schedule-based settings
    ///
    /// - Parameter timeZone: The time zone
    func setScheduleTimeZone(_ timeZone: TimeZone) {
        let shouldUpdate = settings.basalRateSchedule?.timeZone != timeZone ||
        settings.carbRatioSchedule?.timeZone != timeZone ||
        settings.insulinSensitivitySchedule?.timeZone != timeZone ||
        settings.glucoseTargetRangeSchedule?.timeZone != timeZone
        guard shouldUpdate else { return }

        self.mutateLoopSettings { settings in
            settings.basalRateSchedule?.timeZone = timeZone
            settings.carbRatioSchedule?.timeZone = timeZone
            settings.insulinSensitivitySchedule?.timeZone = timeZone
            settings.glucoseTargetRangeSchedule?.timeZone = timeZone
        }
    }

    private func notify(forChange context: LoopUpdateContext) {
        NotificationCenter.default.post(name: .LoopDataUpdated,
            object: self,
            userInfo: [
                LoopDataManager.LoopUpdateContextKey: context.rawValue
            ]
        )
    }

    func mutateLoopSettings(_ changes: (_ settings: inout LoopSettings) -> Void) {
        loopSettingsLock.withLock {
            let oldValue = loopSettings
            var newValue = oldValue
            changes(&newValue)

            guard oldValue != newValue else {
                return
            }

            storeSettings(newLoopSettings: newValue)

            if newValue.insulinSensitivitySchedule != oldValue.insulinSensitivitySchedule {
                analyticsServicesManager?.didChangeInsulinSensitivitySchedule()
            }

            if newValue.basalRateSchedule != oldValue.basalRateSchedule {
                if let newValue = newValue.basalRateSchedule, let oldValue = oldValue.basalRateSchedule, newValue.items != oldValue.items {
                    analyticsServicesManager?.didChangeBasalRateSchedule()
                }
            }

            if newValue.carbRatioSchedule != oldValue.carbRatioSchedule {
                analyticsServicesManager?.didChangeCarbRatioSchedule()
            }

            if newValue.defaultRapidActingModel != oldValue.defaultRapidActingModel {
                analyticsServicesManager?.didChangeInsulinModel()
            }

            if newValue.dosingEnabled != oldValue.dosingEnabled {
                self.dosingEnabled = newValue.dosingEnabled
            }
        }
        notify(forChange: .preferences)
    }

    func storeSettingsCheckingNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings() { notificationSettings in
            DispatchQueue.main.async {
                guard let settings = self.settingsStore.latestSettings else {
                    return
                }

                let temporaryMuteAlertSetting = NotificationSettings.TemporaryMuteAlertSetting(enabled: self.alertMuter.configuration.shouldMute, duration: self.alertMuter.configuration.duration)
                let notificationSettings = NotificationSettings(notificationSettings, temporaryMuteAlertsSetting: temporaryMuteAlertSetting)

                if notificationSettings != settings.notificationSettings
                {
                    self.storeSettings(notificationSettings: notificationSettings)
                }
            }
        }
    }

    func didBecomeActive () {
        storeSettingsCheckingNotificationPermissions()
    }

    func remoteNotificationRegistrationDidFinish(_ result: Swift.Result<Data,Error>) {
        self.remoteNotificationRegistrationResult = result
        storeSettings()
    }

    func purgeHistoricalSettingsObjects(completion: @escaping (Error?) -> Void) {
        settingsStore.purgeHistoricalSettingsObjects(completion: completion)
    }

    // MARK: Historical queries

    func getBasalHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        try await settingsStore.getBasalHistory(startDate: startDate, endDate: endDate)
    }

    func getCarbRatioHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        try await settingsStore.getCarbRatioHistory(startDate: startDate, endDate: endDate)
    }

    func getInsulinSensitivityHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<LoopQuantity>] {
        try await settingsStore.getInsulinSensitivityHistory(startDate: startDate, endDate: endDate)
    }

    func getTargetRangeHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>] {
        try await settingsStore.getTargetRangeHistory(startDate: startDate, endDate: endDate)
    }

    func getDosingLimits(at date: Date) async throws -> DosingLimits {
        try await settingsStore.getDosingLimits(at: date)
    }

}

extension SettingsManager {
    public var therapySettings: TherapySettings {
        get {
            let settings = self.settings
            return TherapySettings(glucoseTargetRangeSchedule: settings.glucoseTargetRangeSchedule,
                            correctionRangeOverrides: CorrectionRangeOverrides(preMeal: settings.preMealTargetRange, workout: settings.workoutTargetRange),
                            overridePresets: settings.overridePresets,
                            maximumBasalRatePerHour: settings.maximumBasalRatePerHour,
                            maximumBolus: settings.maximumBolus,
                            suspendThreshold: settings.suspendThreshold,
                            insulinSensitivitySchedule: settings.insulinSensitivitySchedule,
                            carbRatioSchedule: settings.carbRatioSchedule,
                            basalRateSchedule: settings.basalRateSchedule,
                            defaultRapidActingModel: settings.defaultRapidActingModel?.presetForRapidActingInsulin)
        }

        set {
            mutateLoopSettings { settings in
                settings.defaultRapidActingModel = newValue.defaultRapidActingModel
                settings.insulinSensitivitySchedule = newValue.insulinSensitivitySchedule
                settings.carbRatioSchedule = newValue.carbRatioSchedule
                settings.basalRateSchedule = newValue.basalRateSchedule
                settings.glucoseTargetRangeSchedule = newValue.glucoseTargetRangeSchedule
                settings.preMealTargetRange = newValue.correctionRangeOverrides?.preMeal
                settings.legacyWorkoutTargetRange = newValue.correctionRangeOverrides?.workout
                settings.suspendThreshold = newValue.suspendThreshold
                settings.maximumBolus = newValue.maximumBolus
                settings.maximumBasalRatePerHour = newValue.maximumBasalRatePerHour
                settings.overridePresets = newValue.overridePresets ?? []
            }
        }
    }
}

protocol SettingsProvider {
    var settings: StoredSettings { get }

    func getBasalHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>]
    func getCarbRatioHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>]
    func getInsulinSensitivityHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<LoopQuantity>]
    func getTargetRangeHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>]
    func getDosingLimits(at date: Date) async throws -> DosingLimits
    func executeSettingsQuery(fromQueryAnchor queryAnchor: SettingsStore.QueryAnchor?, limit: Int, completion: @escaping (SettingsStore.SettingsQueryResult) -> Void)
}

extension SettingsManager: SettingsProvider {
    func executeSettingsQuery(fromQueryAnchor queryAnchor: SettingsStore.QueryAnchor?, limit: Int, completion: @escaping (SettingsStore.SettingsQueryResult) -> Void) {
        settingsStore.executeSettingsQuery(fromQueryAnchor: queryAnchor, limit: limit, completion: completion)
    }
}

// MARK: - SettingsStoreDelegate
extension SettingsManager: SettingsStoreDelegate {
    func settingsStoreHasUpdatedSettingsData(_ settingsStore: SettingsStore) {
        remoteDataServicesManager?.triggerUpload(for: .settings)
    }
}

private extension NotificationSettings {

    init(_ notificationSettings: UNNotificationSettings, temporaryMuteAlertsSetting: TemporaryMuteAlertSetting) {
        let timeSensitiveSetting: NotificationSettings.NotificationSetting
        let scheduledDeliverySetting: NotificationSettings.NotificationSetting

        if #available(iOS 15.0, *) {
            timeSensitiveSetting = NotificationSettings.NotificationSetting(notificationSettings.timeSensitiveSetting)
            scheduledDeliverySetting = NotificationSettings.NotificationSetting(notificationSettings.scheduledDeliverySetting)
        } else {
            timeSensitiveSetting = .unknown
            scheduledDeliverySetting = .unknown
        }

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
                  announcementSetting: NotificationSettings.NotificationSetting(notificationSettings.announcementSetting),
                  timeSensitiveSetting: timeSensitiveSetting,
                  scheduledDeliverySetting: scheduledDeliverySetting,
                  temporaryMuteAlertsSetting: temporaryMuteAlertsSetting
        )
    }
}


