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

    // MARK: - Reservoir data

    private var persistenceController: PersistenceController! = nil

    private var recentReservoirValues: [Reservoir] = []

    private var recentReservoirValuesPredicate: NSPredicate {
        let calendar = NSCalendar.currentCalendar()
        let startDate = min(calendar.startOfDayForDate(NSDate()), NSDate(timeIntervalSinceNow: -insulinActionDuration))
        let predicate = NSPredicate(format: "date >= %@ && pumpID = %@", startDate, pumpID)

        return predicate
    }

    public func addReservoirValue(unitVolume: Double, atDate date: NSDate, rawData: NSData?) {

        let reservoir = Reservoir.insertNewObjectInContext(persistenceController.managedObjectContext)

        reservoir.volume = unitVolume
        reservoir.date = date
        reservoir.raw = rawData
        reservoir.pumpID = pumpID

        persistenceController.save { (error) -> Void in
            // TODO: Handle error
            self.recentReservoirValues.insert(reservoir, atIndex: 0)

            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.ReservoirValuesDidUpdateNotification, object: self)
        }
    }

    public func getRecentReservoirValues(resultsHandler: ([ReservoirValue]) -> Void) {
        if recentReservoirValues.count == 0, case .Ready = readyState {
            do {
                recentReservoirValues += try Reservoir.objectsInContext(persistenceController.managedObjectContext, predicate: recentReservoirValuesPredicate, sortedBy: "date", ascending: false)
            } catch {
            }
        }

        resultsHandler(recentReservoirValues.map({ $0 as ReservoirValue}))
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

        if let index = recentReservoirValues.indexOf(object) {
            recentReservoirValues.removeAtIndex(index)
        }
    }

    public func save() {
        persistenceController.save({ (error) -> Void in
            // Log the error?

        })
    }
}
