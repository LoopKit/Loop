//
//  NightscoutUploader.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import CarbKit
import CoreData
import InsulinKit
import MinimedKit
import NightscoutUploadKit


extension NightscoutUploader: CarbStoreSyncDelegate {
    public func carbStore(_ carbStore: CarbStore, hasEntriesNeedingUpload entries: [CarbEntry], withCompletion completionHandler: @escaping (_ uploadedObjects: [String]) -> Void) {

        let nsCarbEntries = entries.map({ MealBolusNightscoutTreatment(carbEntry: $0)})

        upload(nsCarbEntries) { (result) in
            switch result {
            case .success(let ids):
                // Pass new ids back
                completionHandler(ids)
            case .failure:
                completionHandler([])
            }
        }
    }

    public func carbStore(_ carbStore: CarbStore, hasModifiedEntries entries: [CarbEntry], withCompletion completionHandler: @escaping (_ uploadedObjects: [String]) -> Void) {

        let nsCarbEntries = entries.map({ MealBolusNightscoutTreatment(carbEntry: $0)})

        modifyTreatments(nsCarbEntries) { (error) in
            if error != nil {
                completionHandler([])
            } else {
                completionHandler(entries.map { $0.externalId ?? "" } )
            }
        }
    }

    public func carbStore(_ carbStore: CarbStore, hasDeletedEntries ids: [String], withCompletion completionHandler: @escaping ([String]) -> Void) {

        deleteTreatmentsById(ids) { (error) in
            if error != nil {
                completionHandler([])
            } else {
                completionHandler(ids)
            }
        }
    }
}


extension NightscoutUploader {
    func upload(_ events: [PersistedPumpEvent], from pumpModel: PumpModel, completion: @escaping (NightscoutUploadKit.Either<[NSManagedObjectID], Error>) -> Void) {
        var objectIDs = [NSManagedObjectID]()
        var timestampedPumpEvents = [TimestampedHistoryEvent]()

        for event in events {
            objectIDs.append(event.objectID)

            if let raw = event.raw, raw.count > 0, let type = MinimedKit.PumpEventType(rawValue: raw[0])?.eventType, let pumpEvent = type.init(availableData: raw, pumpModel: pumpModel) {
                timestampedPumpEvents.append(TimestampedHistoryEvent(pumpEvent: pumpEvent, date: event.date))
            }
        }

        let nsEvents = NightscoutPumpEvents.translate(timestampedPumpEvents, eventSource: "loop://\(UIDevice.current.name)", includeCarbs: false)

        self.upload(nsEvents) { (result) in
            switch result {
            case .success( _):
                completion(.success(objectIDs))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
