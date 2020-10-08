//
//  DosingDecisionStore.swift
//  Loop
//
//  Created by Darin Krauss on 5/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

extension DosingDecisionStore {
    public func storeDosingDecision(_ dosingDecision: StoredDosingDecision, completion: @escaping () -> Void) {
        if let data = encodeDosingDecision(dosingDecision) {
            storeDosingDecisionData(StoredDosingDecisionData(date: dosingDecision.date, data: data), completion: completion)
        }
    }

    private static var encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    private func encodeDosingDecision(_ dosingDecision: StoredDosingDecision) -> Data? {
        do {
            return try DosingDecisionStore.encoder.encode(dosingDecision)
        } catch let error {
            log.error("Error encoding StoredDosingDecision: %@", String(describing: error))
            return nil
        }
    }

    private static var decoder = PropertyListDecoder()

    private func decodeDosingDecision(fromData data: Data) -> StoredDosingDecision? {
        do {
            return try DosingDecisionStore.decoder.decode(StoredDosingDecision.self, from: data)
        } catch let error {
            log.error("Error decoding StoredDosingDecision: %@", String(describing: error))
            return nil
        }
    }
}

extension DosingDecisionStore {
    public enum DosingDecisionQueryResult {
        case success(QueryAnchor, [StoredDosingDecision])
        case failure(Error)
    }

    public func executeDosingDecisionQuery(fromQueryAnchor queryAnchor: QueryAnchor?, limit: Int, completion: @escaping (DosingDecisionQueryResult) -> Void) {
        executeDosingDecisionDataQuery(fromQueryAnchor: queryAnchor, limit: limit) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let anchor, let dosingDecisionData):
                completion(.success(anchor, dosingDecisionData.compactMap { self.decodeDosingDecision(fromData: $0.data) }))
            }
        }
    }
}

extension StoredDosingDecision: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedDosingDecisionError = try container.decodeIfPresent([StoredDosingDecisionError].self, forKey: .errors)
        self.init(date: try container.decode(Date.self, forKey: .date),
                  insulinOnBoard: try container.decodeIfPresent(InsulinValue.self, forKey: .insulinOnBoard),
                  carbsOnBoard: try container.decodeIfPresent(CarbValue.self, forKey: .carbsOnBoard),
                  scheduleOverride: try container.decodeIfPresent(TemporaryScheduleOverride.self, forKey: .scheduleOverride),
                  glucoseTargetRangeSchedule: try container.decodeIfPresent(GlucoseRangeSchedule.self, forKey: .glucoseTargetRangeSchedule),
                  glucoseTargetRangeScheduleApplyingOverrideIfActive: try container.decodeIfPresent(GlucoseRangeSchedule.self, forKey: .glucoseTargetRangeScheduleApplyingOverrideIfActive),
                  predictedGlucose: try container.decodeIfPresent([PredictedGlucoseValue].self, forKey: .predictedGlucose),
                  predictedGlucoseIncludingPendingInsulin: try container.decodeIfPresent([PredictedGlucoseValue].self, forKey: .predictedGlucoseIncludingPendingInsulin),
                  lastReservoirValue: try container.decodeIfPresent(LastReservoirValue.self, forKey: .lastReservoirValue),
                  recommendedTempBasal: try container.decodeIfPresent(TempBasalRecommendationWithDate.self, forKey: .recommendedTempBasal),
                  recommendedBolus: try container.decodeIfPresent(BolusRecommendationWithDate.self, forKey: .recommendedBolus),
                  pumpManagerStatus: try container.decodeIfPresent(PumpManagerStatus.self, forKey: .pumpManagerStatus),
                  notificationSettings: try container.decodeIfPresent(NotificationSettings.self, forKey: .notificationSettings),
                  deviceSettings: try container.decodeIfPresent(DeviceSettings.self, forKey: .deviceSettings),
                  errors: storedDosingDecisionError?.map { $0.error },
                  syncIdentifier: try container.decode(String.self, forKey: .syncIdentifier))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(insulinOnBoard, forKey: .insulinOnBoard)
        try container.encodeIfPresent(carbsOnBoard, forKey: .carbsOnBoard)
        try container.encodeIfPresent(scheduleOverride, forKey: .scheduleOverride)
        try container.encodeIfPresent(glucoseTargetRangeSchedule, forKey: .glucoseTargetRangeSchedule)
        try container.encodeIfPresent(glucoseTargetRangeScheduleApplyingOverrideIfActive, forKey: .glucoseTargetRangeScheduleApplyingOverrideIfActive)
        try container.encodeIfPresent(predictedGlucose, forKey: .predictedGlucose)
        try container.encodeIfPresent(predictedGlucoseIncludingPendingInsulin, forKey: .predictedGlucoseIncludingPendingInsulin)
        try container.encodeIfPresent(lastReservoirValue, forKey: .lastReservoirValue)
        try container.encodeIfPresent(recommendedTempBasal, forKey: .recommendedTempBasal)
        try container.encodeIfPresent(recommendedBolus, forKey: .recommendedBolus)
        try container.encodeIfPresent(pumpManagerStatus, forKey: .pumpManagerStatus)
        try container.encodeIfPresent(notificationSettings, forKey: .notificationSettings)
        try container.encodeIfPresent(deviceSettings, forKey: .deviceSettings)
        try container.encodeIfPresent(errors?.map { StoredDosingDecisionError(error: $0) }, forKey: .errors)
        try container.encode(syncIdentifier, forKey: .syncIdentifier)
    }
    
    private enum StoredDosingDecisionError: Codable {
        case carbStoreError(CarbStore.CarbStoreError)
        case doseStoreError(DoseStore.DoseStoreError)
        case loopError(LoopError)
        case pumpManagerError(PumpManagerError)
        case unknownError(Error)
        
        init(error: Error) {
            switch error {
            case let error as CarbStore.CarbStoreError:
                self = .carbStoreError(error)
            case let error as DoseStore.DoseStoreError:
                self = .doseStoreError(error)
            case let error as LoopError:
                self = .loopError(error)
            case let error as PumpManagerError:
                self = .pumpManagerError(error)
            default:
                self = .unknownError(error)
            }
        }
        
        var error: Error {
            switch self {
            case .carbStoreError(let error):
                return error
            case .doseStoreError(let error):
                return error
            case .loopError(let error):
                return error
            case .pumpManagerError(let error):
                return error
            case .unknownError(let error):
                return error
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodableKeys.self)
            if let carbStoreError = try container.decodeIfPresent(CarbStore.CarbStoreError.self, forKey: .carbStoreError) {
                self = .carbStoreError(carbStoreError)
            } else if let doseStoreError = try container.decodeIfPresent(DoseStore.DoseStoreError.self, forKey: .doseStoreError) {
                self = .doseStoreError(doseStoreError)
            } else if let loopError = try container.decodeIfPresent(LoopError.self, forKey: .loopError) {
                self = .loopError(loopError)
            } else if let pumpManagerError = try container.decodeIfPresent(PumpManagerError.self, forKey: .pumpManagerError) {
                self = .pumpManagerError(pumpManagerError)
            } else if let error = try container.decodeIfPresent(CodableLocalizedError.self, forKey: .unknownError) {
                self = .unknownError(error)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid enumeration"))
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodableKeys.self)
            switch self {
            case .carbStoreError(let error):
                try container.encode(error, forKey: .carbStoreError)
            case .doseStoreError(let error):
                try container.encode(error, forKey: .doseStoreError)
            case .loopError(let error):
                try container.encode(error, forKey: .loopError)
            case .pumpManagerError(let error):
                try container.encode(error, forKey: .pumpManagerError)
            case .unknownError(let error):
                try container.encode(CodableLocalizedError(error), forKey: .unknownError)
            }
        }
        
        private enum CodableKeys: String, CodingKey {
            case carbStoreError
            case doseStoreError
            case loopError
            case pumpManagerError
            case unknownError
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case date
        case insulinOnBoard
        case carbsOnBoard
        case scheduleOverride
        case glucoseTargetRangeSchedule
        case glucoseTargetRangeScheduleApplyingOverrideIfActive
        case predictedGlucose
        case predictedGlucoseIncludingPendingInsulin
        case lastReservoirValue
        case recommendedTempBasal
        case recommendedBolus
        case pumpManagerStatus
        case notificationSettings
        case deviceSettings
        case errors
        case syncIdentifier
    }
}

