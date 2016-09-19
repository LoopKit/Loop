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
            case is WKApplicationRefreshBackgroundTask:
                // Use the WKApplicationRefreshBackgroundTask class to update your app’s state in the background.
                // You often use a background app refresh task to drive other tasks. For example, you could use a background app refresh task to start an URLSession background transfer, or to schedule a background snapshot refresh task.

                // Your app must schedule background app refresh tasks by calling your extension’s scheduleBackgroundRefresh(withPreferredDate:userInfo:scheduledCompletion:) method. The system never schedules these tasks.

                // WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: <#T##Date#>, userInfo: <#T##NSSecureCoding?#>, scheduledCompletion: <#T##(Error?) -> Void#>)

                // For more information, see [WKApplicationRefreshBackgroundTask] https://developer.apple.com/reference/watchkit/wkapplicationrefreshbackgroundtask

                // Background app refresh tasks are budgeted. In general, the system performs approximately one task per hour for each app in the dock (including the most recently used app). This budget is shared among all apps on the dock. The system performs multiple tasks an hour for each app with a complication on the active watch face. This budget is shared among all complications on the watch face. After you exhaust the budget, the system delays your requests until more time becomes available.
                break
            case let task as WKSnapshotRefreshBackgroundTask:
                // Use the WKSnapshotRefreshBackgroundTask class to update your app’s user interface. You can push, pop, or present other interface controllers, and then update the content of the desired interface controller. The system automatically takes a snapshot of your user interface as soon as this task completes.
                // Your app can invalidate its current snapshot and schedule a background snapshot refresh tasks by calling your extension’s scheduleSnapshotRefresh(withPreferredDate:userInfo:scheduledCompletion:) method. The system will also schedule background snapshot refresh tasks to periodically update your snapshot.

//                For more information, see WKSnapshotRefreshBackgroundTask.

//                WKExtension.shared().scheduleSnapshotRefresh(withPreferredDate: <#T##Date#>, userInfo: <#T##NSSecureCoding?#>, scheduledCompletion: <#T##(Error?) -> Void#>)

//                For more information about snapshots, see Snapshots.
                break
            case is WKURLSessionRefreshBackgroundTask:
                // Use the WKURLSessionRefreshBackgroundTask class to respond to URLSession background transfers.
                break
            case is WKWatchConnectivityRefreshBackgroundTask:
                // Use the WKWatchConnectivityRefreshBackgroundTask class to receive background updates from the WatchConnectivity framework.
                // For more information, see WKWatchConnectivityRefreshBackgroundTask.
                break
            default:
                break
            }

            task.setTaskCompleted()
        }
    }

}
