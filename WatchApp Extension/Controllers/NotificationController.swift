//
//  NotificationController.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import Foundation
import UserNotifications


final class NotificationController: WKUserNotificationInterfaceController {

    override init() {
        super.init()
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

    override func didReceive(
        _ notification: UNNotification,
        withCompletion completionHandler: @escaping (WKUserNotificationInterfaceType) -> Void
    ) {
        let body = notification.request.content.body
        
        WKInterfaceDevice.current().play(.directionDown)
        print("WATCH: didReceive notification")

        // Very minimal band detection based on notification body
        if body.contains("Glucose:") {
            let components = body.split(separator: " ")
            if components.count >= 2,
               let glucose = Double(components[1]) {

                switch glucose {
                case ..<100:
                    WKInterfaceDevice.current().play(.failure)   // strong
                case 100..<200:
                    WKInterfaceDevice.current().play(.click)     // subtle
                default:
                    WKInterfaceDevice.current().play(.success)   // noticeable
                }
            } else {
                // Fallback haptic if parsing fails
                WKInterfaceDevice.current().play(.click)
            }
        }

        completionHandler(.default)
    }

}
