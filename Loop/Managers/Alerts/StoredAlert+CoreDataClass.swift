//
//  StoredAlert+CoreDataClass.swift
//  Loop
//
//  Created by Rick Pasetto on 5/22/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//
//

import Foundation
import CoreData


public class StoredAlert: NSManagedObject {
    var hasUpdatedModificationCounter: Bool { changedValues().keys.contains("modificationCounter") }

    func updateModificationCounter() { setPrimitiveValue(managedObjectContext!.modificationCounter!, forKey: "modificationCounter") }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        updateModificationCounter()
    }

    public override func willSave() {
        if isUpdated && !hasUpdatedModificationCounter {
            updateModificationCounter()
        }
        super.willSave()
    }
}
