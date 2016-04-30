//
//  AppDelegate.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/15/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import CarbKit
import InsulinKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        window?.tintColor = UIColor.tintColor

        NotificationManager.authorize()

        AnalyticsManager.application(application, didFinishLaunchingWithOptions: launchOptions)

        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.

        DeviceDataManager.sharedManager.transmitter?.resumeScanning()
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func applicationShouldRequestHealthAuthorization(application: UIApplication) {

    }

    // MARK: - Notifications

    func application(application: UIApplication, didReceiveLocalNotification notification: UILocalNotification) {
        if application.applicationState == .Active {
            if let message = notification.alertBody {
                window?.rootViewController?.presentAlertControllerWithTitle(notification.alertTitle, message: message, animated: true, completion: nil)
            }
        }
    }

    func application(application: UIApplication, handleActionWithIdentifier identifier: String?, forLocalNotification notification: UILocalNotification, withResponseInfo responseInfo: [NSObject : AnyObject], completionHandler: () -> Void) {

        switch identifier {
        case NotificationManager.Action.RetryBolus.rawValue?:
            if let units = notification.userInfo?[NotificationManager.UserInfoKey.BolusAmount.rawValue] as? Double,
                startDate = notification.userInfo?[NotificationManager.UserInfoKey.BolusStartDate.rawValue] as? NSDate where
                startDate.timeIntervalSinceNow >= NSTimeInterval(minutes: -5)
            {
                AnalyticsManager.didRetryBolus()

                DeviceDataManager.sharedManager.loopManager.enactBolus(units) { (success, error) in
                    if !success {
                        NotificationManager.sendBolusFailureNotificationForAmount(units, atDate: startDate)
                    }

                    completionHandler()
                }
                return
            }
        default:
            break
        }

        completionHandler()
    }

    // MARK: - 3D Touch

    func application(application: UIApplication, performActionForShortcutItem shortcutItem: UIApplicationShortcutItem, completionHandler: (Bool) -> Void) {
        completionHandler(false)
    }
}
