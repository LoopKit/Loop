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

    static let totalFetchLimit = 500
    
    public enum AlertStoreError: Error {
        case notFound
    }

    private enum PostUpdateAction {
        case save, delete
    }
    private typealias ManagedObjectUpdateBlock = (StoredAlert) -> PostUpdateAction
    
    // Available for tests only
    let managedObjectContext: NSManagedObjectContext

    private let persistentContainer: NSPersistentContainer

    private let expireAfter: TimeInterval

    private let log = DiagnosticLog(category: "AlertStore")

    // This is terribly inconvenient, but it turns out that executing the following expression in CoreData _differs_
    // depending on whether it is in-memory or SQLite
    private let predicateExpressionNotYetExpiredSQLite = "issuedDate + triggerInterval < %@"
    private let predicateExpressionNotYetExpiredInMemory = "CAST(issuedDate, 'NSNumber') + triggerInterval < CAST(%@, 'NSNumber')"
    private let predicateExpressionNotYetExpired: String
    
    public init(storageDirectoryURL: URL? = nil, expireAfter: TimeInterval = 24 /* hours */ * 60 /* minutes */ * 60 /* seconds */) {
        managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        managedObjectContext.automaticallyMergesChangesFromParent = true

        let storeDescription = NSPersistentStoreDescription()
        if let storageDirectoryURL = storageDirectoryURL {
            let storageFileURL = storageDirectoryURL
                .appendingPathComponent("AlertStore.sqlite")
            storeDescription.url = storageFileURL
            predicateExpressionNotYetExpired = predicateExpressionNotYetExpiredSQLite
        } else {
            storeDescription.type = NSInMemoryStoreType
            predicateExpressionNotYetExpired = predicateExpressionNotYetExpiredInMemory
        }
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true
        persistentContainer = NSPersistentContainer(name: "AlertStore")
        persistentContainer.persistentStoreDescriptions = [storeDescription]

        let group = DispatchGroup()
        group.enter()
        persistentContainer.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
            group.leave()
        }
        group.wait()

        managedObjectContext.persistentStoreCoordinator = persistentContainer.persistentStoreCoordinator

        self.expireAfter = expireAfter
    }

    public func recordIssued(alert: Alert, at date: Date = Date(), completion: ((Result<Void, Error>) -> Void)? = nil) {
        self.managedObjectContext.perform {
            _ = StoredAlert(from: alert, context: self.managedObjectContext, issuedDate: date)
            do {
                try self.managedObjectContext.save()
                self.log.default("Recorded alert: %{public}@", alert.identifier.value)
                self.purgeExpired()
                completion?(.success)
            } catch {
                self.log.error("Could not store alert: %{public}@, %{public}@", alert.identifier.value, String(describing: error))
                completion?(.failure(error))
            }
        }
    }
    
    public func recordAcknowledgement(of identifier: Alert.Identifier, at date: Date = Date(),
                                      completion: ((Result<Void, Error>) -> Void)? = nil) {
        recordUpdateOfAll(identifier: identifier,
                          addingPredicate: NSPredicate(format: "acknowledgedDate == nil"),
                          with: {
                              $0.acknowledgedDate = date
                              return .save
                          },
                          completion: completion)
    }
    
    public func recordRetraction(of identifier: Alert.Identifier, at date: Date = Date(),
                                 completion: ((Result<Void, Error>) -> Void)? = nil) {
        recordUpdateOfLatest(identifier: identifier,
                             addingPredicate: NSPredicate(format: "retractedDate == nil"),
                             with: {
                                // if the alert was retracted before it was ever shown, delete it.
                                // Note: this only applies to .delayed or .repeating alerts!
                                if let delay = $0.trigger.interval, $0.issuedDate + delay >= date {
                                    return .delete
                                } else {
                                    $0.retractedDate = date
                                    return .save
                                }
                             },
                             completion: completion)
    }
    
    public func lookupAllUnacknowledged(completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        managedObjectContext.perform {
            do {
                let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                fetchRequest.predicate =  NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "acknowledgedDate == nil"),
                    NSPredicate(format: "retractedDate == nil")
                ])
                fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "modificationCounter", ascending: true) ]
                let result = try self.managedObjectContext.fetch(fetchRequest)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

}

// MARK: Private functions

extension AlertStore {
    
