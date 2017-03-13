//
//  NightscoutUploader.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import CarbKit
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
