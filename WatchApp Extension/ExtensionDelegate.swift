//
//  ExtensionDelegate.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import WatchKit


final class ExtensionDelegate: NSObject, WKExtensionDelegate {

    func applicationDidFinishLaunching() {
        // Perform any final initialization of your application.
    }

    func applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let task as WKApplicationRefreshBackgroundTask:
                // Use the WKApplicationRefreshBackgroundTask class to update your app’s state in the background.
                break
            case let task as WKSnapshotRefreshBackgroundTask:
                // Use the WKSnapshotRefreshBackgroundTask class to update your app’s user interface. You can push, pop, or present other interface controllers, and then update the content of the desired interface controller. The system automatically takes a snapshot of your user interface as soon as this task completes.
                break
            case let task as WKURLSessionRefreshBackgroundTask:
                // Use the WKURLSessionRefreshBackgroundTask class to respond to URLSession background transfers.
                break
            case let task as WKWatchConnectivityRefreshBackgroundTask:
                // Use the WKWatchConnectivityRefreshBackgroundTask class to receive background updates from the WatchConnectivity framework.
                break
            default:
                break
            }

            task.setTaskCompleted()
        }
    }

}