    private func recordUpdateOfAll(identifier: Alert.Identifier,
                                   addingPredicate predicate: NSPredicate,
                                   with updateBlock: @escaping ManagedObjectUpdateBlock,
                                   completion: ((Result<Void, Error>) -> Void)?) {
        managedObjectContext.perform {
            self.lookupAll(identifier: identifier, predicate: predicate) {
                switch $0 {
                case .success(let objects):
                    if objects.count > 0 {
                        let result = self.update(objects: objects, with: updateBlock)
                        completion?(result)
                    } else {
                        self.log.error("Alert not found for update: %{public}@", identifier.value)
                        completion?(.failure(AlertStoreError.notFound))
                    }
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        }
    }
    
    private func recordUpdateOfLatest(identifier: Alert.Identifier,
                                      addingPredicate predicate: NSPredicate,
                                      with updateBlock: @escaping ManagedObjectUpdateBlock,
                                      completion: ((Result<Void, Error>) -> Void)?) {
        managedObjectContext.perform {
            self.lookupLatest(identifier: identifier, predicate: predicate) {
                switch $0 {
                case .success(let object):
                    if let object = object {
                        let result = self.update(objects: [object], with: updateBlock)
                        completion?(result)
                    } else {
                        self.log.error("Alert not found for update: %{public}@", identifier.value)
                        completion?(.failure(AlertStoreError.notFound))
                    }
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        }
    }
    
    private func update(objects: [StoredAlert], with updateBlock: @escaping ManagedObjectUpdateBlock) -> Result<Void, Error> {
        objects.forEach { alert in
            let shouldDelete = updateBlock(alert) == .delete
            if shouldDelete {
                self.managedObjectContext.delete(alert)
            }
            self.log.default("%{public}@ alert: %{public}@", shouldDelete ? "Deleted" : "Recorded", alert.identifier.value)
        }
        do {
            try self.managedObjectContext.save()
        } catch {
            return .failure(error)
        }
        self.purgeExpired()
        return .success
    }
    

    private func lookupAll(identifier: Alert.Identifier, predicate: NSPredicate, completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        managedObjectContext.perform {
            do {
                let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    identifier.equalsPredicate,
                    predicate
                ])
                fetchRequest.fetchLimit = Self.totalFetchLimit
                let result = try self.managedObjectContext.fetch(fetchRequest)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func lookupLatest(identifier: Alert.Identifier, predicate: NSPredicate, completion: @escaping (Result<StoredAlert?, Error>) -> Void) {
        managedObjectContext.perform {
            do {
                let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    identifier.equalsPredicate,
                    predicate
                ])
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

// MARK: Alert Purging

extension AlertStore {
    var expireDate: Date {
        return Date(timeIntervalSinceNow: -expireAfter)
    }

    private func purgeExpired() {
        purge(before: expireDate)
    }

    func purge(before date: Date, completion: ((Error?) -> Void)? = nil) {
        do {
            let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "issuedDate < %@", date as NSDate)
            let count = try self.managedObjectContext.deleteObjects(matching: fetchRequest)
            self.log.info("Purged %d StoredAlerts", count)
            completion?(nil)
        } catch let error {
            self.log.error("Unable to purge StoredAlerts: %{public}@", String(describing: error))
            completion?(error)
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
        let predicateExpressionNotYetExpired: String
        let date: Date
        let excludingFutureAlerts: Bool
        let now: Date
        var predicate: NSPredicate? {
            let datePredicate = NSPredicate(format: "issuedDate >= %@", date as NSDate)
            // This predicate only _includes_ a record if it either has no interval (i.e. is 'immediate')
            // _or_ it is a 'delayed' or 'repeating' alert (a non-nil triggerInterval) whose time has already come
            // (that is, issuedDate + triggerInterval < now).
            let futurePredicate = NSPredicate(format: "triggerInterval == nil OR \(predicateExpressionNotYetExpired)", now as NSDate)
            return excludingFutureAlerts ?
                NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, futurePredicate])
                : datePredicate
        }
    }

    func executeQuery(since date: Date, excludingFutureAlerts: Bool = true, now: Date = Date(), limit: Int, completion: @escaping (QueryResult<SinceDateFilter>) -> Void) {
        let sinceDateFilter = SinceDateFilter(predicateExpressionNotYetExpired: predicateExpressionNotYetExpired,
                                              date: date,
                                              excludingFutureAlerts: excludingFutureAlerts,
                                              now: now)
        executeAlertQuery(from: QueryAnchor(filter: sinceDateFilter), limit: limit, completion: completion)
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
    internal func fetch(identifier: Alert.Identifier? = nil, completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        self.managedObjectContext.perform {
            let storedRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
            storedRequest.predicate = identifier?.equalsPredicate
            storedRequest.sortDescriptors = [NSSortDescriptor(key: "modificationCounter", ascending: true)]
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

extension Alert.Trigger {
    var interval: TimeInterval? {
        switch self {
        case .delayed(let interval): return interval
        case .repeating(let repeatInterval): return repeatInterval
        case .immediate: return nil
        }
    }
}

extension Result where Success == Void {
    static var success: Result {
        return Result.success(Void())
    }
}

// MARK: - Critical Event Log Export

extension AlertStore: CriticalEventLog {
    private var exportProgressUnitCountPerObject: Int64 { 1 }
    private var exportFetchLimit: Int { Int(criticalEventLogExportProgressUnitCountPerFetch / exportProgressUnitCountPerObject) }

    public var exportName: String { "Alerts.json" }

    public func exportProgressTotalUnitCount(startDate: Date, endDate: Date? = nil) -> Result<Int64, Error> {
        var result: Result<Int64, Error>?

        self.managedObjectContext.performAndWait {
            do {
                let request: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                request.predicate = self.exportDatePredicate(startDate: startDate, endDate: endDate)

                let objectCount = try self.managedObjectContext.count(for: request)
                result = .success(Int64(objectCount) * exportProgressUnitCountPerObject)
            } catch let error {
                result = .failure(error)
            }
        }

        return result!
    }

    public func export(startDate: Date, endDate: Date, to stream: OutputStream, progress: Progress) -> Error? {
        let encoder = JSONStreamEncoder(stream: stream)
        var modificationCounter: Int64 = 0
        var fetching = true
        var error: Error?

        while fetching && error == nil {
            self.managedObjectContext.performAndWait {
                do {
                    guard !progress.isCancelled else {
                        throw CriticalEventLogError.cancelled
                    }

                    let request: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [NSPredicate(format: "modificationCounter > %d", modificationCounter),
                                                                                            self.exportDatePredicate(startDate: startDate, endDate: endDate)])
                    request.sortDescriptors = [NSSortDescriptor(key: "modificationCounter", ascending: true)]
                    request.fetchLimit = self.exportFetchLimit

                    let objects = try self.managedObjectContext.fetch(request)
                    if objects.isEmpty {
                        fetching = false
                        return
                    }

                    try encoder.encode(objects)

                    modificationCounter = objects.last!.modificationCounter

                    progress.completedUnitCount += Int64(objects.count) * exportProgressUnitCountPerObject
                } catch let fetchError {
                    error = fetchError
                }
            }
        }

        if let closeError = encoder.close(), error == nil {
            error = closeError
        }

        return error
    }

    private func exportDatePredicate(startDate: Date, endDate: Date? = nil) -> NSPredicate {
        var issuedDatePredicate = NSPredicate(format: "issuedDate >= %@", startDate as NSDate)
        var acknowledgedDatePredicate = NSPredicate(format: "acknowledgedDate >= %@", startDate as NSDate)
        var retractedDatePredicate = NSPredicate(format: "retractedDate >= %@", startDate as NSDate)
        if let endDate = endDate {
            issuedDatePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [issuedDatePredicate, NSPredicate(format: "issuedDate < %@", endDate as NSDate)])
            acknowledgedDatePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [acknowledgedDatePredicate, NSPredicate(format: "acknowledgedDate < %@", endDate as NSDate)])
            retractedDatePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [retractedDatePredicate, NSPredicate(format: "retractedDate < %@", endDate as NSDate)])
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: [issuedDatePredicate, acknowledgedDatePredicate, retractedDatePredicate])
    }
}

// MARK: - Core Data (Bulk) - TEST ONLY

extension AlertStore {
    struct DatedAlert {
        let date: Date
        let alert: Alert
    }

    func addAlerts(alerts: [DatedAlert]) -> Error? {
        guard !alerts.isEmpty else {
            return nil
        }

        var error: Error?

        self.managedObjectContext.performAndWait {
            for alert in alerts {
                let storedAlert = StoredAlert(from: alert.alert, context: self.managedObjectContext, issuedDate: alert.date)
                storedAlert.acknowledgedDate = alert.date
            }

            do {
                try self.managedObjectContext.save()
            } catch let saveError {
                error = saveError
            }
        }

        guard error == nil else {
            return error
        }

        self.log.info("Added %d StoredAlerts", alerts.count)
        return nil
    }
}
