//
//  PumpDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/24/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import WatchConnectivity


class PumpDataManager: NSObject, WCSessionDelegate {

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

    // MARK: - WCSessionDelegate

    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        if let context = WatchContext(rawValue: applicationContext) {
            lastContextData = context
        }
    }

    // MARK: - Initialization

    static let sharedManager = PumpDataManager()

    override init() {
        super.init()

        if WCSession.isSupported() {
            connectSession = WCSession.defaultSession()
            connectSession?.delegate = self
            connectSession?.activateSession()
        }

        if let context = readContext() {
            self.lastContextData = context
        }
    }
}