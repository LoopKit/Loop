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


class DeviceDataManager: NSObject, WCSessionDelegate {

    enum Error: ErrorType {
        case ReachabilityError
    }

    private var connectSession: WCSession?

    private func readContext() -> WatchContext? {
        return NSUserDefaults.standardUserDefaults().watchContext
    }

    private func saveContext(context: WatchContext) {
        NSUserDefaults.standardUserDefaults().watchContext = context
    }

    var hasNewComplicationData: Bool {
        get {
            return NSUserDefaults.standardUserDefaults().watchContextReadyForComplication
        }
        set {
            NSUserDefaults.standardUserDefaults().watchContextReadyForComplication = newValue
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
                server.extendTimelineForComplication(complication)
            }
        }
    }

    func sendCarbEntry(carbEntry: CarbEntryUserInfo) {
        guard let session = connectSession else { return }

        if session.reachable {
            session.sendMessage(carbEntry.rawValue,
                replyHandler: { (reply) -> Void in
                    if let suggestion = BolusSuggestionUserInfo(rawValue: reply) where suggestion.recommendedBolus > 0 {
                        WKExtension.sharedExtension().rootInterfaceController?.presentControllerWithName(BolusInterfaceController.className, context: suggestion)
                    }
                },
                errorHandler: { (error) -> Void in
                    WKExtension.sharedExtension().rootInterfaceController?.presentAlertControllerWithTitle(error.localizedDescription, message: error.localizedRecoverySuggestion, preferredStyle: .Alert, actions: [WKAlertAction.dismissAction()])
                }
            )
        } else {
            session.transferUserInfo(carbEntry.rawValue)
        }
    }

    func sendSetBolus(userInfo: SetBolusUserInfo) throws {
        guard let session = connectSession where session.reachable else {
            throw Error.ReachabilityError
        }

        session.sendMessage(userInfo.rawValue, replyHandler: { (reply) -> Void in

        }, errorHandler: { (error) -> Void in
            WKExtension.sharedExtension().rootInterfaceController?.presentAlertControllerWithTitle(error.localizedDescription, message: error.localizedRecoverySuggestion, preferredStyle: .Alert, actions: [WKAlertAction.dismissAction()])
        })
    }

    // MARK: - WCSessionDelegate

    @available(watchOSApplicationExtension 2.2, *)
    func session(session: WCSession, activationDidCompleteWithState activationState: WCSessionActivationState, error: NSError?) {
        if let error = error {
            DiagnosticLogger()?.addError(String(error), fromSource: "WCSession")
        }
    }

    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        if let context = WatchContext(rawValue: applicationContext) {
            lastContextData = context
        }
    }

    func session(session: WCSession, didReceiveUserInfo userInfo: [String : AnyObject]) {
        switch userInfo["name"] as? String {
        case .Some:
            break
        default:
            if let context = WatchContext(rawValue: userInfo) {
                lastContextData = context
            }
        }
    }

    func sessionDidBecomeInactive(session: WCSession) {
        // Nothing to do here
    }

    func sessionDidDeactivate(session: WCSession) {
        connectSession = WCSession.defaultSession()
        connectSession?.delegate = self
        connectSession?.activateSession()
    }

    // MARK: - Initialization

    static let sharedManager = DeviceDataManager()

    override init() {
        super.init()

        connectSession = WCSession.defaultSession()
        connectSession?.delegate = self
        connectSession?.activateSession()

        if let context = readContext() {
            self.lastContextData = context
        }
    }
}