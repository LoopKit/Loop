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
import LoopAlgorithm
import Intents
import os
import os.log
import UserNotifications
import LoopKit
import LoopCore
import ClockKit

class ExtensionDelegate: NSObject, WKApplicationDelegate {

    let log = OSLog(category: "ExtensionDelegate")

    /// The Sport Mode stack — built and used by ExtensionDelegate+PodLoan.swift.
    var stockLoopSession: StockLoopSession?
    /// Guards a second build while the first is in flight — ExtensionDelegate+PodLoan.swift.
    var stockLoopSessionStarting = false

    private var observers: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []

    static func shared() -> ExtensionDelegate {
        return sharedIfAvailable()!
    }

    let loopManager = LoopDataManager.shared

    override init() {
        super.init()

        podLoanRegisterSharedInstance()

        let session = WCSession.default
        session.delegate = self

        // It seems, according to [this sample code](https://developer.apple.com/library/prerelease/content/samplecode/QuickSwitch/Listings/QuickSwitch_WatchKit_Extension_ExtensionDelegate_swift.html#//apple_ref/doc/uid/TP40016647-QuickSwitch_WatchKit_Extension_ExtensionDelegate_swift-DontLinkElementID_8)
        // that WCSession activation and delegation and WKWatchConnectivityRefreshBackgroundTask don't have any determinism,
        // and that KVO is the "recommended" way to deal with it.
        observers.append(session.observe(\WCSession.activationState) { [weak self] (session, change) in
            self?.log.default("WCSession.applicationState did change to %d", session.activationState.rawValue)

            self?.log.default("WCSession.applicationState did change rootInterfaceController = %{public}@", String(describing: WKApplication.shared().rootInterfaceController))
            self?.log.default("WCSession.applicationState did change visibleInterfaceController = %{public}@", String(describing: WKApplication.shared().visibleInterfaceController))

            DispatchQueue.main.async {
                self?.completePendingConnectivityTasksIfNeeded()
            }
        })
        observers.append(session.observe(\WCSession.hasContentPending) { [weak self] (session, change) in
            self?.log.default("WCSession.hasContentPending did change to %d", session.hasContentPending)

            DispatchQueue.main.async {
                self?.loopManager.sendDidUpdateContextNotificationIfNecessary()
                self?.completePendingConnectivityTasksIfNeeded()
            }
        })

        notifications.append(NotificationCenter.default.addObserver(forName: LoopDataManager.didUpdateContextNotification, object: loopManager, queue: nil) { [weak self] (_) in
            DispatchQueue.main.async {
                self?.loopManagerDidUpdateContext()
            }
        })

        session.activate()
    }

    deinit {
        for notification in notifications {
            NotificationCenter.default.removeObserver(notification)
        }
    }

