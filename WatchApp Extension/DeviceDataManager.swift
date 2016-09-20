//
//  DeviceDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/24/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import ClockKit
import Foundation
import WatchConnectivity
import WatchKit


enum DeviceDataManagerError: Error {
    case reachabilityError
}


final class DeviceDataManager {

    private var connectSession: WCSession?

    private var complicationDataLastRefreshed: Date {
        get {
            return UserDefaults.standard.complicationDataLastRefreshed
        }
        set {
            UserDefaults.standard.complicationDataLastRefreshed = newValue
        }
    }

    private var hasNewComplicationData: Bool {
        get {
            return UserDefaults.standard.watchContextReadyForComplication
        }
        set {
            UserDefaults.standard.watchContextReadyForComplication = newValue
        }
    }

    var lastContextData: WatchContext?

    func updateComplicationDataIfNeeded() {
        if hasNewComplicationData {
            hasNewComplicationData = false
            let server = CLKComplicationServer.sharedInstance()
            for complication in server.activeComplications ?? [] {
                if complicationDataLastRefreshed.timeIntervalSinceNow < TimeInterval(-8 * 60 * 60) {
                    complicationDataLastRefreshed = Date()
                    server.reloadTimeline(for: complication)
                } else {
                    server.extendTimeline(for: complication)
                }
            }
        }
    }

    func sendCarbEntry(_ carbEntry: CarbEntryUserInfo) {
        guard let session = connectSession else { return }

        if session.isReachable {
            var replied = false

            session.sendMessage(carbEntry.rawValue,
                replyHandler: { (reply) -> Void in
                    replied = true

                    if let suggestion = BolusSuggestionUserInfo(rawValue: reply as BolusSuggestionUserInfo.RawValue), suggestion.recommendedBolus > 0 {
                        WKExtension.shared().rootInterfaceController?.presentController(withName: BolusInterfaceController.className, context: suggestion)
                    }
                },
                errorHandler: { (error) -> Void in
                    if !replied {
                        WKExtension.shared().rootInterfaceController?.presentAlert(withTitle: #function, message: (error as NSError).localizedRecoverySuggestion, preferredStyle: .alert, actions: [WKAlertAction.dismissAction()])
                    }
                }
            )
        } else {
            session.transferUserInfo(carbEntry.rawValue)
        }
    }

    func sendSetBolus(_ userInfo: SetBolusUserInfo) throws {
        guard let session = connectSession, session.isReachable else {
            throw DeviceDataManagerError.reachabilityError
        }

        var replied = false

        session.sendMessage(userInfo.rawValue, replyHandler: { (reply) -> Void in
            replied = true
        }, errorHandler: { (error) -> Void in
            if !replied {
                WKExtension.shared().rootInterfaceController?.presentAlert(withTitle: error.localizedDescription, message: (error as NSError).localizedRecoverySuggestion ?? (error as NSError).localizedFailureReason, preferredStyle: .alert, actions: [WKAlertAction.dismissAction()])
            }
        })
    }

    // MARK: - Initialization

    static let sharedManager = DeviceDataManager()
}
