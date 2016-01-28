//
//  PersistenceController.swift
//  Naterade
//
//  Inspired by http://martiancraft.com/blog/2015/03/core-data-stack/
//

import CoreData


class PersistenceController {

    let managedObjectContext: NSManagedObjectContext

    private let privateManagedObjectContext: NSManagedObjectContext

    init(readyCallback: (error: NSError?) -> Void) {
        managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        privateManagedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)

        initializeStack(readyCallback)
    }

    func save() throws {
        guard privateManagedObjectContext.hasChanges || managedObjectContext.hasChanges else {
            return
        }

        var error: NSError?

        managedObjectContext.performBlockAndWait { [unowned self] in
            do {
                try self.managedObjectContext.save()

                self.privateManagedObjectContext.performBlock { [unowned self] in
                    do {
                        try self.privateManagedObjectContext.save()
                    } catch let saveError as NSError {
                        NSLog("Error saving private context: %@", saveError)
                    }
                }
            } catch let saveError as NSError {
                error = saveError
            }
        }

        if let error = error {
            throw error
        }
    }

    // MARK: - 

    private func initializeStack(readyCallback: (error: NSError?) -> Void) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)) {
            var error: NSError?

            let modelURL = NSBundle(forClass: self.dynamicType).URLForResource("Model", withExtension: "momd")!
            let model = NSManagedObjectModel(contentsOfURL: modelURL)!
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

            self.privateManagedObjectContext.persistentStoreCoordinator = coordinator
            self.managedObjectContext.parentContext = self.privateManagedObjectContext

            if let  bundleIdentifier = NSBundle(forClass: self.dynamicType).bundleIdentifier,
                    documentsURL = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first?.URLByAppendingPathComponent(bundleIdentifier, isDirectory: true)
            {
                let storeURL = documentsURL.URLByAppendingPathComponent("Model.sqlite")

                do {
                    try coordinator.addPersistentStoreWithType(NSSQLiteStoreType,
                        configuration: nil,
                        URL: storeURL,
                        options: [
                            NSMigratePersistentStoresAutomaticallyOption: true,
                            NSInferMappingModelAutomaticallyOption: true
                        ]
                    )
                } catch let storeError as NSError {
                    error = storeError
                }
            } else {
                error = NSError(domain: "", code: -1, userInfo: nil)
            }

            readyCallback(error: error)
        }
    }
}

