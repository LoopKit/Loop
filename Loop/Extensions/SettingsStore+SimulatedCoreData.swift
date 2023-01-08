//
//  SettingsStore+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/5/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

// MARK: - Simulated Core Data

extension SettingsStore {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedPerDay: Int { 2 }
    private var simulatedLimit: Int { 10000 }

    func generateSimulatedHistoricalSettingsObjects(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: expireDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [StoredSettings]()

        while startDate < endDate {
            for index in 0..<simulatedPerDay {
                simulated.append(StoredSettings.simulated(date: startDate.addingTimeInterval(.hours(24) * Double(index) / Double(simulatedPerDay))))
            }

            if simulated.count >= simulatedLimit {
                if let error = addSimulatedHistoricalSettingsObjects(settings: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        completion(addSimulatedHistoricalSettingsObjects(settings: simulated))
    }

    private func addSimulatedHistoricalSettingsObjects(settings: [StoredSettings]) -> Error? {
        var addError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        addStoredSettings(settings: settings) { error in
            addError = error
            semaphore.signal()
        }
        semaphore.wait()
        return addError
    }

    func purgeHistoricalSettingsObjects(completion: @escaping (Error?) -> Void) {
        purgeSettings(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension StoredSettings {
    static func simulated(date: Date) -> StoredSettings {
        let controllerTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        let scheduleTimeZone = TimeZone(secondsFromGMT: TimeZone(identifier: "America/Phoenix")!.secondsFromGMT())!
        let glucoseTargetRangeSchedule =  GlucoseRangeSchedule(rangeSchedule: DailyQuantitySchedule(unit: .milligramsPerDeciliter,
                                                                                                    dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                 RepeatingScheduleValue(startTime: .hours(8), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                 RepeatingScheduleValue(startTime: .hours(10), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                 RepeatingScheduleValue(startTime: .hours(12), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                 RepeatingScheduleValue(startTime: .hours(14), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                 RepeatingScheduleValue(startTime: .hours(16), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                 RepeatingScheduleValue(startTime: .hours(18), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                 RepeatingScheduleValue(startTime: .hours(21), value: DoubleRange(minValue: 110.0, maxValue: 120.0))],
                                                                                                    timeZone: scheduleTimeZone)!,
                                                               override: GlucoseRangeSchedule.Override(value: DoubleRange(minValue: 80.0, maxValue: 90.0),
                                                                                                       start: date.addingTimeInterval(-.minutes(30)),
                                                                                                       end: date.addingTimeInterval(.minutes(30))))
        let preMealOverride = TemporaryScheduleOverride(context: .preMeal,
                                                        settings: TemporaryScheduleOverrideSettings(unit: .milligramsPerDeciliter,
                                                                                                    targetRange: DoubleRange(minValue: 80.0, maxValue: 90.0),
                                                                                                    insulinNeedsScaleFactor: 0.5),
                                                        startDate: date.addingTimeInterval(-.minutes(30)),
                                                        duration: .finite(.minutes(60)),
                                                        enactTrigger: .local,
                                                        syncIdentifier: UUID())
        let basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: 1.0),
                                                               RepeatingScheduleValue(startTime: .hours(8), value: 1.125),
                                                               RepeatingScheduleValue(startTime: .hours(10), value: 1.25),
                                                               RepeatingScheduleValue(startTime: .hours(12), value: 1.5),
                                                               RepeatingScheduleValue(startTime: .hours(14), value: 1.25),
                                                               RepeatingScheduleValue(startTime: .hours(16), value: 1.5),
                                                               RepeatingScheduleValue(startTime: .hours(18), value: 1.25),
                                                               RepeatingScheduleValue(startTime: .hours(21), value: 1.0)],
                                                  timeZone: scheduleTimeZone)
        let insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: .milligramsPerDeciliter,
                                                                    dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: 45.0),
                                                                                 RepeatingScheduleValue(startTime: .hours(8), value: 40.0),
                                                                                 RepeatingScheduleValue(startTime: .hours(10), value: 35.0),
                                                                                 RepeatingScheduleValue(startTime: .hours(12), value: 30.0),
                                                                                 RepeatingScheduleValue(startTime: .hours(14), value: 35.0),
                                                                                 RepeatingScheduleValue(startTime: .hours(16), value: 40.0),
                                                                                 RepeatingScheduleValue(startTime: .hours(18), value: 45.0),
                                                                                 RepeatingScheduleValue(startTime: .hours(21), value: 50.0)],
                                                                    timeZone: scheduleTimeZone)
        let carbRatioSchedule = CarbRatioSchedule(unit: .gram(),
                                                  dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: 10.0),
                                                               RepeatingScheduleValue(startTime: .hours(8), value: 12.0),
                                                               RepeatingScheduleValue(startTime: .hours(10), value: 9.0),
                                                               RepeatingScheduleValue(startTime: .hours(12), value: 10.0),
                                                               RepeatingScheduleValue(startTime: .hours(14), value: 11.0),
                                                               RepeatingScheduleValue(startTime: .hours(16), value: 12.0),
                                                               RepeatingScheduleValue(startTime: .hours(18), value: 8.0),
                                                               RepeatingScheduleValue(startTime: .hours(21), value: 10.0)],
                                                  timeZone: scheduleTimeZone)
        let notificationSettings = NotificationSettings(authorizationStatus: .authorized,
                                                        soundSetting: .enabled,
                                                        badgeSetting: .enabled,
                                                        alertSetting: .enabled,
                                                        notificationCenterSetting: .enabled,
                                                        lockScreenSetting: .enabled,
                                                        carPlaySetting: .enabled,
                                                        alertStyle: .banner,
                                                        showPreviewsSetting: .always,
                                                        criticalAlertSetting: .enabled,
                                                        providesAppNotificationSettings: true,
                                                        announcementSetting: .enabled,
                                                        timeSensitiveSetting: .enabled,
                                                        scheduledDeliverySetting: .disabled,
                                                        temporaryMuteAlertsSetting: .disabled)
        let controllerDevice = StoredSettings.ControllerDevice(name: "Controller Name",
                                                               systemName: "Controller System Name",
                                                               systemVersion: "Controller System Version",
                                                               model: "Controller Model",
                                                               modelIdentifier: "Controller Model Identifier")
        let cgmDevice = HKDevice(name: "CGM Name",
                                 manufacturer: "CGM Manufacturer",
                                 model: "CGM Model",
                                 hardwareVersion: "CGM Hardware Version",
                                 firmwareVersion: "CGM Firmware Version",
                                 softwareVersion: "CGM Software Version",
                                 localIdentifier: "CGM Local Identifier",
                                 udiDeviceIdentifier: "CGM UDI Device Identifier")
        let pumpDevice = HKDevice(name: "Pump Name",
                                  manufacturer: "Pump Manufacturer",
                                  model: "Pump Model",
                                  hardwareVersion: "Pump Hardware Version",
                                  firmwareVersion: "Pump Firmware Version",
                                  softwareVersion: "Pump Software Version",
                                  localIdentifier: "Pump Local Identifier",
                                  udiDeviceIdentifier: "Pump UDI Device Identifier")
        return StoredSettings(date: date,
                              controllerTimeZone: controllerTimeZone,
                              dosingEnabled: true,
                              glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
                              preMealTargetRange: DoubleRange(minValue: 80.0, maxValue: 90.0).quantityRange(for: .milligramsPerDeciliter),
                              workoutTargetRange: DoubleRange(minValue: 150.0, maxValue: 160.0).quantityRange(for: .milligramsPerDeciliter),
                              overridePresets: nil,
                              scheduleOverride: nil,
                              preMealOverride: preMealOverride,
                              maximumBasalRatePerHour: 3.5,
                              maximumBolus: 10.0,
                              suspendThreshold: GlucoseThreshold(unit: .milligramsPerDeciliter, value: 75.0),
                              deviceToken: UUID().uuidString,
                              insulinType: .humalog,
                              defaultRapidActingModel: StoredInsulinModel(ExponentialInsulinModelPreset.rapidActingAdult),
                              basalRateSchedule: basalRateSchedule,
                              insulinSensitivitySchedule: insulinSensitivitySchedule,
                              carbRatioSchedule: carbRatioSchedule,
                              notificationSettings: notificationSettings,
                              controllerDevice: controllerDevice,
                              cgmDevice: cgmDevice,
                              pumpDevice: pumpDevice,
                              bloodGlucoseUnit: .milligramsPerDeciliter)
    }
}
