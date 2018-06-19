//
//  ExtensionDelegate.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import WatchConnectivity
import WatchKit
import HealthKit
import os
import UserNotifications


final class ExtensionDelegate: NSObject, WKExtensionDelegate {

    static func shared() -> ExtensionDelegate {
        return WKExtension.shared().extensionDelegate
    }

    override init() {
        super.init()

        let session = WCSession.default
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
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidBecomeActive() {
        if WCSession.default.activationState != .activated {
            WCSession.default.activate()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case is WKApplicationRefreshBackgroundTask:
                os_log("Processing WKApplicationRefreshBackgroundTask")
                break
            case let task as WKSnapshotRefreshBackgroundTask:
                os_log("Processing WKSnapshotRefreshBackgroundTask")
                task.setTaskCompleted(restoredDefaultState: false, estimatedSnapshotExpiration: Date(timeIntervalSinceNow: TimeInterval(minutes: 5)), userInfo: nil)
                return  // Don't call the standard setTaskCompleted handler
            case is WKURLSessionRefreshBackgroundTask:
                break
            case let task as WKWatchConnectivityRefreshBackgroundTask:
                os_log("Processing WKWatchConnectivityRefreshBackgroundTask")

                pendingConnectivityTasks.append(task)

                if WCSession.default.activationState != .activated {
                    WCSession.default.activate()
                }

                completePendingConnectivityTasksIfNeeded()
                return // Defer calls to the setTaskCompleted handler
            default:
                break
            }

            if #available(watchOSApplicationExtension 4.0, *) {
                task.setTaskCompletedWithSnapshot(false)
            } else {
                task.setTaskCompleted()
            }
        }
    }

    private var pendingConnectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    private func completePendingConnectivityTasksIfNeeded() {
        if WCSession.default.activationState == .activated && !WCSession.default.hasContentPending {
            pendingConnectivityTasks.forEach { (task) in
                if #available(watchOSApplicationExtension 4.0, *) {
                    task.setTaskCompletedWithSnapshot(false)
                } else {
                    task.setTaskCompleted()
                }
            }
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

    private lazy var healthStore = HKHealthStore()

    fileprivate func updateContext(_ data: [String: Any]) {
        if let context = WatchContext(rawValue: data as WatchContext.RawValue) {
            if context.preferredGlucoseUnit == nil {
                let type = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
                healthStore.preferredUnits(for: [type]) { (units, error) in
                    context.preferredGlucoseUnit = units[type]

                    DispatchQueue.main.async {
                        self.lastContext = context
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.lastContext = context
                }
            }
        }
    }
}


extension ExtensionDelegate: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
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
