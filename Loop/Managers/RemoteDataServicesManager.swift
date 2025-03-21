//
//  RemoteDataServicesManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import os.log
import Foundation
import LoopAlgorithm
import LoopKit
import UIKit

enum RemoteDataType: String, CaseIterable {
    case alert = "Alert"
    case carb = "Carb"
    case dose = "Dose"
    case dosingDecision = "DosingDecision"
    case glucose = "Glucose"
    case pumpEvent = "PumpEvent"
    case cgmEvent = "CgmEvent"
    case settings = "Settings"
    case overrides = "Overrides"

    var debugDescription: String {
        return self.rawValue
    }
}

// Each service can upload each type in parallel. But no more than one task for each
// service & type combination should be running concurrently.
struct UploadTaskKey: Hashable {
    let serviceIdentifier: String
    let remoteDataType: RemoteDataType

    var queueName: String {
        return "com.loopkit.Loop.RemoteDataServicesManager.\(serviceIdentifier).\(remoteDataType.rawValue)DispatchQueue"
    }
}

protocol AutomationHistoryProvider {
    func automationHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Bool>]
}

@MainActor
final class RemoteDataServicesManager {

    public typealias RawState = [String: Any]
    
    public weak var delegate: RemoteDataServicesManagerDelegate?

    private var lock = UnfairLock()


    // RemoteDataServices

    private var unlockedRemoteDataServices = [RemoteDataService]()

    func addService(_ remoteDataService: RemoteDataService) {
        remoteDataService.remoteDataServiceDelegate = self
        lock.withLock {
            unlockedRemoteDataServices.append(remoteDataService)
        }
        uploadExistingData(to: remoteDataService)
    }

    func restoreService(_ remoteDataService: RemoteDataService) {
        remoteDataService.remoteDataServiceDelegate = self
        lock.withLock {
            unlockedRemoteDataServices.append(remoteDataService)
        }
    }

    func removeService(_ remoteDataService: RemoteDataService) {
        lock.withLock {
            unlockedRemoteDataServices.removeAll { $0.pluginIdentifier == remoteDataService.pluginIdentifier }
        }
        clearQueryAnchors(for: remoteDataService)
    }

    private var remoteDataServices: [RemoteDataService] {
        return lock.withLock { unlockedRemoteDataServices }
    }


    // Dispatch Queues for each Service/DataType

    private var unlockedDispatchQueues = [UploadTaskKey: DispatchQueue]()


