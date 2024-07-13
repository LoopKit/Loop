//
//  AlertStore.swift
//  Loop
//
//  Created by Rick Pasetto on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreData
import LoopKit

public protocol AlertStoreDelegate: AnyObject {
    /**
     Informs the delegate that the alert store has updated alert data.

     - Parameter alertStore: The alert store that has updated alert data.
     */
    func alertStoreHasUpdatedAlertData(_ alertStore: AlertStore)
}

public class AlertStore {
    public weak var delegate: AlertStoreDelegate?

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
        self.managedObjectContext.performAndWait {
            _ = StoredAlert(from: alert, context: self.managedObjectContext, issuedDate: date)
            do {
                try self.managedObjectContext.save()
                self.log.default("Recorded alert: %{public}@", alert.identifier.value)
                self.purgeExpired()
                self.delegate?.alertStoreHasUpdatedAlertData(self)
                completion?(.success)
            } catch {
                self.log.error("Could not store alert: %{public}@, %{public}@", alert.identifier.value, String(describing: error))
                completion?(.failure(error))
            }
        }
    }

    public func recordRetractedAlert(_ alert: Alert, at date: Date, completion: ((Result<Void, Error>) -> Void)? = nil) {
        self.managedObjectContext.performAndWait {
            let storedAlert = StoredAlert(from: alert, context: self.managedObjectContext, issuedDate: date)
            storedAlert.retractedDate = date
            do {
                try self.managedObjectContext.save()
                self.log.default("Recorded retracted alert: %{public}@", alert.identifier.value)
                self.purgeExpired()
                self.delegate?.alertStoreHasUpdatedAlertData(self)
                completion?(.success)
            } catch {
                self.log.error("Could not store retracted alert: %{public}@, %{public}@", alert.identifier.value, String(describing: error))
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

    public func lookupAllMatching(identifier: Alert.Identifier, completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        managedObjectContext.perform {
            do {
                let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                let predicates = [
                    NSPredicate(format: "managerIdentifier = %@", identifier.managerIdentifier),
                    NSPredicate(format: "alertIdentifier = %@", identifier.alertIdentifier),
                ]
                fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "modificationCounter", ascending: true) ]
                let result = try self.managedObjectContext.fetch(fetchRequest)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func lookupAllUnretracted(managerIdentifier: String? = nil, completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        managedObjectContext.perform {
            do {
                let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                var predicates = [
                    NSPredicate(format: "retractedDate == nil"),
                ]
                if let managerIdentifier = managerIdentifier {
                    predicates.insert(NSPredicate(format: "managerIdentifier = %@", managerIdentifier), at: 0)
                }
                fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "modificationCounter", ascending: true) ]
                let result = try self.managedObjectContext.fetch(fetchRequest)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func lookupAllUnacknowledgedUnretracted(managerIdentifier: String? = nil, filteredByTriggers triggersStoredType: [AlertTriggerStoredType]? = nil, completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        managedObjectContext.perform {
            do {
                let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                var predicates = [
                    NSPredicate(format: "acknowledgedDate == nil"),
                    NSPredicate(format: "retractedDate == nil"),
                ]
                if let managerIdentifier = managerIdentifier {
                    predicates.insert(NSPredicate(format: "managerIdentifier = %@", managerIdentifier), at: 0)
                }
                if let triggersStoredType = triggersStoredType {
                    var triggerPredicates: [NSPredicate] = []
                    for triggerStoredType in triggersStoredType {
                        triggerPredicates.append(NSPredicate(format: "triggerType == %d", triggerStoredType))
                    }
                    let triggerFilterPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: triggerPredicates)
                    predicates.append(triggerFilterPredicate)
                }
                fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "modificationCounter", ascending: true) ]
                let result = try self.managedObjectContext.fetch(fetchRequest)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    public func lookupAllAcknowledgedUnretractedRepeatingAlerts(completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        managedObjectContext.perform {
            do {
                let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                let repeatingTrigger = Alert.Trigger.repeating(repeatInterval: 0)
                fetchRequest.predicate =  NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "acknowledgedDate != nil"),
                    NSPredicate(format: "retractedDate == nil"),
                    NSPredicate(format: "triggerType == \(repeatingTrigger.storedType)")
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
        managedObjectContext.performAndWait {
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
        managedObjectContext.performAndWait {
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
        self.delegate?.alertStoreHasUpdatedAlertData(self)
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

    // Must be invoked within NSManagedObjectContext perform or performAndWait block
    private func purgeExpired() {
        purge(before: expireDate)
    }

    func purge(before date: Date, completion: (Error?) -> Void) {
        var error: Error?
        self.managedObjectContext.performAndWait {
            error = purge(before: date)
        }
        completion(error)
    }

    @discardableResult
    func purge(before date: Date) -> Error? {
        do {
            let fetchRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "issuedDate < %@", date as NSDate)
            let count = try self.managedObjectContext.deleteObjects(matching: fetchRequest)
            self.log.info("Purged %d StoredAlerts", count)
            return nil
        } catch let error {
            self.log.error("Unable to purge StoredAlerts: %{public}@", String(describing: error))
            return error
        }
    }
}

// MARK: Query Support

public protocol QueryFilter {
    var predicate: NSPredicate? { get }
}

extension AlertStore {

    public struct QueryAnchor: RawRepresentable, Equatable {
        public typealias RawValue = [String: Any]

        internal var modificationCounter: Int64

        public init() {
            self.modificationCounter = 0
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

    public struct SinceDateFilter: QueryFilter {
        public let predicateExpressionNotYetExpired: String
        public let date: Date
        public let excludingFutureAlerts: Bool
        public let now: Date
        public var predicate: NSPredicate? {
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

    public enum AlertQueryResult {
        case success(QueryAnchor, [SyncAlertObject])
        case failure(Error)
    }

    func executeQuery(fromQueryAnchor queryAnchor: QueryAnchor? = nil, since date: Date, excludingFutureAlerts: Bool = true, now: Date = Date(), limit: Int, completion: @escaping (AlertQueryResult) -> Void) {
        let sinceDateFilter = SinceDateFilter(predicateExpressionNotYetExpired: predicateExpressionNotYetExpired,
                                              date: date,
                                              excludingFutureAlerts: excludingFutureAlerts,
                                              now: now)
        executeAlertQuery(fromQueryAnchor: queryAnchor, queryFilter: sinceDateFilter, limit: limit, completion: completion)
    }

    func executeAlertQuery(fromQueryAnchor queryAnchor: QueryAnchor?, queryFilter: QueryFilter? = nil, limit: Int, completion: @escaping (AlertQueryResult) -> Void) {
        var queryAnchor = queryAnchor ?? QueryAnchor()
        var queryResult = [SyncAlertObject]()
        var queryError: Error?

        guard limit > 0 else {
            completion(.success(queryAnchor, []))
            return
        }

        self.managedObjectContext.performAndWait {
            let storedRequest: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()

            let queryAnchorPredicate = NSPredicate(format: "modificationCounter > %d", queryAnchor.modificationCounter)
            if let queryFilterPredicate = queryFilter?.predicate {
                storedRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [queryAnchorPredicate, queryFilterPredicate])
            } else {
                storedRequest.predicate = queryAnchorPredicate
            }
            storedRequest.sortDescriptors = [NSSortDescriptor(key: "modificationCounter", ascending: true)]
            storedRequest.fetchLimit = limit

            do {
                let stored = try self.managedObjectContext.fetch(storedRequest)
                if let modificationCounter = stored.max(by: { $0.modificationCounter < $1.modificationCounter })?.modificationCounter {
                    queryAnchor.modificationCounter = modificationCounter
                }
                queryResult.append(contentsOf: stored.compactMap { try? SyncAlertObject(managedObject: $0) })
            } catch let error {
                queryError = error
                return
            }
        }

        if let queryError = queryError {
            completion(.failure(queryError))
            return
        }

        completion(.success(queryAnchor, queryResult))
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

    public func export(startDate: Date, endDate: Date, to stream: DataOutputStream, progress: Progress) -> Error? {
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
        let syncIdentifier: UUID
    }

    func addAlerts(alerts: [DatedAlert]) -> Error? {
        guard !alerts.isEmpty else {
            return nil
        }

        var error: Error?

        self.managedObjectContext.performAndWait {
            for alert in alerts {
                let storedAlert = StoredAlert(from: alert.alert, context: self.managedObjectContext, issuedDate: alert.date, syncIdentifier: alert.syncIdentifier)
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

        self.delegate?.alertStoreHasUpdatedAlertData(self)

        self.log.info("Added %d StoredAlerts", alerts.count)
        return nil
    }
}
