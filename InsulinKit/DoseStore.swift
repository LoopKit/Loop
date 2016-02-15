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


public protocol DoseStoreDelegate: class {
    func doseStoreReadyStateDidChange(doseStore: DoseStore)

    func doseStoreDidError(error: DoseStore.Error)
}


public class DoseStore {

    /// Notification posted when reservoir data was modifed.
    public static let ReservoirValuesDidUpdateNotification = "com.loudnate.InsulinKit.ReservoirValuesDidUpdateNotification"

    public enum ReadyState {
        case Initializing
        case Ready
        case Failed(ErrorType)
    }

    public var readyState = ReadyState.Initializing {
        didSet {
            delegate?.doseStoreReadyStateDidChange(self)
        }
    }

    public enum Error: ErrorType {
        case InitializationError(description: String, recoverySuggestion: String)
        case PersistenceError(description: String, recoverySuggestion: String)
        case FetchError(description: String, recoverySuggestion: String?)
    }

    public let pumpID: String

    public let insulinActionDuration = NSTimeInterval(hours: 4)

    public var basalProfile: BasalRateSchedule {
        didSet {
            clearDoseCache()
        }
    }

    public weak var delegate: DoseStoreDelegate?

    public init(pumpID: String, basalProfile: BasalRateSchedule) {
        self.pumpID = pumpID
        self.basalProfile = basalProfile

        persistenceController = PersistenceController(readyCallback: { [unowned self] (error) -> Void in
            if let error = error {
                self.readyState = .Failed(error)
                self.delegate?.doseStoreDidError(.InitializationError(description: error.description, recoverySuggestion: error.recoverySuggestion))
            } else {
                self.readyState = .Ready
            }
        })
    }

    public func save() {
        persistenceController.save({ (error) -> Void in
            if let error = error {
                self.delegate?.doseStoreDidError(.PersistenceError(description: error.description, recoverySuggestion: error.recoverySuggestion))
            }
        })
    }

    // MARK: - Reservoir data

    private var persistenceController: PersistenceController! = nil

    private var recentReservoirObjectsCache: [Reservoir]?

    private var recentReservoirNormalizedDoseEntriesCache: [DoseEntry]?

    private var recentReservoirDoseEntriesCache: [DoseEntry]?

    private var recentReservoirValuesMinDate: NSDate {
        let calendar = NSCalendar.currentCalendar()

        return min(calendar.startOfDayForDate(NSDate()), NSDate(timeIntervalSinceNow: -insulinActionDuration - NSTimeInterval(minutes: 5)))
    }

    private var recentReservoirValuesPredicate: NSPredicate {
        let startDate = recentReservoirValuesMinDate
        let predicate = NSPredicate(format: "date >= %@ && pumpID = %@", startDate, pumpID)

        return predicate
    }

    // TODO: Add a completion handler to handle errors
    public func addReservoirValue(unitVolume: Double, atDate date: NSDate, rawData: NSData?) {

        let reservoir = Reservoir.insertNewObjectInContext(persistenceController.managedObjectContext)

        reservoir.volume = unitVolume
        reservoir.date = date
        reservoir.raw = rawData
        reservoir.pumpID = pumpID

        if recentReservoirObjectsCache != nil {
            let predicate = recentReservoirValuesPredicate

            recentReservoirObjectsCache = recentReservoirObjectsCache!.filter { predicate.evaluateWithObject($0) }

            if recentReservoirDoseEntriesCache != nil {
                let minEndDate = recentReservoirValuesMinDate

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
                self.delegate?.doseStoreDidError(.PersistenceError(description: error.description, recoverySuggestion: error.recoverySuggestion))
            }

            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.ReservoirValuesDidUpdateNotification, object: self)
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

        if recentReservoirObjectsCache == nil, case .Ready = readyState {
            do {
                try purgeReservoirObjects()

                var recentReservoirObjects: [Reservoir] = []

                recentReservoirObjects += try Reservoir.objectsInContext(persistenceController.managedObjectContext, predicate: recentReservoirValuesPredicate, sortedBy: "date", ascending: false)

                self.recentReservoirObjectsCache = recentReservoirObjects
            } catch let fetchError as NSError {
                error = .FetchError(description: fetchError.localizedDescription, recoverySuggestion: fetchError.localizedRecoverySuggestion)
                delegate?.doseStoreDidError(error!)
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
        if recentReservoirNormalizedDoseEntriesCache == nil, case .Ready = readyState {
            getRecentReservoirDoseEntries { (doses, error) -> Void in
                self.recentReservoirNormalizedDoseEntriesCache = InsulinMath.normalize(doses, againstBasalSchedule: self.basalProfile)

                resultsHandler(doses: self.recentReservoirNormalizedDoseEntriesCache ?? [], error: error)
            }
        } else {
            resultsHandler(doses: recentReservoirNormalizedDoseEntriesCache ?? [], error: nil)
        }
    }

    public func deleteReservoirValue(value: ReservoirValue) throws {
        var deletedObjects = [Reservoir]()

        if let object = value as? Reservoir {
            deleteReservoirObject(object)
            deletedObjects.append(object)
        } else {
            // TODO: Unecessary case handling?
            let predicate = NSPredicate(format: "date = %@ && pumpID = %@", value.startDate, pumpID)

            for object in try Reservoir.objectsInContext(persistenceController.managedObjectContext, predicate: predicate) {
                deleteReservoirObject(object)
                deletedObjects.append(object)
            }
        }

        clearDoseCache()

        NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.ReservoirValuesDidUpdateNotification, object: self)
    }

    private func deleteReservoirObject(object: Reservoir) {
        persistenceController.managedObjectContext.deleteObject(object)

        if let index = recentReservoirObjectsCache?.indexOf(object) {
            recentReservoirObjectsCache!.removeAtIndex(index)
        }
    }

    private func purgeReservoirObjects() throws {
        let predicate = NSCompoundPredicate(notPredicateWithSubpredicate: recentReservoirValuesPredicate)
        let fetchRequest = Reservoir.fetchRequest(persistenceController.managedObjectContext, predicate: predicate)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

        deleteRequest.resultType = .ResultTypeCount

        if let result = try persistenceController.managedObjectContext.executeRequest(deleteRequest) as? NSBatchDeleteResult, count = result.result as? Int where count > 0 {
            recentReservoirObjectsCache?.removeAll()
            persistenceController.managedObjectContext.reset()
        }
    }

    // MARK: Math

    private func clearDoseCache() {
        recentReservoirDoseEntriesCache = nil
        recentReservoirNormalizedDoseEntriesCache = nil

        clearCalculationCache()
    }

    private func clearCalculationCache() {
        insulinOnBoardCache = nil
    }

    private var insulinOnBoardCache: [InsulinValue]?

    public func insulinOnBoardAtDate(date: NSDate, resultHandler: (InsulinValue?) -> Void) {
        if insulinOnBoardCache == nil {
            getRecentNormalizedReservoirDoseEntries { (doses, error) -> Void in
                if error == nil {
                    self.insulinOnBoardCache = InsulinMath.insulinOnBoardForDoses(doses, actionDuration: self.insulinActionDuration)
                }

                resultHandler(self.insulinOnBoardCache?.closestToDate(date))
            }
        } else {
            resultHandler(insulinOnBoardCache?.closestToDate(date))
        }
    }

    public func getTotalRecentUnitsDelivered(resultHandler: (Double) -> Void) {
        getRecentReservoirDoseEntries { (doses, error) -> Void in
            resultHandler(InsulinMath.totalDeliveryForDoses(doses))
        }
    }
}
