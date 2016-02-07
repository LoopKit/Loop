//
//  PersistenceController.swift
//  Naterade
//
//  Inspired by http://martiancraft.com/blog/2015/03/core-data-stack/
//

import CoreData


class PersistenceController {

    enum Error: ErrorType {
        case ConfigurationError(String)
        case CoreDataError(NSError)

        var description: String {
            switch self {
            case .ConfigurationError(let description):
                return description
            case .CoreDataError(let error):
                return error.localizedDescription
            }
        }

        var recoverySuggestion: String {
            switch self {
            case .ConfigurationError:
                return "Unrecoverable Error"
            case .CoreDataError(let error):
                return error.localizedRecoverySuggestion ?? "Please try again later"
            }
        }
    }

    let managedObjectContext: NSManagedObjectContext

    private let privateManagedObjectContext: NSManagedObjectContext

    init(readyCallback: (error: Error?) -> Void) {
        managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        privateManagedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)

        initializeStack(readyCallback)

        didEnterBackgroundNotificationObserver = NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationDidEnterBackgroundNotification, object: UIApplication.sharedApplication(), queue: nil, usingBlock: handleSave)
        willResignActiveNotificationObserver = NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationWillResignActiveNotification, object: UIApplication.sharedApplication(), queue: nil, usingBlock: handleSave)
        willTerminateNotificationObserver = NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationWillTerminateNotification, object: UIApplication.sharedApplication(), queue: nil, usingBlock: handleSave)
    }

    deinit {
        for observer in [didEnterBackgroundNotificationObserver, willResignActiveNotificationObserver, willTerminateNotificationObserver] where observer != nil {
            NSNotificationCenter.defaultCenter().removeObserver(observer!)
        }
    }

    private var didEnterBackgroundNotificationObserver: AnyObject?
    private var willResignActiveNotificationObserver: AnyObject?
    private var willTerminateNotificationObserver: AnyObject?

    private func handleSave(note: NSNotification) {
        var taskID: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid

        taskID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler { () -> Void in
            UIApplication.sharedApplication().endBackgroundTask(taskID)
        }

        if taskID != UIBackgroundTaskInvalid {
            save({ (error) -> Void in
                // Log the error?

                UIApplication.sharedApplication().endBackgroundTask(taskID)
            })
        }
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

            let bundle = NSBundle(forClass: self.dynamicType)

            if let  bundleIdentifier = bundle.bundleIdentifier,
                    documentsURL = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first?.URLByAppendingPathComponent(bundleIdentifier, isDirectory: true)
            {
                if !NSFileManager.defaultManager().fileExistsAtPath(documentsURL.absoluteString) {
                    do {
                        try NSFileManager.defaultManager().createDirectoryAtURL(documentsURL, withIntermediateDirectories: true, attributes: nil)
                    } catch {
                        // Ignore errors here, let Core Data explain the problem
                    }
                }

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
                error = .ConfigurationError("Cannot configure persistent store for bundle: \(bundle.bundleIdentifier) in directory: \(NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask))")
            }

            readyCallback(error: error)
        }
    }
}