    private func dispatchQueue(for remoteDataService: RemoteDataService, withRemoteDataType remoteDataType: RemoteDataType) -> DispatchQueue {
        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: remoteDataType)
        return dispatchQueue(key)
    }

    private func dispatchQueue(_ key: UploadTaskKey) -> DispatchQueue {
        return lock.withLock {
            if let dispatchQueue = self.unlockedDispatchQueues[key] {
                return dispatchQueue
            }

            let dispatchQueue = DispatchQueue(label: key.queueName, qos: .utility)
            self.unlockedDispatchQueues[key] = dispatchQueue
            return dispatchQueue
        }
    }

    private var lockedFailedUploads: Locked<Set<UploadTaskKey>>

    var failedUploads: [UploadTaskKey] {
        Array(lockedFailedUploads.value)
    }

    func uploadFailed(_ key: UploadTaskKey) {
        lockedFailedUploads.mutate { failedUploads in
            failedUploads.insert(key)
        }
        log.debug("RemoteDataType %{public}@ upload failed", key.remoteDataType.rawValue)
    }

    func uploadSucceeded(_ key: UploadTaskKey) {
        lockedFailedUploads.mutate { failedUploads in
            failedUploads.remove(key)
        }
    }

    let uploadGroup = DispatchGroup()

    private let log = OSLog(category: "RemoteDataServicesManager")
    
    private let alertStore: AlertStore

    private let carbStore: CarbStore

    private let doseStore: DoseStore

    private let dosingDecisionStore: DosingDecisionStoreProtocol

    private let glucoseStore: GlucoseStore

    private let cgmEventStore: CgmEventStore

    private let insulinDeliveryStore: InsulinDeliveryStore

    private let settingsProvider: SettingsProvider

    private let overrideHistory: TemporaryScheduleOverrideHistory

    private let deviceLog: PersistentDeviceLog

    private let automationHistoryProvider: AutomationHistoryProvider


    init(
        alertStore: AlertStore,
        carbStore: CarbStore,
        doseStore: DoseStore,
        dosingDecisionStore: DosingDecisionStoreProtocol,
        glucoseStore: GlucoseStore,
        cgmEventStore: CgmEventStore,
        settingsProvider: SettingsProvider,
        overrideHistory: TemporaryScheduleOverrideHistory,
        insulinDeliveryStore: InsulinDeliveryStore,
        deviceLog: PersistentDeviceLog,
        automationHistoryProvider: AutomationHistoryProvider
    ) {
        self.alertStore = alertStore
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.dosingDecisionStore = dosingDecisionStore
        self.glucoseStore = glucoseStore
        self.cgmEventStore = cgmEventStore
        self.insulinDeliveryStore = insulinDeliveryStore
        self.settingsProvider = settingsProvider
        self.overrideHistory = overrideHistory
        self.lockedFailedUploads = Locked([])
        self.deviceLog = deviceLog
        self.automationHistoryProvider = automationHistoryProvider
    }

    private func uploadExistingData(to remoteDataService: RemoteDataService) {
        uploadAlertData(to: remoteDataService)
        uploadCarbData(to: remoteDataService)
        uploadDoseData(to: remoteDataService)
        uploadDosingDecisionData(to: remoteDataService)
        uploadGlucoseData(to: remoteDataService)
        uploadPumpEventData(to: remoteDataService)
        uploadSettingsData(to: remoteDataService)
    }

    private func clearQueryAnchors(for remoteDataService: RemoteDataService) {
        for remoteDataType in RemoteDataType.allCases {
            dispatchQueue(for: remoteDataService, withRemoteDataType: remoteDataType).async {
                UserDefaults.appGroup?.deleteQueryAnchor(for: remoteDataService, withRemoteDataType: remoteDataType)
            }
        }
    }

    func triggerAllUploads() {
        Task {
            for type in RemoteDataType.allCases {
                await performUpload(for: type)
            }
        }
    }

    func triggerUpload(for triggeringType: RemoteDataType) {
        Task {
            await performUpload(for: triggeringType)
        }
    }

    func performUpload(for triggeringType: RemoteDataType) {
        let uploadTypes = [triggeringType] + failedUploads.map { $0.remoteDataType }

        log.debug("RemoteDataType %{public}@ triggering uploads for: %{public}@", triggeringType.rawValue, String(describing: uploadTypes.map { $0.debugDescription}))

        for type in uploadTypes {
            switch type {
            case .alert:
                remoteDataServices.forEach { self.uploadAlertData(to: $0) }
            case .carb:
                remoteDataServices.forEach { self.uploadCarbData(to: $0) }
            case .dose:
                remoteDataServices.forEach { self.uploadDoseData(to: $0) }
            case .dosingDecision:
                remoteDataServices.forEach { self.uploadDosingDecisionData(to: $0) }
            case .glucose:
                remoteDataServices.forEach { self.uploadGlucoseData(to: $0) }
            case .pumpEvent:
                remoteDataServices.forEach { self.uploadPumpEventData(to: $0) }
            case .cgmEvent:
                remoteDataServices.forEach { self.uploadCgmEventData(to: $0) }
            case .settings:
                remoteDataServices.forEach { self.uploadSettingsData(to: $0) }
            case .overrides:
                remoteDataServices.forEach { self.uploadTemporaryOverrideData(to: $0) }
            }
        }
    }
    
    func performUpload(for triggeringType: RemoteDataType, completion: @escaping () -> Void) {
        performUpload(for: triggeringType)
        self.uploadGroup.notify(queue: DispatchQueue.main) {
            completion()
        }
    }
    
    func performUpload(for triggeringType: RemoteDataType) async {
        return await withCheckedContinuation { continuation in
            performUpload(for: triggeringType) {
                continuation.resume(returning: ())
            }
        }
    }
}

extension RemoteDataServicesManager {
    private func uploadAlertData(to remoteDataService: RemoteDataService) {
        uploadGroup.enter()

        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: .alert)

        dispatchQueue(key).async {
            let semaphore = DispatchSemaphore(value: 0)
            let queryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .alert) ?? AlertStore.QueryAnchor()

