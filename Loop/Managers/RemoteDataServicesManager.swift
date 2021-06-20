//
//  RemoteDataServicesManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import os.log
import Foundation
import LoopKit

enum RemoteDataType: String {
    case carb = "Carb"
    case dose = "Dose"
    case dosingDecision = "DosingDecision"
    case glucose = "Glucose"
    case pumpEvent = "PumpEvent"
    case settings = "Settings"
}

final class RemoteDataServicesManager {

    public typealias RawState = [String: Any]

    private var lock = UnfairLock()

    private var unlockedRemoteDataServices = [RemoteDataService]()

    private var unlockedDispatchQueues = [String: DispatchQueue]()

    private let log = OSLog(category: "RemoteDataServicesManager")
    
    private var carbStore: CarbStore

    private var doseStore: DoseStore

    private var dosingDecisionStore: DosingDecisionStore

    private var glucoseStore: GlucoseStore

    private var settingsStore: SettingsStore

    init(
        carbStore: CarbStore,
        doseStore: DoseStore,
        dosingDecisionStore: DosingDecisionStore,
        glucoseStore: GlucoseStore,
        settingsStore: SettingsStore
    ) {
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.dosingDecisionStore = dosingDecisionStore
        self.glucoseStore = glucoseStore
        self.settingsStore = settingsStore
    }

    func addService(_ remoteDataService: RemoteDataService) {
        lock.withLock {
            unlockedRemoteDataServices.append(remoteDataService)
        }
        uploadExistingData(to: remoteDataService)
    }

    func restoreService(_ remoteDataService: RemoteDataService) {
        lock.withLock {
            unlockedRemoteDataServices.append(remoteDataService)
        }
    }

    func removeService(_ remoteDataService: RemoteDataService) {
        lock.withLock {
            unlockedRemoteDataServices.removeAll { $0.serviceIdentifier == remoteDataService.serviceIdentifier }
        }
        clearQueryAnchors(for: remoteDataService)
    }

    private func uploadExistingData(to remoteDataService: RemoteDataService) {
        uploadCarbData(to: remoteDataService)
        uploadDoseData(to: remoteDataService)
        uploadDosingDecisionData(to: remoteDataService)
        uploadGlucoseData(to: remoteDataService)
        uploadPumpEventData(to: remoteDataService)
        uploadSettingsData(to: remoteDataService)
    }

    private func clearQueryAnchors(for remoteDataService: RemoteDataService) {
        clearCarbQueryAnchor(for: remoteDataService)
        clearDoseQueryAnchor(for: remoteDataService)
        clearDosingDecisionQueryAnchor(for: remoteDataService)
        clearGlucoseQueryAnchor(for: remoteDataService)
        clearPumpEventQueryAnchor(for: remoteDataService)
        clearSettingsQueryAnchor(for: remoteDataService)
    }

    private var remoteDataServices: [RemoteDataService] { return lock.withLock { unlockedRemoteDataServices } }

    private func dispatchQueue(for remoteDataService: RemoteDataService, withRemoteDataType remoteDataType: RemoteDataType) -> DispatchQueue {
        return lock.withLock {
            let dispatchQueueName = self.dispatchQueueName(for: remoteDataService, withRemoteDataType: remoteDataType)

            if let dispatchQueue = self.unlockedDispatchQueues[dispatchQueueName] {
                return dispatchQueue
            }

            let dispatchQueue = DispatchQueue(label: dispatchQueueName, qos: .utility)
            self.unlockedDispatchQueues[dispatchQueueName] = dispatchQueue
            return dispatchQueue
        }
    }

    private func dispatchQueueName(for remoteDataService: RemoteDataService, withRemoteDataType remoteDataType: RemoteDataType) -> String {
        return "com.loopkit.Loop.RemoteDataServicesManager.\(remoteDataService.serviceIdentifier).\(remoteDataType.rawValue)DispatchQueue"
    }

}

extension RemoteDataServicesManager {

    public func carbStoreHasUpdatedCarbData(_ carbStore: CarbStore) {
        remoteDataServices.forEach { self.uploadCarbData(to: $0) }
    }

