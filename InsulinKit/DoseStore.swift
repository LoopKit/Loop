//
//  DoseStore.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/27/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import CoreData


public protocol ReservoirValue {
    var startDate: NSDate { get }
    var unitVolume: Double { get }
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
            // Delegate: ReadyStateDidChange?
        }
    }

    public let pumpID: String

    public let insulinActionDuration = NSTimeInterval(hours: 4)

    public init(pumpID: String) {
        self.pumpID = pumpID

        persistenceController = PersistenceController(readyCallback: { [unowned self] (error) -> Void in
            if let error = error {
                self.readyState = .Failed(error)
            } else {
                self.readyState = .Ready
            }
        })
    }

    public func save() {
        persistenceController.save({ (error) -> Void in
            // Log the error?

            if let error = error {
                print(error)
            }
        })
    }

    // MARK: - Reservoir data

    private var persistenceController: PersistenceController! = nil

    private var recentReservoirObjectsCache: [Reservoir]?

    private var recentReservoirDoseEntriesCache: [DoseEntry]?

    private var recentReservoirValuesMinDate: NSDate {
        let calendar = NSCalendar.currentCalendar()

        return min(calendar.startOfDayForDate(NSDate()), NSDate(timeIntervalSinceNow: -insulinActionDuration))
    }

    private var recentReservoirValuesPredicate: NSPredicate {
        let startDate = recentReservoirValuesMinDate
        let predicate = NSPredicate(format: "date >= %@ && pumpID = %@", startDate, pumpID)

        return predicate
    }

    public func addReservoirValue(unitVolume: Double, atDate date: NSDate, rawData: NSData?) {

        let reservoir = Reservoir.insertNewObjectInContext(persistenceController.managedObjectContext)

        reservoir.volume = unitVolume
        reservoir.date = date
        reservoir.raw = rawData
        reservoir.pumpID = pumpID

        if recentReservoirObjectsCache != nil {
            let predicate = recentReservoirValuesPredicate

            for (index, value) in recentReservoirObjectsCache!.reverse().enumerate() {
                if predicate.evaluateWithObject(value) {
                    break
                } else {
                    recentReservoirObjectsCache!.removeAtIndex(index)
                }
            }

            if recentReservoirDoseEntriesCache != nil {
                let minEndDate = recentReservoirValuesMinDate

                for (index, entry) in recentReservoirDoseEntriesCache!.reverse().enumerate() {
                    if entry.endDate >= minEndDate {
                        break
                    } else {
                        recentReservoirDoseEntriesCache!.removeAtIndex(index)
                    }
                }

                var newValues: [Reservoir] = []

                if let previousValue = recentReservoirObjectsCache?.first {
                    newValues.append(previousValue)
                }

                newValues.append(reservoir)

                recentReservoirDoseEntriesCache! += InsulinMath.doseEntriesFromReservoirValues(newValues)
            }

            recentReservoirObjectsCache!.insert(reservoir, atIndex: 0)
        }

        persistenceController.save { (error) -> Void in
            // TODO: Handle error

            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.ReservoirValuesDidUpdateNotification, object: self)
        }
    }

    /**
     Fetches recent reservoir values

     - parameter resultsHandler: A closure called when the results are ready. This closure takes two arguments:
        - objects: An array of reservoir objects in reverse-chronological order
        - error:   An error object explaining why the results could not be fetched
     */
    public func getRecentReservoirValues(resultsHandler: (values: [ReservoirValue], error: ErrorType?) -> Void) {
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
    private func getRecentReservoirObjects(resultsHandler: (objects: [Reservoir], error: ErrorType?) -> Void) {
        var error: ErrorType?

        if recentReservoirObjectsCache == nil, case .Ready = readyState {
            do {
                try purgeReservoirObjects()

                var recentReservoirObjects: [Reservoir] = []

                recentReservoirObjects += try Reservoir.objectsInContext(persistenceController.managedObjectContext, predicate: recentReservoirValuesPredicate, sortedBy: "date", ascending: false)

                self.recentReservoirObjectsCache = recentReservoirObjects
            } catch let fetchError {
                error = fetchError
            }
        }

        resultsHandler(objects: recentReservoirObjectsCache ?? [], error: error)
    }

    private func getRecentReservoirDoseEntries(resultsHandler: (doses: [DoseEntry], error: ErrorType?) -> Void) {
        if recentReservoirDoseEntriesCache == nil, case .Ready = readyState {
            getRecentReservoirObjects { (reservoirValues, error) -> Void in
                self.recentReservoirDoseEntriesCache = InsulinMath.doseEntriesFromReservoirValues(reservoirValues.reverse())

                resultsHandler(doses: self.recentReservoirDoseEntriesCache ?? [], error: error)
            }
        } else {
            resultsHandler(doses: recentReservoirDoseEntriesCache ?? [], error: nil)
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

    public func getTotalRecentUnitsDelivered(resultHandler: (Double) -> Void) {
        getRecentReservoirDoseEntries { (doses, error) -> Void in
            resultHandler(InsulinMath.totalDeliveryForDoses(doses))
        }
    }
}
