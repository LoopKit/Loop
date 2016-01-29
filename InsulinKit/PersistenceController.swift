//
//  PersistenceController.swift
//  Naterade
//
//  Inspired by http://martiancraft.com/blog/2015/03/core-data-stack/
//

import CoreData


class PersistenceController {

    enum Error: ErrorType {
        case ConfigurationError
        case CoreDataError(NSError?)
    }

    let managedObjectContext: NSManagedObjectContext

    private let privateManagedObjectContext: NSManagedObjectContext

    init(readyCallback: (error: Error?) -> Void) {
        managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        privateManagedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)

        initializeStack(readyCallback)
    }

    func save(completionHandler: (error: Error?) -> Void) {
        managedObjectContext.performBlock { [unowned self] in
            do {
                if self.managedObjectContext.hasChanges {
                    try self.managedObjectContext.save()
                }

                self.privateManagedObjectContext.performBlock { [unowned self] in
                    do {
                        if self.privateManagedObjectContext.hasChanges {
                            try self.privateManagedObjectContext.save()
                        }

                        completionHandler(error: nil)
                    } catch let saveError as NSError {
                        completionHandler(error: .CoreDataError(saveError))
                    }
                }
            } catch let saveError as NSError {
                completionHandler(error: .CoreDataError(saveError))
            }
        }
    }

    // MARK: - 

    private func initializeStack(readyCallback: (error: Error?) -> Void) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)) {
            var error: Error?

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
                    error = .CoreDataError(storeError)
                }
            } else {
                error = .ConfigurationError
            }

            readyCallback(error: error)
        }
    }
}

