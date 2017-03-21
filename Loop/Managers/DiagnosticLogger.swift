//
//  DiagnosticLogger.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/10/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


final class DiagnosticLogger {
    private lazy var isSimulator: Bool = TARGET_OS_SIMULATOR != 0

    var mLabService: MLabService {
        didSet {
            try! KeychainManager().setMLabDatabaseName(mLabService.databaseName, APIKey: mLabService.APIKey)
        }
    }

    init() {
        if let (databaseName, APIKey) = KeychainManager().getMLabCredentials() {
            mLabService = MLabService(databaseName: databaseName, APIKey: APIKey)
        } else {
            mLabService = MLabService(databaseName: nil, APIKey: nil)
        }
    }

    func addMessage(_ message: [String: Any], toCollection collection: String) {
        if !isSimulator,
            let messageData = try? JSONSerialization.data(withJSONObject: message, options: []),
            let task = mLabService.uploadTaskWithData(messageData, inCollection: collection)
        {
            task.resume()
        } else {
            NSLog("%@: %@", collection, message)
        }
    }
    
    func addMessage(_ message: String, _ collection: String) {
        addMessage(["message": message], toCollection: collection)
    }
}

