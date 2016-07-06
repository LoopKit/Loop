//
//  mLabService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


private let mLabAPIHost = NSURL(string: "https://api.mongolab.com/api/1/databases")!


struct MLabService: ServiceAuthentication {
    var credentials: [ServiceCredential]

    let title: String = NSLocalizedString("mLab", comment: "The title of the mLab service")

    init(databaseName: String?, APIKey: String?) {
        credentials = [
            ServiceCredential(
                title: NSLocalizedString("Database", comment: "The title of the mLab database name credential"),
                placeholder: "nightscoutdb",
                isSecret: false,
                keyboardType: .ASCIICapable,
                value: databaseName
            ),
            ServiceCredential(
                title: NSLocalizedString("API Key", comment: "The title of the mLab API Key credential"),
                placeholder: nil,
                isSecret: false,
                keyboardType: .ASCIICapable,
                value: APIKey
            )
        ]

        if databaseName != nil && APIKey != nil {
            isAuthorized = true
        }
    }

    var databaseName: String? {
        return credentials[0].value
    }

    var APIKey: String? {
        return credentials[1].value
    }

    private(set) var isAuthorized: Bool = false

    mutating func verify(completion: (success: Bool, error: ErrorType?) -> Void) {
        guard let APIURL = APIURLForCollection("") else {
            completion(success: false, error: nil)
            return
        }

        NSURLSession.sharedSession().dataTaskWithURL(APIURL) { (_, response, error) in
            var error: ErrorType? = error
            if error == nil, let response = response as? NSHTTPURLResponse where response.statusCode >= 300 {
                error = LoopError.ConnectionError
            }

            self.isAuthorized = error == nil

            completion(success: self.isAuthorized, error: error)
        }.resume()
    }

    mutating func reset() {
        credentials[0].value = nil
        credentials[1].value = nil
        isAuthorized = false
    }

    private func APIURLForCollection(collection: String) -> NSURL? {
        guard let databaseName = databaseName, APIKey = APIKey else {
            return nil
        }

        let APIURL = mLabAPIHost.URLByAppendingPathComponent("\(databaseName)/collections").URLByAppendingPathComponent(collection)
        let components = NSURLComponents(URL: APIURL, resolvingAgainstBaseURL: true)!

        var items = components.queryItems ?? []
        items.append(NSURLQueryItem(name: "apiKey", value: APIKey))
        components.queryItems = items

        return components.URL
    }

    func uploadTaskWithData(data: NSData, inCollection collection: String) -> NSURLSessionTask? {
        guard let URL = APIURLForCollection(collection) else {
            return nil
        }

        let request = NSMutableURLRequest(URL: URL)
        request.HTTPMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return NSURLSession.sharedSession().uploadTaskWithRequest(request, fromData: data)
    }
}


extension KeychainManager {
    func setMLabDatabaseName(databaseName: String?, APIKey: String?) throws {
        let credentials: InternetCredentials?

        if let username = databaseName, password = APIKey {
            credentials = InternetCredentials(username: username, password: password, URL: mLabAPIHost)
        } else {
            credentials = nil
        }

        try replaceInternetCredentials(credentials, forURL: mLabAPIHost)
    }

    func getMLabCredentials() -> (databaseName: String, APIKey: String)? {
        do {
            let credentials = try getInternetCredentials(URL: mLabAPIHost)

            return (databaseName: credentials.username, APIKey: credentials.password)
        } catch {
            return nil
        }
    }
}
