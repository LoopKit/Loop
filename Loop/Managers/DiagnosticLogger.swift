//
//  DiagnosticLogger.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/10/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


class DiagnosticLogger {
    private lazy var isSimulator: Bool = TARGET_OS_SIMULATOR != 0

    var mLabService: MLabService {
        didSet {
            try! KeychainManager().setMLabDatabaseName(mLabService.databaseName, APIKey: mLabService.APIKey)
        }
    }

    init() {
        let keychain = KeychainManager()

        // Migrate RemoteSettings.plist to the Keychain
        if let (databaseName, APIKey) = keychain.getMLabCredentials() {
            mLabService = MLabService(databaseName: databaseName, APIKey: APIKey)
        } else if let settings = NSBundle.mainBundle().remoteSettings,
            APIKey = settings["mLabAPIKey"],
            APIPath = settings["mLabAPIPath"] where !APIKey.isEmpty
        {
            let databaseName = APIPath.componentsSeparatedByString("/")[1]
            try! keychain.setMLabDatabaseName(databaseName, APIKey: APIKey)
            mLabService = MLabService(databaseName: databaseName, APIKey: APIKey)
        } else {
            mLabService = MLabService(databaseName: nil, APIKey: nil)
        }
    }

    func addMessage(message: [String: AnyObject], toCollection collection: String) {
        if !isSimulator,
            let messageData = try? NSJSONSerialization.dataWithJSONObject(message, options: []),
            let task = mLabService.uploadTaskWithData(messageData, inCollection: collection)
        {
            task.resume()
        } else {
            NSLog("%@: %@", collection, message)
        }
    }
}