    private func uploadCarbData(to remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .carb).async {
            let semaphore = DispatchSemaphore(value: 0)
            let queryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .carb) ?? CarbStore.QueryAnchor()
            
            self.carbStore.executeCarbQuery(fromQueryAnchor: queryAnchor, limit: remoteDataService.carbDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying carb data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let created, let updated, let deleted):
                    remoteDataService.uploadCarbData(created: created, updated: updated, deleted: deleted) { result in
                        switch result {
                        case .failure(let error):
                            self.log.error("Error synchronizing carb data: %{public}@", String(describing: error))
                        case .success:
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .carb, queryAnchor)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
        }
    }

    private func clearCarbQueryAnchor(for remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .carb).async {
            UserDefaults.appGroup?.deleteQueryAnchor(for: remoteDataService, withRemoteDataType: .carb)
        }
    }

}

extension RemoteDataServicesManager {

    public func doseStoreHasUpdatedDoseData(_ doseStore: DoseStore) {
        remoteDataServices.forEach { self.uploadDoseData(to: $0) }
    }

    private func uploadDoseData(to remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .dose).async {
            let semaphore = DispatchSemaphore(value: 0)
            let queryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .dose) ?? DoseStore.QueryAnchor()

            self.doseStore.executeDoseQuery(fromQueryAnchor: queryAnchor, limit: remoteDataService.doseDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying dose data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let data):
                    remoteDataService.uploadDoseData(data) { result in
                        switch result {
                        case .failure(let error):
                            self.log.error("Error synchronizing dose data: %{public}@", String(describing: error))
                        case .success:
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .dose, queryAnchor)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
        }
    }

    private func clearDoseQueryAnchor(for remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .dose).async {
            UserDefaults.appGroup?.deleteQueryAnchor(for: remoteDataService, withRemoteDataType: .dose)
        }
    }

}

extension RemoteDataServicesManager {

    public func dosingDecisionStoreHasUpdatedDosingDecisionData(_ dosingDecisionStore: DosingDecisionStore) {
        remoteDataServices.forEach { self.uploadDosingDecisionData(to: $0) }
    }

    private func uploadDosingDecisionData(to remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .dosingDecision).async {
            let semaphore = DispatchSemaphore(value: 0)
            let queryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .dosingDecision) ?? DosingDecisionStore.QueryAnchor()

            self.dosingDecisionStore.executeDosingDecisionQuery(fromQueryAnchor: queryAnchor, limit: remoteDataService.dosingDecisionDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying dosing decision data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let data):
                    remoteDataService.uploadDosingDecisionData(data) { result in
                        switch result {
                        case .failure(let error):
                            self.log.error("Error synchronizing dosing decision data: %{public}@", String(describing: error))
                        case .success:
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .dosingDecision, queryAnchor)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
        }
    }

    private func clearDosingDecisionQueryAnchor(for remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .dosingDecision).async {
            UserDefaults.appGroup?.deleteQueryAnchor(for: remoteDataService, withRemoteDataType: .dosingDecision)
        }
    }

}

extension RemoteDataServicesManager {

    public func glucoseStoreHasUpdatedGlucoseData(_ glucoseStore: GlucoseStore) {
        remoteDataServices.forEach { self.uploadGlucoseData(to: $0) }
    }

    private func uploadGlucoseData(to remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .glucose).async {
            let semaphore = DispatchSemaphore(value: 0)
            let queryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .glucose) ?? GlucoseStore.QueryAnchor()

            self.glucoseStore.executeGlucoseQuery(fromQueryAnchor: queryAnchor, limit: remoteDataService.glucoseDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying glucose data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let data):
                    remoteDataService.uploadGlucoseData(data) { result in
                        switch result {
                        case .failure(let error):
                            self.log.error("Error synchronizing glucose data: %{public}@", String(describing: error))
                        case .success:
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .glucose, queryAnchor)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
        }
    }

    private func clearGlucoseQueryAnchor(for remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .glucose).async {
            UserDefaults.appGroup?.deleteQueryAnchor(for: remoteDataService, withRemoteDataType: .glucose)
        }
    }

}

