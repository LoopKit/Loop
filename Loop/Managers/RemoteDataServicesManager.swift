//
//  RemoteDataServicesManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit

final class RemoteDataServicesManager: CarbStoreSyncDelegate {

    private unowned let deviceDataManager: DeviceDataManager

    private var remoteDataServices: [RemoteDataService]!

    private var lastSettingsUpdate: Date = .distantPast

    private let log = DiagnosticLog(category: "RemoteDataServicesManager")

    init(servicesManager: ServicesManager, deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager
        self.remoteDataServices = filter(services: servicesManager.services)

        servicesManager.addObserver(self)

        NotificationCenter.default.addObserver(self, selector: #selector(loopCompleted(_:)), name: .LoopCompleted, object: deviceDataManager.loopManager)
        NotificationCenter.default.addObserver(self, selector: #selector(loopDataUpdated(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)
    }

    private func filter(services: [Service]) -> [RemoteDataService] {
        return services.compactMap({ (service) in
            guard let remoteDataService = service as? RemoteDataService else {
                return nil
            }
            return remoteDataService
        })
    }

    @objc func loopDataUpdated(_ note: Notification) {
        guard
            !remoteDataServices.isEmpty,
            let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
            let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext),
            case .preferences = context
            else {
                return
        }

        lastSettingsUpdate = Date()
        
        uploadSettings()
    }

    private func uploadSettings() {
        guard !remoteDataServices.isEmpty else {
            return
        }

        guard let settings = UserDefaults.appGroup?.loopSettings else {
            log.default("Not uploading due to incomplete configuration")
            return
        }

        remoteDataServices.forEach { $0.uploadSettings(settings, lastUpdated: lastSettingsUpdate) }
    }

    @objc func loopCompleted(_ note: Notification) {
        guard !remoteDataServices.isEmpty else {
            return
        }

        deviceDataManager.loopManager.getLoopState { (manager, state) in
            var loopError = state.error
            let recommendedBolus: Double?

            recommendedBolus = state.recommendedBolus?.recommendation.amount

            let carbsOnBoard = state.carbsOnBoard
            let predictedGlucose = state.predictedGlucose
            let recommendedTempBasal = state.recommendedTempBasal

            manager.doseStore.insulinOnBoard(at: Date()) { (result) in
                let insulinOnBoard: InsulinValue?

                switch result {
                case .success(let value):
                    insulinOnBoard = value
                case .failure(let error):
                    insulinOnBoard = nil

                    if loopError == nil {
                        loopError = error
                    }
                }

                self.uploadLoopStatus(
                    insulinOnBoard: insulinOnBoard,
                    carbsOnBoard: carbsOnBoard,
                    predictedGlucose: predictedGlucose,
                    recommendedTempBasal: recommendedTempBasal,
                    recommendedBolus: recommendedBolus,
                    loopError: loopError
                )

                self.uploadSettings()
            }
        }
    }

    func uploadLoopStatus(
        insulinOnBoard: InsulinValue? = nil,
        carbsOnBoard: CarbValue? = nil,
        predictedGlucose: [GlucoseValue]? = nil,
        recommendedTempBasal: (recommendation: TempBasalRecommendation, date: Date)? = nil,
        recommendedBolus: Double? = nil,
        lastReservoirValue: ReservoirValue? = nil,
        pumpManagerStatus: PumpManagerStatus? = nil,
        glucoseTargetRangeSchedule: GlucoseRangeSchedule? = nil,
        scheduleOverride: TemporaryScheduleOverride? = nil,
        glucoseTargetRangeScheduleApplyingOverrideIfActive: GlucoseRangeSchedule? = nil,
        loopError: Error? = nil)
    {
        remoteDataServices.forEach {
            $0.uploadLoopStatus(
                insulinOnBoard: insulinOnBoard,
                carbsOnBoard: carbsOnBoard,
                predictedGlucose: predictedGlucose,
                recommendedTempBasal: recommendedTempBasal,
                recommendedBolus: recommendedBolus,
                lastReservoirValue: lastReservoirValue ?? deviceDataManager.loopManager.doseStore.lastReservoirValue,
                pumpManagerStatus: pumpManagerStatus ?? deviceDataManager.pumpManagerStatus,
                glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
                scheduleOverride: scheduleOverride,
                glucoseTargetRangeScheduleApplyingOverrideIfActive: glucoseTargetRangeScheduleApplyingOverrideIfActive,
                loopError: loopError)
        }
    }

    func upload(glucoseValues values: [GlucoseValue], sensorState: SensorDisplayable?) {
        remoteDataServices.forEach { $0.upload(glucoseValues: values, sensorState: sensorState) }
    }

    func upload(pumpEvents events: [PersistedPumpEvent], fromSource source: String, completion: @escaping (Result<[URL], Error>) -> Void) {
        // TODO: How to handle completion correctly
        if !remoteDataServices.isEmpty {
            remoteDataServices[0].upload(pumpEvents: events, fromSource: source, completion: completion)
        }
    }

    func upload(carbEntries entries: [StoredCarbEntry], completion: @escaping (_ entries: [StoredCarbEntry]) -> Void) {
        // TODO: How to handle completion correctly
        if !remoteDataServices.isEmpty {
            remoteDataServices[0].upload(carbEntries: entries, completion: completion)
        }
    }

    func delete(carbEntries entries: [DeletedCarbEntry], completion: @escaping (_ entries: [DeletedCarbEntry]) -> Void) {
        // TODO: How to handle completion correctly
        if !remoteDataServices.isEmpty {
            remoteDataServices[0].delete(carbEntries: entries, completion: completion)
        }
    }

    func carbStore(_ carbStore: CarbStore, hasEntriesNeedingUpload entries: [StoredCarbEntry], completion: @escaping (_ entries: [StoredCarbEntry]) -> Void) {
        upload(carbEntries: entries, completion: completion)
    }

    func carbStore(_ carbStore: CarbStore, hasDeletedEntries entries: [DeletedCarbEntry], completion: @escaping (_ entries: [DeletedCarbEntry]) -> Void) {
        delete(carbEntries: entries, completion: completion)
    }

}

extension RemoteDataServicesManager: ServicesManagerObserver {

    func servicesManagerDidUpdate(services: [Service]) {
        remoteDataServices = filter(services: services)
    }

}