    func applicationDidFinishLaunching() {
        podLoanDidFinishLaunching()
        UNUserNotificationCenter.current().delegate = self
        if #available(watchOSApplicationExtension 5.0, *) {
            INRelevantShortcutStore.default.registerShortcuts()
        }
    }

    func applicationDidBecomeActive() {
        if WCSession.default.activationState != .activated {
            WCSession.default.activate()
        }

        // Catch up when the app comes to the foreground (e.g. tapping a stale
        // complication). Otherwise glucose is only fetched during background
        // refresh tasks, so opening the app could show just the current point
        // and forecast with no history. Pull the latest context and backfill any
        // glucose we're missing.
        loopManager.requestContextUpdate()
        loopManager.requestGlucoseBackfillIfNecessary()

        podLoanDidBecomeActive()
    }

    func applicationWillResignActive() {
        podLoanWillResignActive()
    }

    // NOT always the main thread. The Bluetooth alert task is delivered synchronously from
    // CoreBluetooth's delegate queue: bluetoothd's "peripheral usage" notification (fired the
    // moment the app subscribes to a characteristic) is posted on that queue, WatchKit observes
    // it there and calls this delegate on the spot. 2026-09-14: four Bluetooth relaunches in a row
    // died 0.25 s after subscribing, on the `dispatchPrecondition(.onQueue(.main))` inside
    // `requestGlucoseBackfillIfNecessary()` (crash reports WatchApp-2026-09-14-16{4956,5640,5641,5645}).
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        guard Thread.isMainThread else {
            // Silent hop: WatchKit delivers the Bluetooth task once per GATT event (~55 per
            // handshake on 2026-09-14), so the hop is not worth a log line each; the held-task
            // summary below counts them.
            DispatchQueue.main.async { self.handle(backgroundTasks) }
            return
        }
        podLoanNoteBackgroundTasks(backgroundTasks)

        loopManager.requestGlucoseBackfillIfNecessary()

        for task in backgroundTasks {
            switch task {
            case is WKApplicationRefreshBackgroundTask:
                log.default("Processing WKApplicationRefreshBackgroundTask")
                break
            case let task as WKSnapshotRefreshBackgroundTask:
                log.default("Processing WKSnapshotRefreshBackgroundTask")
                task.setTaskCompleted(restoredDefaultState: false, estimatedSnapshotExpiration: Date(timeIntervalSinceNow: TimeInterval(minutes: 5)), userInfo: nil)
                return  // Don't call the standard setTaskCompleted handler
            case let task as WKBluetoothAlertRefreshBackgroundTask:
                holdBluetoothTask(task)
                continue  // completed on our own schedule
            case is WKURLSessionRefreshBackgroundTask:
                break
            case let task as WKWatchConnectivityRefreshBackgroundTask:
                log.default("Processing WKWatchConnectivityRefreshBackgroundTask")

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

    // MARK: Bluetooth alert task — one held per wake (ExtensionDelegate+BluetoothWake.swift)

    var heldBluetoothTask: WKBluetoothAlertRefreshBackgroundTask?
    var heldBluetoothTaskSince: Date?
    var bluetoothDeliveriesThisWake = 0

    private func completePendingConnectivityTasksIfNeeded() {
        if WCSession.default.activationState == .activated && !WCSession.default.hasContentPending {
            pendingConnectivityTasks.forEach { (task) in
                self.log.default("Completing WKWatchConnectivityRefreshBackgroundTask %{public}@", String(describing: task))
                if #available(watchOSApplicationExtension 4.0, *) {
                    task.setTaskCompletedWithSnapshot(false)
                } else {
                    task.setTaskCompleted()
                }
            }
            pendingConnectivityTasks.removeAll()
        }
    }

    func handle(_ userActivity: NSUserActivity) {
        switch userActivity.activityType {
        case NSUserActivity.newCarbEntryActivityType, NSUserActivity.didAddCarbEntryOnWatchActivityType:
            loopManager.bolusViewModel = CarbAndBolusFlowViewModel(configuration: .carbEntry(nil))
        default:
            break
        }
    }

    private func updateContext(_ data: [String: Any]) {
        guard let context = WatchContext(rawValue: data) else {
            log.error("Could not decode WatchContext: %{public}@", data)
            return
        }

        if context.displayGlucoseUnit == nil {
            let type = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
            loopManager.healthStore.preferredUnits(for: [type]) { (units, error) in
                defer {
                    DispatchQueue.main.async {
                        self.loopManager.updateContext(context)
                    }
                }
                
                guard let unit = units[type] else {
                    context.displayGlucoseUnit = nil
                    return
                }
                
                context.displayGlucoseUnit = LoopUnit(from: unit)
            }
        } else {
            DispatchQueue.main.async {
                self.loopManager.updateContext(context)
            }
        }
    }

    private func loopManagerDidUpdateContext() {
        dispatchPrecondition(condition: .onQueue(.main))

        if WKApplication.shared().applicationState != .active {
            WKApplication.shared().scheduleSnapshotRefresh(withPreferredDate: Date(), userInfo: nil) { (error) in
                if let error = error {
                    self.log.error("scheduleSnapshotRefresh error: %{public}@", String(describing: error))
                }
            }
        }

        // Update complication data if needed
        let server = CLKComplicationServer.sharedInstance()
        for complication in server.activeComplications ?? [] {
            log.default("Reloading complication timeline")
            server.reloadTimeline(for: complication)
        }
    }
}


extension ExtensionDelegate: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        log.default("activationDidCompleteWith %{public}@", String(describing: activationState))

        log.default("activationDidCompleteWith rootInterfaceController = %{public}@", String(describing: WKApplication.shared().rootInterfaceController))
        log.default("activationDidCompleteWith visibleInterfaceController = %{public}@", String(describing: WKApplication.shared().visibleInterfaceController))

        if activationState == .activated {
            updateContext(session.receivedApplicationContext)
            podLoanSessionDidActivate()
            Task {
                await loopManager.requestSettingsUpdate()
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        log.default("didReceiveApplicationContext")
        updateContext(applicationContext)
    }

    // This method is called on a background thread of your app
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        // Loan traffic first: it is addressed to the loan controller, not to the context
        // machinery below, and the switch's default arm would otherwise swallow it.
        if let session = stockLoopSession {
            if session.handleIncomingIfLoanMessage(userInfo, channel: .queued) { return }
        } else if userInfo[LoanProtocol.userInfoKey] != nil {
            podLoanNoteEarlyPayload()
            return
        }

        let name = userInfo["name"] as? String ?? "WatchContext"

        log.default("didReceiveUserInfo: %{public}@", name)

        switch name {
        case LoopSettingsUserInfo.name:
            if let loopSettings = LoopSettingsUserInfo(rawValue: userInfo) {
                DispatchQueue.main.async {
                    self.loopManager.watchInfo = loopSettings
                }
            } else {
                log.error("Could not decode LoopSettingsUserInfo: %{public}@", userInfo)
            }
        case SupportedBolusVolumesUserInfo.name:
            guard let volumes = SupportedBolusVolumesUserInfo(rawValue: userInfo)?.supportedBolusVolumes else {
                log.error("Could not decode SupportedBolusVolumesUserInfo: %{public}@", userInfo)
                return
            }

            DispatchQueue.main.async {
                self.loopManager.supportedBolusVolumes = volumes
            }
        case "WatchContext":
            // WatchContext is the only userInfo type without a "name" key. This isn't a great heuristic.
            updateContext(userInfo)
        default:
            break
        }
    }
}

