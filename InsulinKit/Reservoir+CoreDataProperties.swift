//
//  Reservoir+CoreDataProperties.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Reservoir {

    @NSManaged var date: NSDate!
    @NSManaged var raw: NSData?
    @NSManaged var primitiveVolume: NSNumber?
    @NSManaged var createdAt: NSDate!
    @NSManaged var pumpID: String!

}
