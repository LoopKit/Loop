//
//  RemoteDataManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import ShareClient


class RemoteDataManager {

    var shareClient: ShareClient? {
        return shareService.client
    }

    var shareService: ShareService {
        didSet {
            try! keychain.setDexcomShareUsername(shareService.username, password: shareService.password)
        }
    }

    var nightscoutUploader: NightscoutUploader?

    private var keychain = KeychainManager()

    init() {
        // Migrate RemoteSettings.plist to the Keychain
        let settings = NSBundle.mainBundle().remoteSettings

        if let (username, password) = keychain.getDexcomShareCredentials() {
            shareService = ShareService(username: username, password: password)
        } else if let username = settings?["ShareAccountName"],
            password = settings?["ShareAccountPassword"]
            where !username.isEmpty && !password.isEmpty
        {
            try! keychain.setDexcomShareUsername(username, password: password)
            shareService = ShareService(username: username, password: password)
        } else {
            shareService = ShareService(username: nil, password: nil)
        }

        if let (siteURL, APISecret) = keychain.getNightscoutCredentials() {
            nightscoutUploader = NightscoutUploader(siteURL: siteURL.absoluteString, APISecret: APISecret)
        } else if let siteURLString = settings?["NightscoutSiteURL"],
            APISecret = settings?["NightscoutAPISecret"],
            siteURL = NSURL(string: siteURLString)
        {
            try! keychain.setNightscoutURL(siteURL, secret: APISecret)
            nightscoutUploader = NightscoutUploader(siteURL: siteURLString, APISecret: APISecret)
        }

        nightscoutUploader?.errorHandler = { (error: ErrorType, context: String) -> Void in
            print("Error \(error), while \(context)")
        }
    }

}