extension ExtensionDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {

        log.default("UNNotificationResponse rootInterfaceController = %{public}@", String(describing: WKApplication.shared().rootInterfaceController))
        log.default("UNNotificationResponse visibleInterfaceController = %{public}@", String(describing: WKApplication.shared().visibleInterfaceController))

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            guard response.notification.request.identifier == LoopNotificationCategory.missedMeal.rawValue else {
                break
            }

            let userInfo = response.notification.request.content.userInfo
            // If we have info about a meal, the carb entry UI should reflect it
            if
                let mealTime = userInfo[LoopNotificationUserInfoKey.missedMealTime.rawValue] as? Date,
                let carbAmount = userInfo[LoopNotificationUserInfoKey.missedMealCarbAmount.rawValue] as? Double
            {
                let missedEntry = NewCarbEntry(quantity: LoopQuantity(unit: .gram,
                                                                         doubleValue: carbAmount),
                                                    startDate: mealTime,
                                                    foodType: nil,
                                                    absorptionTime: nil)
                loopManager.bolusViewModel = CarbAndBolusFlowViewModel(configuration: .carbEntry(missedEntry))
            // Otherwise, just provide the ability to add carbs
            } else {
                loopManager.bolusViewModel = CarbAndBolusFlowViewModel(configuration: .carbEntry(nil))
            }
        case NotificationManager.Action.startPreset.rawValue:
            // Response contains the preset id and alert id
            let userInfo = response.notification.request.content.userInfo
            guard let presetIdentifier = userInfo[LoopNotificationUserInfoKey.presetId.rawValue] as? String,
                  let alertIdentifier = userInfo[LoopNotificationUserInfoKey.alertTypeID.rawValue] as? LoopKit.Alert.AlertIdentifier,
                  let managerIdentifier = userInfo[LoopNotificationUserInfoKey.managerIDForAlert.rawValue] as? String
            else {
                log.default("Unable to find keys in userInfo: %{public}@", String(describing: userInfo))
                return
            }
            log.default("Setting up PendingPresetReminder(presetIdentifier: %{public}@, alertIdentifier: %{public}@), managerIdentifier: %{public}@", presetIdentifier, alertIdentifier, managerIdentifier)

            loopManager.pendingPresetReminder = PendingPresetReminder(
                presetIdentifier: presetIdentifier,
                alertIdentifier: alertIdentifier,
                managerIdentifier: managerIdentifier
            )

            guard let visibleVC = WKApplication.shared().visibleInterfaceController else {
                log.error("no visible interface controller for presenting preset reminder!")
                return
            }

            guard let preset = loopManager.selectablePresets.first(where: { $0.id == presetIdentifier }) else {
                log.error("Unable to find preset %{public}@", presetIdentifier)
                return
            }

            visibleVC.presentController(withName: "PresetConfirmHostingController", context: preset)

        default:
            let userInfo = response.notification.request.content.userInfo
            if let alertIdentifier = userInfo[LoopNotificationUserInfoKey.alertTypeID.rawValue] as? LoopKit.Alert.AlertIdentifier,
               let managerIdentifier = userInfo[LoopNotificationUserInfoKey.managerIDForAlert.rawValue] as? String
            {
                await loopManager.sendUserSelectedNotificationActionMessage(alertIdentifier: alertIdentifier, managerIdentifier: managerIdentifier, actionIdentifier: response.actionIdentifier)
            }
            break
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.badge, .sound, .list, .banner])
    }
}


extension ExtensionDelegate {
    /// Global shortcut to present an alert for a specific error out-of-context with a specific interface controller.
    ///
    /// - parameter error: The error whose contents to display
    func present(_ error: Error) {
        dispatchPrecondition(condition: .onQueue(.main))

        WKApplication.shared().rootInterfaceController?.presentAlert(withTitle: error.localizedDescription, message: (error as NSError).localizedRecoverySuggestion ?? (error as NSError).localizedFailureReason, preferredStyle: .alert, actions: [WKAlertAction.dismissAction()])
    }
}


// `WKApplication.extensionDelegate` (which was `delegate as? ExtensionDelegate`) was deleted
// rather than left unused. Under the SwiftUI lifecycle that lookup always yields nil, so keeping
// it around is keeping a loaded gun: it reads like the obvious way to reach the delegate and
// silently returns nothing. Use `ExtensionDelegate.sharedIfAvailable()`.