            self.alertStore.executeAlertQuery(fromQueryAnchor: queryAnchor, limit: remoteDataService.alertDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying alert data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let data):
                    Task {
                        do {
                            try await remoteDataService.uploadAlertData(data)
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .alert, queryAnchor)
                            self.uploadSucceeded(key)
                        } catch {
                            self.log.error("Error synchronizing alert data: %{public}@", String(describing: error))
                            self.uploadFailed(key)
                        }
                        semaphore.signal()
                    }
                }
            }
            semaphore.wait()
            self.uploadGroup.leave()
        }
    }
}

extension RemoteDataServicesManager {
    private func uploadCarbData(to remoteDataService: RemoteDataService) {
        uploadGroup.enter()

        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: .carb)

        dispatchQueue(key).async {
            let semaphore = DispatchSemaphore(value: 0)
            let previousQueryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .carb) ?? CarbStore.QueryAnchor()
            var continueUpload = false

            self.carbStore.executeCarbQuery(fromQueryAnchor: previousQueryAnchor, limit: remoteDataService.carbDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying carb data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let created, let updated, let deleted):
                    Task {
                        do {
                            try await remoteDataService.uploadCarbData(created: created, updated: updated, deleted: deleted)
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .carb, queryAnchor)
                            continueUpload = queryAnchor != previousQueryAnchor
                            self.uploadSucceeded(key)
                        } catch {
                            self.log.error("Error synchronizing carb data: %{public}@", String(describing: error))
                            self.uploadFailed(key)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
            self.uploadGroup.leave()

            if continueUpload {
                self.uploadCarbData(to: remoteDataService)
            }
        }
    }
}

extension RemoteDataServicesManager {
    private func uploadDoseData(to remoteDataService: RemoteDataService) {
        uploadGroup.enter()

        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: .dose)

        dispatchQueue(key).async {
            let semaphore = DispatchSemaphore(value: 0)
            let previousQueryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .dose) ?? InsulinDeliveryStore.QueryAnchor()
            var continueUpload = false

            self.insulinDeliveryStore.executeDoseQuery(fromQueryAnchor: previousQueryAnchor, limit: remoteDataService.doseDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying dose data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let created, let deleted):
                    Task {
                        do {
                            continueUpload = queryAnchor != previousQueryAnchor
                            try await remoteDataService.uploadDoseData(created: created, deleted: deleted)
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .dose, queryAnchor)
                            self.uploadSucceeded(key)
                        } catch {
                            self.log.error("Error synchronizing dose data: %{public}@", String(describing: error))
                            self.uploadFailed(key)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
            self.uploadGroup.leave()

            if continueUpload {
                self.uploadDoseData(to: remoteDataService)
            }
        }
    }
}

extension RemoteDataServicesManager {
    private func uploadDosingDecisionData(to remoteDataService: RemoteDataService) {
        uploadGroup.enter()

        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: .dosingDecision)

        dispatchQueue(key).async {
            let semaphore = DispatchSemaphore(value: 0)
            let previousQueryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .dosingDecision) ?? DosingDecisionStore.QueryAnchor()
            var continueUpload = false

            self.dosingDecisionStore.executeDosingDecisionQuery(fromQueryAnchor: previousQueryAnchor, limit: remoteDataService.dosingDecisionDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying dosing decision data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let data):
                    Task {
                        do {
                            try await remoteDataService.uploadDosingDecisionData(data)
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .dosingDecision, queryAnchor)
                            continueUpload = queryAnchor != previousQueryAnchor
                            self.uploadSucceeded(key)

                        } catch {
                            self.log.error("Error synchronizing dosing decision data: %{public}@", String(describing: error))
                            self.uploadFailed(key)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
            self.uploadGroup.leave()

            if continueUpload {
                self.uploadDosingDecisionData(to: remoteDataService)
            }
        }
    }
}

extension RemoteDataServicesManager {
    private func uploadGlucoseData(to remoteDataService: RemoteDataService) {
        guard delegate?.shouldSyncGlucoseToRemoteService != false else { return }

        uploadGroup.enter()

        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: .glucose)

        dispatchQueue(key).async {
            let semaphore = DispatchSemaphore(value: 0)
            let previousQueryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .glucose) ?? GlucoseStore.QueryAnchor()
            var continueUpload = false

