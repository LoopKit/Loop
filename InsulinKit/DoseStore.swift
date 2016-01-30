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

    private var persistenceController: PersistenceController! = nil

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

    public func addReservoirVolume(unitVolume: Double, atDate date: NSDate, rawData: NSData?) {

        let reservoir = Reservoir.insertNewObjectInContext(persistenceController.managedObjectContext)

        reservoir.volume = unitVolume
        reservoir.date = date
        reservoir.raw = rawData
        reservoir.pumpID = pumpID

        persistenceController.save { (error) -> Void in
            // TODO: Handle error
        }
    }

    public func deleteReservoirValue(value: ReservoirValue) throws {
        let predicate = NSPredicate(format: "date = %@ && pumpID = %@", value.startDate, pumpID)

        for object in try Reservoir.objectsInContext(persistenceController.managedObjectContext, predicate: predicate) {
            persistenceController.managedObjectContext.deleteObject(object)
        }
    }

    public func save() {
        persistenceController.save({ (error) -> Void in
            // Log the error?

        })
    }
}