extension RemoteDataServicesManager {

    public func doseStoreHasUpdatedPumpEventData(_ doseStore: DoseStore) {
        remoteDataServices.forEach { self.uploadPumpEventData(to: $0) }
    }

    private func uploadPumpEventData(to remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .pumpEvent).async {
            let semaphore = DispatchSemaphore(value: 0)
            let queryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .pumpEvent) ?? DoseStore.QueryAnchor()

            self.doseStore.executePumpEventQuery(fromQueryAnchor: queryAnchor, limit: remoteDataService.pumpEventDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying pump event data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let data):
                    remoteDataService.uploadPumpEventData(data) { result in
                        switch result {
                        case .failure(let error):
                            self.log.error("Error synchronizing pump event data: %{public}@", String(describing: error))
                        case .success:
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .pumpEvent, queryAnchor)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
        }
    }

    private func clearPumpEventQueryAnchor(for remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .pumpEvent).async {
            UserDefaults.appGroup?.deleteQueryAnchor(for: remoteDataService, withRemoteDataType: .pumpEvent)
        }
    }

}

extension RemoteDataServicesManager {

    public func settingsStoreHasUpdatedSettingsData(_ settingsStore: SettingsStore) {
        remoteDataServices.forEach { self.uploadSettingsData(to: $0) }
    }

    private func uploadSettingsData(to remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .settings).async {
            let semaphore = DispatchSemaphore(value: 0)
            let queryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .settings) ?? SettingsStore.QueryAnchor()

            self.settingsStore.executeSettingsQuery(fromQueryAnchor: queryAnchor, limit: remoteDataService.settingsDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying settings data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let data):
                    remoteDataService.uploadSettingsData(data) { result in
                        switch result {
                        case .failure(let error):
                            self.log.error("Error synchronizing settings data: %{public}@", String(describing: error))
                        case .success:
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .settings, queryAnchor)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
        }
    }

    private func clearSettingsQueryAnchor(for remoteDataService: RemoteDataService) {
        dispatchQueue(for: remoteDataService, withRemoteDataType: .settings).async {
            UserDefaults.appGroup?.deleteQueryAnchor(for: remoteDataService, withRemoteDataType: .settings)
        }
    }

}

extension RemoteDataServicesManager {

    func validatePushNotificationSource(_ notification: [String: AnyObject]) -> Bool {
        for service in remoteDataServices {
            let validated = service.validatePushNotificationSource(notification)
            if validated {
                return validated
            }
        }
        
        return false
    }
    
}

fileprivate extension UserDefaults {

    private func queryAnchorKey(for remoteDataService: RemoteDataService, withRemoteDataType remoteDataType: RemoteDataType) -> String {
        return "com.loopkit.Loop.RemoteDataServicesManager.\(remoteDataService.serviceIdentifier).\(remoteDataType.rawValue)QueryAnchor"
    }

    func getQueryAnchor<T>(for remoteDataService: RemoteDataService, withRemoteDataType remoteDataType: RemoteDataType) -> T? where T: RawRepresentable, T.RawValue == [String: Any] {
        guard let rawQueryAnchor = dictionary(forKey: queryAnchorKey(for: remoteDataService, withRemoteDataType: remoteDataType)) else {
            return nil
        }
        return T.init(rawValue: rawQueryAnchor)
    }

    func setQueryAnchor<T>(for remoteDataService: RemoteDataService, withRemoteDataType remoteDataType: RemoteDataType, _ queryAnchor: T) where T: RawRepresentable, T.RawValue == [String: Any] {
        set(queryAnchor.rawValue, forKey: queryAnchorKey(for: remoteDataService, withRemoteDataType: remoteDataType))
    }

    func deleteQueryAnchor(for remoteDataService: RemoteDataService, withRemoteDataType remoteDataType: RemoteDataType) {
        removeObject(forKey: queryAnchorKey(for: remoteDataService, withRemoteDataType: remoteDataType))
    }

}
