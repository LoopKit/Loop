//
//  AlertStore.swift
//  Loop
//
//  Created by Rick Pasetto on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreData
import LoopKit

public class AlertStore {
    
    public enum AlertStoreError: Error {
        case notFound
    }
    
    // Available for tests only
    let managedObjectContext: NSManagedObjectContext

    private let persistentContainer: NSPersistentContainer
        
    private let log = DiagnosticLog(category: "AlertStore")
    
    public init(storageFileURL: URL? = nil) {
        managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        managedObjectContext.automaticallyMergesChangesFromParent = true

        let storeDescription = NSPersistentStoreDescription()
        if let storageFileURL = storageFileURL {
            storeDescription.url = storageFileURL
        } else {
            storeDescription.type = NSInMemoryStoreType
        }
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true
        persistentContainer = NSPersistentContainer(name: "AlertStore")
        persistentContainer.persistentStoreDescriptions = [storeDescription]
        persistentContainer.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        managedObjectContext.persistentStoreCoordinator = persistentContainer.persistentStoreCoordinator
    }
}

// MARK: Alert Recording

extension AlertStore {
    
    public func recordIssued(alert: Alert, at date: Date = Date(), completion: ((Result<Void, Error>) -> Void)? = nil) {
        self.managedObjectContext.perform {
            _ = StoredAlert(from: alert, context: self.managedObjectContext, issuedDate: date)
            do {
                try self.managedObjectContext.save()
                self.log.default("Recorded alert: %{public}@", alert.identifier.value)
                completion?(.success)
            } catch {
                self.log.error("Could not store alert: %{public}@, %{public}@", alert.identifier.value, String(describing: error))
                completion?(.failure(error))
            }
        }
    }
    
    public func recordAcknowledgement(of identifier: Alert.Identifier, at date: Date = Date(),
                                      completion: ((Result<Void, Error>) -> Void)? = nil) {
        recordUpdateOfLatest(of: identifier, with: { $0.acknowledgedDate = date }, completion: completion)
    }
    
    public func recordRetraction(of identifier: Alert.Identifier, at date: Date = Date(),
                                 completion: ((Result<Void, Error>) -> Void)? = nil) {
        recordUpdateOfLatest(of: identifier, with: { $0.retractedDate = date }, completion: completion)
    }
    
    private func recordUpdateOfLatest(of identifier: Alert.Identifier,
                                      with block: @escaping (StoredAlert) -> Void,
                                      completion: ((Result<Void, Error>) -> Void)?) {
        self.managedObjectContext.perform {
            self.lookupLatest(identifier: identifier) {
                switch $0 {
                case .success(let object):
                    if let object = object {
                        block(object)
                        do {
                            try self.managedObjectContext.save()
                            self.log.default("Recorded alert: %{public}@", identifier.value)
                            completion?(.success)
                        } catch {
                            self.log.error("Could not store alert: %{public}@, %{public}@", identifier.value, String(describing: error))
                            completion?(.failure(error))
                        }
                    } else {
                        self.log.default("Alert not found for update: %{public}@", identifier.value)
                        completion?(.failure(AlertStoreError.notFound))
                    }
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        }
    }

    private func lookupLatest(identifier: Alert.Identifier, completion: @escaping (Result<StoredAlert?, Error>) -> Void) {
        managedObjectContext.perform {
            do {
                let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                fetchRequest.predicate = identifier.equalsPredicate
                fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "modificationCounter", ascending: false) ]
                fetchRequest.fetchLimit = 1
                let result = try self.managedObjectContext.fetch(fetchRequest)
                completion(.success(result.last))
            } catch {
                completion(.failure(error))
            }
        }
    }

}

// MARK: Query Support

public protocol QueryFilter: Equatable {
    var predicate: NSPredicate? { get }
}

extension AlertStore {
    
    public struct QueryAnchor<Filter: QueryFilter>: RawRepresentable, Equatable {
        public typealias RawValue = [String: Any]
        internal var modificationCounter: Int64
        internal var filter: Filter?
        public init() {
            self.modificationCounter = 0
        }
        init(modificationCounter: Int64? = nil, filter: Filter?) {
            self.modificationCounter = modificationCounter ?? 0
            self.filter = filter
        }
        public init?(rawValue: RawValue) {
            guard let modificationCounter = rawValue["modificationCounter"] as? Int64 else {
                return nil
            }
            self.modificationCounter = modificationCounter
        }
        public var rawValue: RawValue {
            var rawValue: RawValue = [:]
            rawValue["modificationCounter"] = modificationCounter
            return rawValue
        }
    }
    typealias QueryResult<Filter: QueryFilter> = Result<(QueryAnchor<Filter>, [StoredAlert]), Error>
    
    struct NoFilter: QueryFilter {
        let predicate: NSPredicate?
    }
    struct SinceDateFilter: QueryFilter {
        let date: Date
        var predicate: NSPredicate? { NSPredicate(format: "issuedDate >= %@", date as NSDate) }
    }
    
    func executeQuery(since date: Date, limit: Int, completion: @escaping (QueryResult<SinceDateFilter>) -> Void) {
        executeAlertQuery(from: QueryAnchor(filter: SinceDateFilter(date: date)), limit: limit, completion: completion)
    }
    
    func continueQuery<Filter: QueryFilter>(from anchor: QueryAnchor<Filter>, limit: Int, completion: @escaping (QueryResult<Filter>) -> Void) {
        executeAlertQuery(from: anchor, limit: limit, completion: completion)
    }

    private func executeAlertQuery<Filter: QueryFilter>(from anchor: QueryAnchor<Filter>, limit: Int, completion: @escaping (QueryResult<Filter>) -> Void) {
        self.managedObjectContext.perform {
            guard limit > 0 else {
                completion(.success((anchor, [])))
                return
            }
            let storedRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
            let anchorPredicate = NSPredicate(format: "modificationCounter > %d", anchor.modificationCounter)
            if let filterPredicate = anchor.filter?.predicate {
                storedRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    anchorPredicate,
                    filterPredicate
                ])
            } else {
                storedRequest.predicate = anchorPredicate
            }
            storedRequest.sortDescriptors = [NSSortDescriptor(key: "modificationCounter", ascending: true)]
            storedRequest.fetchLimit = limit
            
            do {
                let stored = try self.managedObjectContext.fetch(storedRequest)
                let modificationCounter = stored.max(by: { $0.modificationCounter < $1.modificationCounter })?.modificationCounter
                let newAnchor = QueryAnchor<Filter>(modificationCounter: modificationCounter, filter: anchor.filter)
                completion(.success((newAnchor, stored)))
            } catch let error {
                completion(.failure(error))
            }
        }
    }
    
    // At the moment, this is only used for unit testing
    internal func fetch(identifier: Alert.Identifier, completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        self.managedObjectContext.perform {
            let storedRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
            storedRequest.predicate = identifier.equalsPredicate
            do {
                let stored = try self.managedObjectContext.fetch(storedRequest)
                completion(.success(stored))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

extension Alert.Identifier {
    var equalsPredicate: NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "managerIdentifier == %@", managerIdentifier),
            NSPredicate(format: "alertIdentifier == %@", alertIdentifier)
        ])
    }
}

extension Result where Success == Void {
    static var success: Result {
        return Result.success(Void())
    }
}
