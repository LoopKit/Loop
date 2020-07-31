//
//  AppDelegate.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/15/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Intents
import LoopCore
import LoopKit
import UIKit
import UserNotifications
import HealthKit
import LoopKitUI

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate, DeviceOrientationController {

    private lazy var log = DiagnosticLog(category: "AppDelegate")

    private lazy var pluginManager = PluginManager()

    private var alertManager: AlertManager!
    private var deviceDataManager: DeviceDataManager!
    private var loopAlertsManager: LoopAlertsManager!
    private var bluetoothStateManager: BluetoothStateManager!

    var window: UIWindow?

    private var rootViewController: RootNavigationController! {
        return window?.rootViewController as? RootNavigationController
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true

        bluetoothStateManager = BluetoothStateManager()
        bluetoothStateManager.addBluetoothStateObserver(rootViewController.rootViewController)
        alertManager = AlertManager(rootViewController: rootViewController, expireAfter: Bundle.main.localCacheDuration ?? .days(1))
        deviceDataManager = DeviceDataManager(pluginManager: pluginManager, alertManager: alertManager, bluetoothStateManager: bluetoothStateManager)
        loopAlertsManager = LoopAlertsManager(alertManager: alertManager, bluetoothStateManager: bluetoothStateManager)
        
        SharedLogging.instance = deviceDataManager.loggingServicesManager

        OrientationLock.deviceOrientationController = self

        NotificationManager.authorize(delegate: self)
        
        log.info(#function)

        deviceDataManager.analyticsServicesManager.application(application, didFinishLaunchingWithOptions: launchOptions)

        rootViewController.rootViewController.deviceManager = deviceDataManager
        
        let notificationOption = launchOptions?[.remoteNotification]
        
        if let notification = notificationOption as? [String: AnyObject] {
            deviceDataManager.handleRemoteNotification(notification)
        }
                
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        deviceDataManager.updatePumpManagerBLEHeartbeatPreference()
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }

    // MARK: - Continuity

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {

        if #available(iOS 12.0, *) {
            if userActivity.activityType == NewCarbEntryIntent.className {
                log.default("Restoring %{public}@ intent", userActivity.activityType)
                rootViewController.restoreUserActivityState(.forNewCarbEntry())
                return true
            }
        }

        switch userActivity.activityType {
        case NSUserActivity.newCarbEntryActivityType,
             NSUserActivity.viewLoopStatusActivityType:
            log.default("Restoring %{public}@ activity", userActivity.activityType)
            restorationHandler([rootViewController])
            return true
        default:
            return false
        }
    }
    
    // MARK: - Remote notifications
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        log.default("RemoteNotifications device token: %{public}@", token)
        deviceDataManager.loopManager.settings.deviceToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("Failed to register: %{public}@", String(describing: error))
    }
    
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let notification = userInfo as? [String: AnyObject] else {
            completionHandler(.failed)
            return
        }
      
        deviceDataManager.handleRemoteNotification(notification)
        completionHandler(.noData)
    }

    // MARK: - DeviceOrientationController

    var supportedInterfaceOrientations = UIInterfaceOrientationMask.allButUpsideDown

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        supportedInterfaceOrientations
    }
}

// MARK: UNUserNotificationCenterDelegate implementation

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case NotificationManager.Action.retryBolus.rawValue:
            if  let units = response.notification.request.content.userInfo[LoopNotificationUserInfoKey.bolusAmount.rawValue] as? Double,
                let startDate = response.notification.request.content.userInfo[LoopNotificationUserInfoKey.bolusStartDate.rawValue] as? Date,
                startDate.timeIntervalSinceNow >= TimeInterval(minutes: -5)
            {
                deviceDataManager.analyticsServicesManager.didRetryBolus()

                deviceDataManager.enactBolus(units: units, at: startDate) { (_) in
                    completionHandler()
                }
                return
            }
        case NotificationManager.Action.acknowledgeAlert.rawValue:
            let userInfo = response.notification.request.content.userInfo
            if let alertIdentifier = userInfo[LoopNotificationUserInfoKey.alertTypeID.rawValue] as? Alert.AlertIdentifier,
                let managerIdentifier = userInfo[LoopNotificationUserInfoKey.managerIDForAlert.rawValue] as? String {
                alertManager.acknowledgeAlert(identifier:
                    Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: alertIdentifier))
            }
        default:
            break
        }

        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        switch notification.request.identifier {
        // TODO: Until these notifications are converted to use the new alert system, they shall still show in the foreground
        case LoopNotificationCategory.bolusFailure.rawValue,
             LoopNotificationCategory.pumpReservoirLow.rawValue,
             LoopNotificationCategory.pumpReservoirEmpty.rawValue,
             LoopNotificationCategory.pumpBatteryLow.rawValue,
             LoopNotificationCategory.pumpExpired.rawValue,
             LoopNotificationCategory.pumpFault.rawValue:
            completionHandler([.badge, .sound, .alert])
        default:
            // All other userNotifications are not to be displayed while in the foreground
            completionHandler([])
        }
    }
}