public struct CodableLocalizedError: LocalizedError, Codable {
    public let errorDescription: String?
    public let failureReason: String?
    public let helpAnchor: String?
    public let recoverySuggestion: String?

    public init(_ error: Error) {
        let localizedError = error as? LocalizedError
        self.errorDescription = localizedError?.errorDescription
        self.failureReason = localizedError?.failureReason
        self.helpAnchor = localizedError?.helpAnchor
        self.recoverySuggestion = localizedError?.recoverySuggestion
    }

    public init?(_ error: Error?) {
        guard let error = error else {
            return nil
        }
        self.init(error)
    }

    public init(_ localizedError: LocalizedError) {
        self.errorDescription = localizedError.errorDescription
        self.failureReason = localizedError.failureReason
        self.helpAnchor = localizedError.helpAnchor
        self.recoverySuggestion = localizedError.recoverySuggestion
    }
    
    public init?(_ localizedError: LocalizedError?) {
        guard let localizedError = localizedError else {
            return nil
        }
        self.init(localizedError)
    }
}

extension DosingDecisionObject: Encodable {
    public func encode(to encoder: Encoder) throws {
        try EncodableDosingDecisionObject(self).encode(to: encoder)
    }
}

fileprivate struct EncodableDosingDecisionObject: Encodable {
    var data: StoredDosingDecision
    var date: Date
    var modificationCounter: Int64

    init(_ object: DosingDecisionObject) throws {
        self.data = try PropertyListDecoder().decode(StoredDosingDecision.self, from: object.data)
        self.date = object.date
        self.modificationCounter = object.modificationCounter
    }
}

// MARK: - Critical Event Log Export

extension DosingDecisionStore: CriticalEventLog {
    public var exportName: String { "DosingDecisions.json" }

    public func export(startDate: Date, endDate: Date, to stream: OutputStream, progress: Progress) -> Error? {
        let encoder = JSONStreamEncoder(stream: stream)

        var error = export(startDate: startDate, endDate: endDate, using: encoder.encode, progress: progress)

        if let closeError = encoder.close(), error == nil {
            error = closeError
        }

        return error
    }
}

// MARK: - Core Data (Bulk) - TEST ONLY

extension DosingDecisionStore {
    public func addStoredDosingDecisions(dosingDecisions: [StoredDosingDecision], completion: @escaping (Error?) -> Void) {
        let dosingDecisionDatas: [StoredDosingDecisionData] = dosingDecisions.compactMap { dosingDecision in
            guard let data = encodeDosingDecision(dosingDecision) else {
                return nil
            }
            return StoredDosingDecisionData(date: dosingDecision.date, data: data)
        }
        addStoredDosingDecisionDatas(dosingDecisionDatas: dosingDecisionDatas, completion: completion)
    }
}