            Task {
                do {
                    let (queryAnchor, data) = try await self.glucoseStore.executeGlucoseQuery(fromQueryAnchor: previousQueryAnchor, limit: remoteDataService.glucoseDataLimit ?? Int.max)
                    do {
                        try await remoteDataService.uploadGlucoseData(data)
                        UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .glucose, queryAnchor)
                        continueUpload = queryAnchor != previousQueryAnchor
                        await self.uploadSucceeded(key)
                    } catch {
                        self.log.error("Error synchronizing glucose data: %{public}@", String(describing: error))
                        await self.uploadFailed(key)
                    }
                    semaphore.signal()
                } catch {
                    self.log.error("Error querying glucose data: %{public}@", String(describing: error))
                    semaphore.signal()
                }
            }

            semaphore.wait()
            self.uploadGroup.leave()

            if continueUpload {
                self.uploadGlucoseData(to: remoteDataService)
            }
        }
    }
}

extension RemoteDataServicesManager {
    private func uploadPumpEventData(to remoteDataService: RemoteDataService) {
        uploadGroup.enter()

        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: .pumpEvent)

        dispatchQueue(for: remoteDataService, withRemoteDataType: .pumpEvent).async {
            let semaphore = DispatchSemaphore(value: 0)
            let previousQueryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .pumpEvent) ?? DoseStore.QueryAnchor()
            var continueUpload = false
            Task {
                do {
                    let (queryAnchor, data) = try await self.doseStore.executePumpEventQuery(fromQueryAnchor: previousQueryAnchor, limit: remoteDataService.pumpEventDataLimit ?? Int.max)
                    do {
                        try await remoteDataService.uploadPumpEventData(data)
                        UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .pumpEvent, queryAnchor)
                        continueUpload = queryAnchor != previousQueryAnchor
                        self.uploadSucceeded(key)
                    } catch {
                        self.log.error("Error synchronizing pump event data: %{public}@", String(describing: error))
                        self.uploadFailed(key)
                    }
                    semaphore.signal()
                } catch {
                    self.log.error("Error querying pump event data: %{public}@", String(describing: error))
                    semaphore.signal()
                }
            }

            semaphore.wait()
            self.uploadGroup.leave()

            if continueUpload {
                self.uploadPumpEventData(to: remoteDataService)
            }
        }
    }
}

extension RemoteDataServicesManager {
    private func uploadSettingsData(to remoteDataService: RemoteDataService) {
        uploadGroup.enter()

        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: .settings)

        dispatchQueue(for: remoteDataService, withRemoteDataType: .settings).async {
            let semaphore = DispatchSemaphore(value: 0)
            let previousQueryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .settings) ?? SettingsStore.QueryAnchor()
            var continueUpload = false

            self.settingsProvider.executeSettingsQuery(fromQueryAnchor: previousQueryAnchor, limit: remoteDataService.settingsDataLimit ?? Int.max) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying settings data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let data):
                    Task {
                        do {
                            try await remoteDataService.uploadSettingsData(data)
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .settings, queryAnchor)
                            continueUpload = queryAnchor != previousQueryAnchor
                            self.uploadSucceeded(key)
                        } catch {
                            self.log.error("Error synchronizing settings data: %{public}@", String(describing: error))
                            self.uploadFailed(key)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
            self.uploadGroup.leave()

            if continueUpload {
                self.uploadSettingsData(to: remoteDataService)
            }
        }
    }
}

extension RemoteDataServicesManager {
    private func uploadTemporaryOverrideData(to remoteDataService: RemoteDataService) {
        uploadGroup.enter()

        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: .overrides)

        dispatchQueue(for: remoteDataService, withRemoteDataType: .overrides).async {
            let semaphore = DispatchSemaphore(value: 0)

            let queryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .overrides) ?? TemporaryScheduleOverrideHistory.QueryAnchor()

            let (overrides, deletedOverrides, newAnchor) = self.overrideHistory.queryByAnchor(queryAnchor)

            Task {
                do {
                    try await remoteDataService.uploadTemporaryOverrideData(updated: overrides, deleted: deletedOverrides)
                    UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .overrides, newAnchor)
                    self.uploadSucceeded(key)
                } catch {
                    self.log.error("Error synchronizing temporary override data: %{public}@", String(describing: error))
                    self.uploadFailed(key)
                }
                semaphore.signal()
            }

            semaphore.wait()
            self.uploadGroup.leave()
        }
    }
}

