//
//  AppDelegate.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/15/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import Intents
import LoopCore
import LoopKit
import UserNotifications

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    private lazy var log = DiagnosticLog(category: "AppDelegate")

    private lazy var servicesManager = ServicesManager()

    private lazy var analyticsServicesManager = AnalyticsServicesManager(servicesManager: servicesManager)

    private lazy var loggingServicesManager = LoggingServicesManager(servicesManager: servicesManager)

    private lazy var deviceManager = DeviceDataManager(servicesManager: servicesManager, analyticsServicesManager: analyticsServicesManager)

    var window: UIWindow?

    private var rootViewController: RootNavigationController! {
        return window?.rootViewController as? RootNavigationController
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        SharedLoggingService.instance = loggingServicesManager

        NotificationManager.authorize(delegate: self)

        log.info(#function)

        analyticsServicesManager.application(application, didFinishLaunchingWithOptions: launchOptions)

        rootViewController.rootViewController.deviceManager = deviceManager

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        deviceManager.updatePumpManagerBLEHeartbeatPreference()
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
}


extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case NotificationManager.Action.retryBolus.rawValue:
            if  let units = response.notification.request.content.userInfo[LoopNotificationUserInfoKey.bolusAmount.rawValue] as? Double,
                let startDate = response.notification.request.content.userInfo[LoopNotificationUserInfoKey.bolusStartDate.rawValue] as? Date,
                startDate.timeIntervalSinceNow >= TimeInterval(minutes: -5)
            {
                analyticsServicesManager.didRetryBolus()

                deviceManager.enactBolus(units: units, at: startDate) { (_) in
                    completionHandler()
                }
                return
            }
        case NotificationManager.Action.acknowledgeCGMAlert.rawValue:
            if let alertID = response.notification.request.content.userInfo[LoopNotificationUserInfoKey.cgmAlertID.rawValue] as? Int {
                deviceManager.acknowledgeCGMAlert(alertID: alertID)
            }
        default:
            break
        }
        
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.badge, .sound, .alert])
    }
}
