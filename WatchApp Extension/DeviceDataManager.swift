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


class DeviceDataManager: NSObject, WCSessionDelegate {

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
        if let session = connectSession {
            if session.reachable {
                session.sendMessage(carbEntry.rawValue, replyHandler: nil, errorHandler: { (_) -> Void in
                    session.transferUserInfo(carbEntry.rawValue)
                })
            } else {
                session.transferUserInfo(carbEntry.rawValue)
            }
        }
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
        if let context = WatchContext(rawValue: userInfo) {
            lastContextData = context

            let server = CLKComplicationServer.sharedInstance()

            for complication in server.activeComplications {
                server.extendTimelineForComplication(complication)
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