//
//  DoseStore.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/27/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import CoreData


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

    public init() {
        persistenceController = PersistenceController(readyCallback: { [unowned self] (error) -> Void in
            if let error = error {
                self.readyState = .Failed(error)
            } else {
                self.readyState = .Ready
            }
        })

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
        save()
    }

    func save() {
        var taskID: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid

        taskID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler { () -> Void in
            UIApplication.sharedApplication().endBackgroundTask(taskID)
        }

        if taskID != UIBackgroundTaskInvalid {
            persistenceController.save({ (error) -> Void in
                // Log the error?

                UIApplication.sharedApplication().endBackgroundTask(taskID)
            })
        }
    }
}
