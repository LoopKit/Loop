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

    private static var lastContextDataFilename = "lastContextData.data"

    private func getDataPath(filename: String) -> String? {
        return NSFileManager.defaultManager().URLsForDirectory(.CachesDirectory, inDomains: .UserDomainMask).first?.URLByAppendingPathComponent(filename).path
    }

    private func readContext() -> WatchContext? {
        if let cacheFilePath = getDataPath(self.dynamicType.lastContextDataFilename) {
            return NSKeyedUnarchiver.unarchiveObjectWithFile(cacheFilePath) as? WatchContext
        } else {
            return nil
        }
    }

    private func saveContext(context: WatchContext) {
        if let cacheFilePath = getDataPath(self.dynamicType.lastContextDataFilename) {
            let data = NSKeyedArchiver.archivedDataWithRootObject(context)

            NSFileManager.defaultManager().createFileAtPath(cacheFilePath, contents: data, attributes: [NSFileProtectionKey: NSFileProtectionComplete])
        }
    }

    dynamic var lastContextData: WatchContext? {
        didSet {
            if let data = lastContextData {
                saveContext(data)
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
                errorHandler: { (_) -> Void in
                    session.transferUserInfo(carbEntry.rawValue)
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

// TODO: iOS 9.3
//    func session(session: WCSession, activationDidCompleteWithState activationState: WCSessionActivationState, error: NSError?) { }

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

                let server = CLKComplicationServer.sharedInstance()

                for complication in server.activeComplications {
                    server.extendTimelineForComplication(complication)
                }
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