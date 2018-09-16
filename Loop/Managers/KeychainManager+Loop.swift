//
//  KeychainManager+Loop.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


private let NightscoutAccount = "NightscoutAPI"


extension KeychainManager {
    func setNightscoutURL(_ url: URL?, secret: String?) {
        let credentials: InternetCredentials?

        if let url = url, let secret = secret {
            credentials = InternetCredentials(username: NightscoutAccount, password: secret, url: url)
        } else {
            credentials = nil
        }

        do {
            try replaceInternetCredentials(credentials, forAccount: NightscoutAccount)
        } catch {
        }
    }

    func getNightscoutCredentials() -> (url: URL, secret: String)? {
        do {
            let credentials = try getInternetCredentials(account: NightscoutAccount)

            return (url: credentials.url, secret: credentials.password)
        } catch {
            return nil
        }
    }
}