extension RemoteDataServicesManager {
    private func uploadCgmEventData(to remoteDataService: RemoteDataService) {
        uploadGroup.enter()

        let key = UploadTaskKey(serviceIdentifier: remoteDataService.pluginIdentifier, remoteDataType: .pumpEvent)

        dispatchQueue(for: remoteDataService, withRemoteDataType: .cgmEvent).async {
            let semaphore = DispatchSemaphore(value: 0)
            let previousQueryAnchor = UserDefaults.appGroup?.getQueryAnchor(for: remoteDataService, withRemoteDataType: .cgmEvent) ?? CgmEventStore.QueryAnchor()
            var continueUpload = false

            self.cgmEventStore.executeCgmEventQuery(fromQueryAnchor: previousQueryAnchor) { result in
                switch result {
                case .failure(let error):
                    self.log.error("Error querying cgm event data: %{public}@", String(describing: error))
                    semaphore.signal()
                case .success(let queryAnchor, let data):
                    Task {
                        do {
                            try await remoteDataService.uploadCgmEventData(data)
                            UserDefaults.appGroup?.setQueryAnchor(for: remoteDataService, withRemoteDataType: .cgmEvent, queryAnchor)
                            continueUpload = queryAnchor != previousQueryAnchor
                            self.uploadSucceeded(key)
                        } catch {
                            self.log.error("Error synchronizing pump event data: %{public}@", String(describing: error))
                            self.uploadFailed(key)
                        }
                        semaphore.signal()
                    }
                }
            }

            semaphore.wait()
            self.uploadGroup.leave()

            if continueUpload {
                self.uploadPumpEventData(to: remoteDataService)
            }
        }
    }
}

// RemoteDataServiceDelegate
extension RemoteDataServicesManager: RemoteDataServiceDelegate {
    func automationHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Bool>] {
        try await automationHistoryProvider.automationHistory(from: start, to: end)
    }
    
    func getBasalHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        try await settingsProvider.getBasalHistory(startDate: startDate, endDate: endDate)
    }
    
    func fetchDeviceLogs(startDate: Date, endDate: Date) async throws -> [StoredDeviceLogEntry] {
        return try await deviceLog.fetch(startDate: startDate, endDate: endDate)
    }
}

//Remote Commands
extension RemoteDataServicesManager {
    
    public func remoteNotificationWasReceived(_ notification: [String: AnyObject]) async throws {
        let service = try serviceForPushNotification(notification)
        return try await service.remoteNotificationWasReceived(notification)
    }
    
    func serviceForPushNotification(_ notification: [String: AnyObject]) throws -> RemoteDataService {
        let defaultServiceIdentifier = "NightscoutService"
        let serviceIdentifier = notification["serviceIdentifier"] as? String ?? defaultServiceIdentifier
        guard let service = remoteDataServices.first(where: {$0.pluginIdentifier == serviceIdentifier}) else {
            throw RemoteDataServicesManagerCommandError.unsupportedServiceIdentifier(serviceIdentifier)
        }
        return service
    }
    
    enum RemoteDataServicesManagerCommandError: LocalizedError {
        case unsupportedServiceIdentifier(String)
        
        var errorDescription: String? {
            switch self {
            case .unsupportedServiceIdentifier(let serviceIdentifier):
                return String(format: NSLocalizedString("Unsupported Notification Service: %1$@", comment: "Error message when a service can't be found to handle a push notification. (1: Service Identifier)"), serviceIdentifier)
            }
        }
    }
}

extension RemoteDataServicesManager: UploadEventListener { }

protocol RemoteDataServicesManagerDelegate: AnyObject {
    var shouldSyncGlucoseToRemoteService: Bool { get }
}


fileprivate extension UserDefaults {

    private func queryAnchorKey(for remoteDataService: RemoteDataService, withRemoteDataType remoteDataType: RemoteDataType) -> String {
        return "com.loopkit.Loop.RemoteDataServicesManager.\(remoteDataService.pluginIdentifier).\(remoteDataType.rawValue)QueryAnchor"
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
