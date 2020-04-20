//
//  KeychainManager.swift
//  Learn
//
//  Created by Pete Schwamb on 4/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

extension KeychainManager {
    func storeNightscoutCredentials(identifier: String, url: URL, secret: String?) {
        let credentials: InternetCredentials?

        if let secret = secret {
            credentials = InternetCredentials(username: identifier, password: secret, url: url)
        } else {
            credentials = nil
        }

        do {
            try replaceInternetCredentials(credentials, forAccount: identifier)
        } catch {
        }
    }

    func getNightscoutCredentials(identifier: String) -> (url: URL, secret: String)? {
        do {
            let credentials = try getInternetCredentials(account: identifier)

            return (url: credentials.url, secret: credentials.password)
        } catch {
            return nil
        }
    }
}
