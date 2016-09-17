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


final class DeviceDataManager: NSObject, WCSessionDelegate {

    private var connectSession: WCSession?

    private func readContext() -> WatchContext? {
        return UserDefaults.standard.watchContext
    }

    private func saveContext(_ context: WatchContext) {
        UserDefaults.standard.watchContext = context
    }

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

    dynamic var lastContextData: WatchContext? {
        didSet {
            if let data = lastContextData {
                saveContext(data)
            }
        }
    }

    func updateComplicationDataIfNeeded() {
        if DeviceDataManager.sharedManager.hasNewComplicationData {
            DeviceDataManager.sharedManager.hasNewComplicationData = false
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

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
//        if let error = error {
            // TODO: os_log_info in iOS 10
//        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let context = WatchContext(rawValue: applicationContext as WatchContext.RawValue) {
            lastContextData = context
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        switch userInfo["name"] as? String {
        case .some:
            break
        default:
            if let context = WatchContext(rawValue: userInfo as WatchContext.RawValue) {
                lastContextData = context
                updateComplicationDataIfNeeded()
            }
        }
    }

    // MARK: - Initialization

    static let sharedManager = DeviceDataManager()

    override init() {
        super.init()

        connectSession = WCSession.default()
        connectSession?.delegate = self
        connectSession?.activate()

        if let context = readContext() {
            self.lastContextData = context
        }
    }
}
