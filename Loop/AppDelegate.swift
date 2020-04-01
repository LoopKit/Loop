//
//  AppDelegate.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/15/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import Intents
import LoopKit
import UserNotifications

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    private lazy var log = DiagnosticLogger.shared.forCategory("AppDelegate")

    var window: UIWindow?

    private var deviceManager: DeviceDataManager?

    private var rootViewController: RootNavigationController! {
        return window?.rootViewController as? RootNavigationController
    }
    
    private var isAfterFirstUnlock: Bool {
        let fileManager = FileManager.default
        do {
            let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
            let fileURL = documentDirectory.appendingPathComponent("protection.test")
            guard fileManager.fileExists(atPath: fileURL.path) else {
                let contents = Data("unimportant".utf8)
                try? contents.write(to: fileURL, options: .completeFileProtectionUntilFirstUserAuthentication)
                // If file doesn't exist, we're at first start, which will be user directed.
                return true
            }
            let contents = try? Data(contentsOf: fileURL)
            return contents != nil
        } catch {
            log.error(error)
        }
        return false
    }
    
    private func finishLaunch() {
        log.default("Finishing launching")
        
        deviceManager = DeviceDataManager()
        
        NotificationManager.authorize(delegate: self)
 
        let mainStatusViewController = UIStoryboard(name: "Main", bundle: Bundle(for: AppDelegate.self)).instantiateViewController(withIdentifier: "MainStatusViewController") as! StatusTableViewController
        
        mainStatusViewController.deviceManager = deviceManager
        
        rootViewController.pushViewController(mainStatusViewController, animated: false)
        
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        log.default("didFinishLaunchingWithOptions \(String(describing: launchOptions))")
        
        AnalyticsManager.shared.application(application, didFinishLaunchingWithOptions: launchOptions)

        guard isAfterFirstUnlock else {
            log.default("Launching before first unlock; pausing launch...")
            return false
        }

        finishLaunch()

        let notificationOption = launchOptions?[.remoteNotification]
        
        if let notification = notificationOption as? [String: AnyObject] {
            deviceManager?.handleRemoteNotification(notification)
        }

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        log.default(#function)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        log.default(#function)
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        log.default(#function)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        deviceManager?.updatePumpManagerBLEHeartbeatPreference()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        log.default(#function)
    }

    // MARK: - Continuity

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        log.default(#function)

        if #available(iOS 12.0, *) {
            if userActivity.activityType == NewCarbEntryIntent.className {
                log.default("Restoring \(userActivity.activityType) intent")
                rootViewController.restoreUserActivityState(.forNewCarbEntry())
                return true
            }
        }

        switch userActivity.activityType {
        case NSUserActivity.newCarbEntryActivityType,
             NSUserActivity.viewLoopStatusActivityType:
            log.default("Restoring \(userActivity.activityType) activity")
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
        log.default("RemoteNotifications device token: \(token)")
        deviceManager?.loopManager.settings.deviceToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("Failed to register: \(error)")
    }
    
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let notification = userInfo as? [String: AnyObject] else {
            completionHandler(.failed)
            return
        }
      
        deviceManager?.handleRemoteNotification(notification)
        completionHandler(.noData)
    }
    
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        log.default("applicationProtectedDataDidBecomeAvailable")
        
        if deviceManager == nil {
            finishLaunch()
        }
    }

}


extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case NotificationManager.Action.retryBolus.rawValue:
            if  let units = response.notification.request.content.userInfo[NotificationManager.UserInfoKey.bolusAmount.rawValue] as? Double,
                let startDate = response.notification.request.content.userInfo[NotificationManager.UserInfoKey.bolusStartDate.rawValue] as? Date,
                startDate.timeIntervalSinceNow >= TimeInterval(minutes: -5)
            {
                AnalyticsManager.shared.didRetryBolus()

                deviceManager?.enactBolus(units: units, at: startDate) { (_) in
                    completionHandler()
                }
                return
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
