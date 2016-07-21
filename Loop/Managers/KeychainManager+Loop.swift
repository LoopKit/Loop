//
//  KeychainManager+Loop.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


private let AmplitudeAPIKeyService = "AmplitudeAPIKey"
private let DexcomShareURL = NSURL(string: "https://share1.dexcom.com")!
private let NightscoutAccount = "NightscoutAPI"


extension KeychainManager {
    func setAmplitudeAPIKey(key: String?) throws {
        try replaceGenericPassword(key, forService: AmplitudeAPIKeyService)
    }

    func getAmplitudeAPIKey() -> String? {
        return try? getGenericPasswordForService(AmplitudeAPIKeyService)
    }

    func setDexcomShareUsername(username: String?, password: String?) throws {
        let credentials: InternetCredentials?

        if let username = username, password = password {
            credentials = InternetCredentials(username: username, password: password, URL: DexcomShareURL)
        } else {
            credentials = nil
        }

        try replaceInternetCredentials(credentials, forURL: DexcomShareURL)
    }

    func getDexcomShareCredentials() -> (username: String, password: String)? {
        do {
            let credentials = try getInternetCredentials(URL: DexcomShareURL)

            return (username: credentials.username, password: credentials.password)
        } catch {
            return nil
        }
    }

    func setNightscoutURL(URL: NSURL?, secret: String?) {
        let credentials: InternetCredentials?

        if let URL = URL, secret = secret {
            credentials = InternetCredentials(username: NightscoutAccount, password: secret, URL: URL)
        } else {
            credentials = nil
        }

        do {
            try replaceInternetCredentials(credentials, forAccount: NightscoutAccount)
        } catch {
        }
    }

    func getNightscoutCredentials() -> (URL: NSURL, secret: String)? {
        do {
            let credentials = try getInternetCredentials(account: NightscoutAccount)

            return (URL: credentials.URL, secret: credentials.password)
        } catch {
            return nil
        }
    }
}