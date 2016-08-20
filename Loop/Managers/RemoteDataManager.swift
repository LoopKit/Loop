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


final class RemoteDataManager {

    var nightscoutUploader: NightscoutUploader? {
        return nightscoutService.uploader
    }

    var nightscoutService: NightscoutService {
        didSet {
            keychain.setNightscoutURL(nightscoutService.siteURL, secret: nightscoutService.APISecret)
            UIDevice.currentDevice().batteryMonitoringEnabled = true
        }
    }

    var shareClient: ShareClient? {
        return shareService.client
    }

    var shareService: ShareService {
        didSet {
            try! keychain.setDexcomShareUsername(shareService.username, password: shareService.password)
        }
    }

    private let keychain = KeychainManager()

    init() {
        if let (username, password) = keychain.getDexcomShareCredentials() {
            shareService = ShareService(username: username, password: password)
        } else {
            shareService = ShareService(username: nil, password: nil)
        }

        if let (siteURL, APISecret) = keychain.getNightscoutCredentials() {
            nightscoutService = NightscoutService(siteURL: siteURL, APISecret: APISecret)
            UIDevice.currentDevice().batteryMonitoringEnabled = true
        } else {
            nightscoutService = NightscoutService(siteURL: nil, APISecret: nil)
        }
    }
}