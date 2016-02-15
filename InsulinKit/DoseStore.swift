//
//  DoseStore.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/27/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import CoreData
import LoopKit


public protocol ReservoirValue {
    var startDate: NSDate { get }
    var unitVolume: Double { get }
}


public class DoseStore {

    /// Notification posted when the ready state was modified.
    public static let ReadyStateDidChangeNotification = "com.loudnate.InsulinKit.ReadyStateDidUpdateNotification"

    /// Notification posted when reservoir data was modifed.
    public static let ReservoirValuesDidChangeNotification = "com.loudnate.InsulinKit.ReservoirValuesDidChangeNotification"

    public enum ReadyState {
        case NeedsConfiguration
        case Initializing
        case Ready
        case Failed(Error)
    }

    public var readyState = ReadyState.NeedsConfiguration {
        didSet {
            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.ReadyStateDidChangeNotification, object: self)
        }
    }

    public enum Error: ErrorType {
        case ConfigurationError
        case InitializationError(description: String, recoverySuggestion: String)
        case PersistenceError(description: String, recoverySuggestion: String?)
        case FetchError(description: String, recoverySuggestion: String?)
    }

    public var pumpID: String? {
        didSet {
            clearReservoirCache()
            configurationDidChange()
        }
    }

    public var insulinActionDuration: NSTimeInterval? {
        didSet {
            clearCalculationCache()
            configurationDidChange()
        }
    }

    public var basalProfile: BasalRateSchedule? {
        didSet {
            clearDoseCache()
            configurationDidChange()
        }
    }

    public init(pumpID: String?, insulinActionDuration: NSTimeInterval?, basalProfile: BasalRateSchedule?) {
        self.pumpID = pumpID
        self.insulinActionDuration = insulinActionDuration
        self.basalProfile = basalProfile

        configurationDidChange()
    }

    public func save(completionHandler: (error: Error?) -> Void) {
        if let persistenceController = persistenceController {
            persistenceController.save({ (error) -> Void in
                if let error = error {
                    completionHandler(error: .PersistenceError(description: error.description, recoverySuggestion: error.recoverySuggestion))
                } else {
                    completionHandler(error: nil)
                }
            })
        } else {
            completionHandler(error: .ConfigurationError)
        }
    }

    // MARK: - Reservoir data

    private func configurationDidChange() {
        if insulinActionDuration != nil && pumpID != nil {
            initializePersistenceController()
        } else {
            readyState = .NeedsConfiguration
        }
    }

    private func initializePersistenceController() {
        if persistenceController == nil, case .NeedsConfiguration = readyState {
            self.readyState = .Initializing

            persistenceController = PersistenceController(readyCallback: { [unowned self] (error) -> Void in
                if let error = error {
                    self.readyState = .Failed(.InitializationError(description: error.description, recoverySuggestion: error.recoverySuggestion))
                } else {
                    self.readyState = .Ready
                }
            })
        }
    }

    private var persistenceController: PersistenceController?

    private var recentReservoirObjectsCache: [Reservoir]?

    private var recentReservoirNormalizedDoseEntriesCache: [DoseEntry]?

    private var recentReservoirDoseEntriesCache: [DoseEntry]?

    private var recentReservoirValuesMinDate: NSDate? {
        if let insulinActionDuration = insulinActionDuration {
            let calendar = NSCalendar.currentCalendar()

            return min(calendar.startOfDayForDate(NSDate()), NSDate(timeIntervalSinceNow: -insulinActionDuration - NSTimeInterval(minutes: 5)))
        } else {
            return nil
        }
    }

    private var recentReservoirValuesPredicate: NSPredicate? {
        if let pumpID = pumpID, startDate = recentReservoirValuesMinDate {
            let predicate = NSPredicate(format: "date >= %@ && pumpID = %@", startDate, pumpID)

            return predicate
        } else {
            return nil
        }
    }

    public func addReservoirValue(unitVolume: Double, atDate date: NSDate, completionHandler: (value: ReservoirValue?, error: Error?) -> Void) {

        if let pumpID = pumpID, persistenceController = persistenceController {
            let reservoir = Reservoir.insertNewObjectInContext(persistenceController.managedObjectContext)

            reservoir.volume = unitVolume
            reservoir.date = date
            reservoir.pumpID = pumpID

            if recentReservoirObjectsCache != nil, let predicate = recentReservoirValuesPredicate {
                recentReservoirObjectsCache = recentReservoirObjectsCache!.filter { predicate.evaluateWithObject($0) }

                if recentReservoirDoseEntriesCache != nil, let
                    basalProfile = basalProfile,
                    minEndDate = recentReservoirValuesMinDate
                {
                    recentReservoirDoseEntriesCache = recentReservoirDoseEntriesCache!.filter { $0.endDate >= minEndDate }

                    var newValues: [Reservoir] = []

                    if let previousValue = recentReservoirObjectsCache?.first {
                        newValues.append(previousValue)
                    }

                    newValues.append(reservoir)

                    let newDoseEntries = InsulinMath.doseEntriesFromReservoirValues(newValues)

                    recentReservoirDoseEntriesCache! += newDoseEntries

                    if recentReservoirNormalizedDoseEntriesCache != nil {
                        recentReservoirNormalizedDoseEntriesCache = recentReservoirNormalizedDoseEntriesCache!.filter { $0.endDate > minEndDate }

                        recentReservoirNormalizedDoseEntriesCache! += InsulinMath.normalize(newDoseEntries, againstBasalSchedule: basalProfile)
                    }
                }

                recentReservoirObjectsCache!.insert(reservoir, atIndex: 0)
            }

            clearCalculationCache()

            persistenceController.save { (error) -> Void in
                if let error = error {
                    completionHandler(value: reservoir, error: .PersistenceError(description: error.description, recoverySuggestion: error.recoverySuggestion))
                } else {
                    completionHandler(value: reservoir, error: nil)
                }

                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.ReservoirValuesDidChangeNotification, object: self)
            }
        } else {
            completionHandler(value: nil, error: .ConfigurationError)
        }
    }

    /**
     Fetches recent reservoir values

     - parameter resultsHandler: A closure called when the results are ready. This closure takes two arguments:
        - objects: An array of reservoir objects in reverse-chronological order
        - error:   An error object explaining why the results could not be fetched
     */
    public func getRecentReservoirValues(resultsHandler: (values: [ReservoirValue], error: Error?) -> Void) {
        getRecentReservoirObjects { (reservoirObjects, error) -> Void in
            resultsHandler(values: reservoirObjects.map({ $0 as ReservoirValue}), error: error)
        }
    }

    /**
     Note: Must be called on the main queue

     - parameter resultsHandler: A closure called when the results are ready. This closure takes two arguments:
        - objects: An array of reservoir objects
        - error:   An error object explaining why the results could not be fetched
     */
    private func getRecentReservoirObjects(resultsHandler: (objects: [Reservoir], error: Error?) -> Void) {
        var error: Error?

        if recentReservoirObjectsCache == nil {
            if case .Ready = readyState, let persistenceController = persistenceController {
                do {
                    try purgeReservoirObjects()

                    var recentReservoirObjects: [Reservoir] = []

                    recentReservoirObjects += try Reservoir.objectsInContext(persistenceController.managedObjectContext, predicate: recentReservoirValuesPredicate, sortedBy: "date", ascending: false)

                    self.recentReservoirObjectsCache = recentReservoirObjects
                } catch let fetchError as NSError {
                    error = .FetchError(description: fetchError.localizedDescription, recoverySuggestion: fetchError.localizedRecoverySuggestion)
                }
            } else {
                error = .ConfigurationError
            }
        }

        resultsHandler(objects: recentReservoirObjectsCache ?? [], error: error)
    }

    private func getRecentReservoirDoseEntries(resultsHandler: (doses: [DoseEntry], error: Error?) -> Void) {
        if recentReservoirDoseEntriesCache == nil, case .Ready = readyState {
            getRecentReservoirObjects { (reservoirValues, error) -> Void in
                self.recentReservoirDoseEntriesCache = InsulinMath.doseEntriesFromReservoirValues(reservoirValues.reverse())

                resultsHandler(doses: self.recentReservoirDoseEntriesCache ?? [], error: error)
            }
        } else {
            resultsHandler(doses: recentReservoirDoseEntriesCache ?? [], error: nil)
        }
    }

    private func getRecentNormalizedReservoirDoseEntries(resultsHandler: (doses: [DoseEntry], error: Error?) -> Void) {
        if recentReservoirNormalizedDoseEntriesCache == nil {
            if case .Ready = readyState, let basalProfile = basalProfile {
                getRecentReservoirDoseEntries { (doses, error) -> Void in
                    self.recentReservoirNormalizedDoseEntriesCache = InsulinMath.normalize(doses, againstBasalSchedule: basalProfile)

                    resultsHandler(doses: self.recentReservoirNormalizedDoseEntriesCache ?? [], error: error)
                }
            } else {
                resultsHandler(doses: recentReservoirDoseEntriesCache ?? [], error: .ConfigurationError)
            }
        } else {
            resultsHandler(doses: recentReservoirNormalizedDoseEntriesCache ?? [], error: nil)
        }
    }

    public func deleteReservoirValue(value: ReservoirValue, completionHandler: (deletedValues: [ReservoirValue], error: Error?) -> Void) {

        if case .Ready = readyState, let persistenceController = persistenceController {
            var deletedObjects = [Reservoir]()
            var error: Error?

            if let object = value as? Reservoir {
                deleteReservoirObject(object)
                deletedObjects.append(object)
            } else if let pumpID = pumpID {
                // TODO: Unecessary case handling?
                let predicate = NSPredicate(format: "date = %@ && pumpID = %@", value.startDate, pumpID)

                // TODO: Background queue
                do {
                    for object in try Reservoir.objectsInContext(persistenceController.managedObjectContext, predicate: predicate) {
                        deleteReservoirObject(object)
                        deletedObjects.append(object)
                    }
                } catch let deleteError as NSError {
                    error = .PersistenceError(description: deleteError.localizedDescription, recoverySuggestion: deleteError.localizedRecoverySuggestion)
                }
            }

            clearDoseCache()

            completionHandler(deletedValues: deletedObjects.map { $0 }, error: error)

            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.ReservoirValuesDidChangeNotification, object: self)
        } else {
            completionHandler(deletedValues: [], error: .ConfigurationError)
        }
    }

    private func deleteReservoirObject(object: Reservoir) {
        persistenceController?.managedObjectContext.deleteObject(object)

        if let index = recentReservoirObjectsCache?.indexOf(object) {
            recentReservoirObjectsCache?.removeAtIndex(index)
        }
    }

    private func purgeReservoirObjects() throws {
        if let subPredicate = recentReservoirValuesPredicate, persistenceController = persistenceController {
            let predicate = NSCompoundPredicate(notPredicateWithSubpredicate: subPredicate)
            let fetchRequest = Reservoir.fetchRequest(persistenceController.managedObjectContext, predicate: predicate)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

            deleteRequest.resultType = .ResultTypeCount

            if let result = try persistenceController.managedObjectContext.executeRequest(deleteRequest) as? NSBatchDeleteResult, count = result.result as? Int where count > 0 {
                recentReservoirObjectsCache?.removeAll()
                persistenceController.managedObjectContext.reset()
            }
        }
    }

    // MARK: Math

    private func clearReservoirCache() {
        recentReservoirObjectsCache = nil

        clearDoseCache()
    }

    private func clearDoseCache() {
        recentReservoirDoseEntriesCache = nil
        recentReservoirNormalizedDoseEntriesCache = nil

        clearCalculationCache()
    }

    private func clearCalculationCache() {
        insulinOnBoardCache = nil
    }

    private var insulinOnBoardCache: [InsulinValue]?

    public func insulinOnBoardAtDate(date: NSDate, resultHandler: (iob: InsulinValue?, error: Error?) -> Void) {
        if insulinOnBoardCache == nil {
            if let insulinActionDuration = insulinActionDuration {
                getRecentNormalizedReservoirDoseEntries { (doses, error) -> Void in
                    if error == nil {
                        self.insulinOnBoardCache = InsulinMath.insulinOnBoardForDoses(doses, actionDuration: insulinActionDuration)
                    }

                    resultHandler(iob: self.insulinOnBoardCache?.closestToDate(date), error: error)
                }
            } else {
                resultHandler(iob: nil, error: .ConfigurationError)
            }
        } else {
            resultHandler(iob: insulinOnBoardCache?.closestToDate(date), error: nil)
        }
    }

    public func getTotalRecentUnitsDelivered(resultHandler: (total: Double, error: Error?) -> Void) {
        getRecentReservoirDoseEntries { (doses, error) -> Void in
            resultHandler(total: InsulinMath.totalDeliveryForDoses(doses), error: error)
        }
    }
}
