//
//  mLabService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


private let mLabAPIHost = URL(string: "https://api.mongolab.com/api/1/databases")!


extension KeychainManager {
    func setMLabDatabaseName(_ databaseName: String?, APIKey: String?) throws {
        let credentials: InternetCredentials?

        if let username = databaseName, let password = APIKey {
            credentials = InternetCredentials(username: username, password: password, url: mLabAPIHost)
        } else {
            credentials = nil
        }

        try replaceInternetCredentials(credentials, forURL: mLabAPIHost)
    }

    func getMLabCredentials() -> (databaseName: String, APIKey: String)? {
        do {
            let credentials = try getInternetCredentials(url: mLabAPIHost)

            return (databaseName: credentials.username, APIKey: credentials.password)
        } catch {
            return nil
        }
    }
}
