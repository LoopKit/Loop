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
    let AzureAPIHost: String
    let AzureTempBasalAPIPath: String
    let AzureStatusAPIPath: String
    
    var mLabService: MLabService {
        didSet {
            try! KeychainManager().setMLabDatabaseName(mLabService.databaseName, APIKey: mLabService.APIKey)
        }
    }

    init() {
            let settings = Bundle.main.remoteSettings,
            AzureAPIHost = settings?["AzureAppServiceURL"],
            AzureTempBasalAPIPath = settings?["AzureAppServiceTempBasalAPI"],
            AzureStatusAPIPath = settings?["AzureAppServiceStatusAPI"]
        
        self.AzureTempBasalAPIPath=AzureTempBasalAPIPath!
        self.AzureStatusAPIPath = AzureStatusAPIPath!
        self.AzureAPIHost=AzureAPIHost!

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
    
    func loopPushNotification(message: [String: AnyObject], loopAlert: Bool) {
        var path : String;
        
        if !loopAlert {
            path = AzureTempBasalAPIPath
        }
        else {
            path = AzureStatusAPIPath
        }
        if !isSimulator,
            let messageData = try? JSONSerialization.data(withJSONObject: message, options: []),
            let URL = NSURL(string: AzureAPIHost)?.appendingPathComponent(path),
            let components = NSURLComponents(url: URL, resolvingAgainstBaseURL: true)
        {
            //components.query = "apiKey=\(APIKey)"
            
            if let URL = components.url {
                let request = NSMutableURLRequest(url: URL)
                
                request.httpMethod = "POST"
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                
                let task = URLSession.shared.uploadTask(with: request as URLRequest, from: messageData) { (_, _, error) -> Void in
                    if let error = error {
                        //NSLog("%s error: %@", error)
                    }
                }
                
                task.resume()
            }
        }
        
    }

}

