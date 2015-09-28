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

    private static var lastStatusDataFilename = "lastStatusData.data"

    private var lastStatusDataPath: String? {
        return NSFileManager.defaultManager().URLsForDirectory(.CachesDirectory, inDomains: .UserDomainMask).first?.URLByAppendingPathComponent(self.dynamicType.lastStatusDataFilename).path
    }

    dynamic var lastStatusData: NSData? {
        didSet {
            if let data = lastStatusData, cacheFilePath = lastStatusDataPath {
                NSFileManager.defaultManager().createFileAtPath(cacheFilePath, contents: data, attributes: [NSFileProtectionKey: NSFileProtectionComplete])
            }
        }
    }

    // MARK: - WCSessionDelegate

    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        if let statusData = applicationContext["statusData"] as? NSData {
            lastStatusData = statusData
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

        if let cacheFilePath = lastStatusDataPath, lastStatusData = NSFileManager.defaultManager().contentsAtPath(cacheFilePath) {
            self.lastStatusData = lastStatusData
        }
    }
}