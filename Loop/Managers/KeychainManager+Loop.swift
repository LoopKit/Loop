//
//  KeychainManager+Loop.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


private let AmplitudeAPIKeyService = "AmplitudeAPIKey"
private let DexcomShareURL = URL(string: "https://share1.dexcom.com")!
private let NightscoutAccount = "NightscoutAPI"


extension KeychainManager {
    func setAmplitudeAPIKey(_ key: String?) throws {
        try replaceGenericPassword(key, forService: AmplitudeAPIKeyService)
    }

    func getAmplitudeAPIKey() -> String? {
        return try? getGenericPasswordForService(AmplitudeAPIKeyService)
    }

    func setDexcomShareUsername(_ username: String?, password: String?) throws {
        let credentials: InternetCredentials?

        if let username = username, let password = password {
            credentials = InternetCredentials(username: username, password: password, url: DexcomShareURL)
        } else {
            credentials = nil
        }

        try replaceInternetCredentials(credentials, forURL: DexcomShareURL)
    }

    func getDexcomShareCredentials() -> (username: String, password: String)? {
        do {
            let credentials = try getInternetCredentials(url: DexcomShareURL)

            return (username: credentials.username, password: credentials.password)
        } catch {
            return nil
        }
    }

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
