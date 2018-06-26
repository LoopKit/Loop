//
//  NightscoutUploader.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit
import NightscoutUploadKit


extension NightscoutUploader: CarbStoreSyncDelegate {
    static let logger = DiagnosticLogger.shared.forCategory("NightscoutUploader")

    public func carbStore(_ carbStore: CarbStore, hasEntriesNeedingUpload entries: [StoredCarbEntry], completion: @escaping ([StoredCarbEntry]) -> Void) {
        var created = [StoredCarbEntry]()
        var modified = [StoredCarbEntry]()

        for entry in entries {
            if entry.externalID != nil {
                modified.append(entry)
            } else {
                created.append(entry)
            }
        }

        upload(created.map { MealBolusNightscoutTreatment(carbEntry: $0) }) { (result) in
            switch result {
            case .success(let ids):
                for (index, id) in ids.enumerated() {
                    created[index].externalID = id
                    created[index].isUploaded = true
                }
                completion(created)
            case .failure(let error):
                NightscoutUploader.logger.error(error)
                completion(created)
            }
        }

        modifyTreatments(modified.map { MealBolusNightscoutTreatment(carbEntry: $0) }) { (error) in
            if let error = error {
                NightscoutUploader.logger.error(error)
            } else {
                for index in modified.startIndex..<modified.endIndex {
                    modified[index].isUploaded = true
                }
            }

            completion(modified)
        }
    }

    public func carbStore(_ carbStore: CarbStore, hasDeletedEntries entries: [DeletedCarbEntry], completion: @escaping ([DeletedCarbEntry]) -> Void) {
        var deleted = entries

        deleteTreatmentsById(deleted.map { $0.externalID }) { (error) in
            if let error = error {
                NightscoutUploader.logger.error(error)
            } else {
                for index in deleted.startIndex..<deleted.endIndex {
                    deleted[index].isUploaded = true
                }
            }

            completion(deleted)
        }
    }
}


extension NightscoutUploader {
    func upload(_ events: [PersistedPumpEvent], fromSource source: String, completion: @escaping (NightscoutUploadKit.Either<[URL], Error>) -> Void) {
        var objectIDURLs = [URL]()
        var treatments = [NightscoutTreatment]()

        for event in events {
            guard let treatment = event.treatment(enteredBy: source) else {
                continue
            }

            objectIDURLs.append(event.objectIDURL)
            treatments.append(treatment)
        }

        self.upload(treatments) { (result) in
            switch result {
            case .success( _):
                completion(.success(objectIDURLs))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
