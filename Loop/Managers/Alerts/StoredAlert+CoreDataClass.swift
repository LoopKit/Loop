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
import LoopKit

public class StoredAlert: NSManagedObject {
    
    var interruptionLevel: Alert.InterruptionLevel {
        get {
            willAccessValue(forKey: "interruptionLevel")
            defer { didAccessValue(forKey: "interruptionLevel") }
            return Alert.InterruptionLevel(storedValue: primitiveInterruptionLevel)!
        }
        set {
            willChangeValue(forKey: "interruptionLevel")
            defer { didChangeValue(forKey: "interruptionLevel") }
            primitiveInterruptionLevel = newValue.storedValue
        }
    }
    
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
