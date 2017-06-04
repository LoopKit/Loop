//
//  ExtensionDelegate.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import WatchConnectivity
import WatchKit
import os
import UserNotifications


final class ExtensionDelegate: NSObject, WKExtensionDelegate {

    static func shared() -> ExtensionDelegate {
        return WKExtension.shared().extensionDelegate
    }

    override init() {
        super.init()

        let session = WCSession.default()
        session.delegate = self

        // It seems, according to [this sample code](https://developer.apple.com/library/prerelease/content/samplecode/QuickSwitch/Listings/QuickSwitch_WatchKit_Extension_ExtensionDelegate_swift.html#//apple_ref/doc/uid/TP40016647-QuickSwitch_WatchKit_Extension_ExtensionDelegate_swift-DontLinkElementID_8)
        // that WCSession activation and delegation and WKWatchConnectivityRefreshBackgroundTask don't have any determinism,
        // and that KVO is the "recommended" way to deal with it.
        session.addObserver(self, forKeyPath: #keyPath(WCSession.activationState), options: [], context: nil)
        session.addObserver(self, forKeyPath: #keyPath(WCSession.hasContentPending), options: [], context: nil)

        session.activate()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            self.completePendingConnectivityTasksIfNeeded()
        }
    }

    func applicationDidFinishLaunching() {
        // Perform any final initialization of your application.
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.

        if WCSession.default().activationState != .activated {
            WCSession.default().activate()
        }
    }

    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
    }

    func handleUserActivity(_ userInfo: [AnyHashable : Any]?) {
        // Use it to respond to Handoff–related activity. WatchKit calls this method when your app is launched as a result of a Handoff action. Use the information in the provided userInfo dictionary to determine how you want to respond to the action. For example, you might decide to display a specific interface controller.
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case is WKApplicationRefreshBackgroundTask:
                os_log("Processing WKApplicationRefreshBackgroundTask")
                // Use the WKApplicationRefreshBackgroundTask class to update your app’s state in the background.
                // You often use a background app refresh task to drive other tasks. For example, you could use a background app refresh task to start an URLSession background transfer, or to schedule a background snapshot refresh task.
                // Your app must schedule background app refresh tasks by calling your extension’s scheduleBackgroundRefresh(withPreferredDate:userInfo:scheduledCompletion:) method. The system never schedules these tasks.
                // WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate:userInfo: scheduledCompletion:)
                // For more information, see [WKApplicationRefreshBackgroundTask] https://developer.apple.com/reference/watchkit/wkapplicationrefreshbackgroundtask
                // Background app refresh tasks are budgeted. In general, the system performs approximately one task per hour for each app in the dock (including the most recently used app). This budget is shared among all apps on the dock. The system performs multiple tasks an hour for each app with a complication on the active watch face. This budget is shared among all complications on the watch face. After you exhaust the budget, the system delays your requests until more time becomes available.
                break
            case let task as WKSnapshotRefreshBackgroundTask:
                os_log("Processing WKSnapshotRefreshBackgroundTask")
                // Use the WKSnapshotRefreshBackgroundTask class to update your app’s user interface. You can push, pop, or present other interface controllers, and then update the content of the desired interface controller. The system automatically takes a snapshot of your user interface as soon as this task completes.
                // Your app can invalidate its current snapshot and schedule a background snapshot refresh tasks by calling your extension’s scheduleSnapshotRefresh(withPreferredDate:userInfo:scheduledCompletion:) method. The system will also schedule background snapshot refresh tasks to periodically update your snapshot.
                // For more information, see WKSnapshotRefreshBackgroundTask.
                // For more information about snapshots, see Snapshots.

                task.setTaskCompleted(restoredDefaultState: false, estimatedSnapshotExpiration: Date(timeIntervalSinceNow: TimeInterval(minutes: 5)), userInfo: nil)
                return  // Don't call the standard setTaskCompleted handler
            case is WKURLSessionRefreshBackgroundTask:
                // Use the WKURLSessionRefreshBackgroundTask class to respond to URLSession background transfers.
                break
            case let task as WKWatchConnectivityRefreshBackgroundTask:
                os_log("Processing WKWatchConnectivityRefreshBackgroundTask")
                // Use the WKWatchConnectivityRefreshBackgroundTask class to receive background updates from the WatchConnectivity framework.
                // For more information, see WKWatchConnectivityRefreshBackgroundTask.

                pendingConnectivityTasks.append(task)

                if WCSession.default().activationState != .activated {
                    WCSession.default().activate()
                }

                completePendingConnectivityTasksIfNeeded()
                return // Defer calls to the setTaskCompleted handler
            default:
                break
            }

            task.setTaskCompleted()
        }
    }

    private var pendingConnectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    private func completePendingConnectivityTasksIfNeeded() {
        if WCSession.default().activationState == .activated && !WCSession.default().hasContentPending {
            pendingConnectivityTasks.forEach { $0.setTaskCompleted() }
            pendingConnectivityTasks.removeAll()
        }
    }

    // Main queue only
    private(set) var lastContext: WatchContext? {
        didSet {
            WKExtension.shared().rootUpdatableInterfaceController?.update(with: lastContext)

            if WKExtension.shared().applicationState != .active {
                WKExtension.shared().scheduleSnapshotRefresh(withPreferredDate: Date(), userInfo: nil) { (_) in }
            }

            // Update complication data if needed
            let server = CLKComplicationServer.sharedInstance()
            for complication in server.activeComplications ?? [] {
                // In watchOS 2, we forced a timeline reload every 8 hours because attempting to extend it indefinitely seemed to lead to the complication "freezing".
                if UserDefaults.standard.complicationDataLastRefreshed.timeIntervalSinceNow < TimeInterval(hours: -8) {
                    UserDefaults.standard.complicationDataLastRefreshed = Date()
                    os_log("Reloading complication timeline")
                    server.reloadTimeline(for: complication)
                } else {
                    os_log("Extending complication timeline")
                    // TODO: Switch this back to extendTimeline if things are working correctly.
                    // Time Travel appears to be disabled by default in watchOS 3 anyway
                    server.reloadTimeline(for: complication)
                }
            }
        }
    }

    fileprivate func updateContext(_ data: [String: Any]) {
        if let context = WatchContext(rawValue: data as WatchContext.RawValue) {
            DispatchQueue.main.async {
                self.lastContext = context
            }
        }
    }
}


extension ExtensionDelegate: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated && lastContext == nil {
            updateContext(session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        updateContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        // WatchContext is the only userInfo type without a "name" key. This isn't a great heuristic.
        if !(userInfo["name"] is String) {
            updateContext(userInfo)
        }
    }
}


extension ExtensionDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.badge, .sound, .alert])
    }
}


extension ExtensionDelegate {

    /// Global shortcut to present an alert for a specific error out-of-context with a specific interface controller.
    ///
    /// - parameter error: The error whose contents to display
    func present(_ error: Error) {
        WKExtension.shared().rootInterfaceController?.presentAlert(withTitle: error.localizedDescription, message: (error as NSError).localizedRecoverySuggestion ?? (error as NSError).localizedFailureReason, preferredStyle: .alert, actions: [WKAlertAction.dismissAction()])
    }
}


fileprivate extension WKExtension {
    var extensionDelegate: ExtensionDelegate! {
        return delegate as? ExtensionDelegate
    }

    var rootUpdatableInterfaceController: ContextUpdatable? {
        return rootInterfaceController as? ContextUpdatable
    }
}
