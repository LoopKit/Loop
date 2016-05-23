//
//  DiagnosticLogger.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/10/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


class DiagnosticLogger {
    let APIKey: String
    let APIHost: String
    let APIPath: String

    private lazy var isSimulator: Bool = TARGET_OS_SIMULATOR != 0

    init?() {
        guard let settings = NSBundle.mainBundle().remoteSettings,
            APIKey = settings["mLabAPIKey"],
            APIHost = settings["mLabAPIHost"],
            APIPath = settings["mLabAPIPath"] where !APIKey.isEmpty
        else {
            return nil
        }

        self.APIKey = APIKey
        self.APIHost = APIHost
        self.APIPath = APIPath
    }

    func addMessage(message: [String: AnyObject], toCollection collection: String) {
        if !isSimulator,
            let messageData = try? NSJSONSerialization.dataWithJSONObject(message, options: []),
            let URL = NSURL(string: APIHost)?.URLByAppendingPathComponent(APIPath).URLByAppendingPathComponent(collection),
            components = NSURLComponents(URL: URL, resolvingAgainstBaseURL: true)
        {
            components.query = "apiKey=\(APIKey)"

            if let URL = components.URL {
                let request = NSMutableURLRequest(URL: URL)

                request.HTTPMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let task = NSURLSession.sharedSession().uploadTaskWithRequest(request, fromData: messageData) { (_, _, error) -> Void in
                    if let error = error {
                        NSLog("%s error: %@", #function, error)
                    }
                }

                task.resume()
            }
        }
    }
}

