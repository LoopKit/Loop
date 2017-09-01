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

    weak var delegate: RemoteDataManagerDelegate?

    var nightscoutService: NightscoutService {
        didSet {
            keychain.setNightscoutURL(nightscoutService.siteURL, secret: nightscoutService.APISecret)
            UIDevice.current.isBatteryMonitoringEnabled = true
            delegate?.remoteDataManagerDidUpdateServices(self)
        }
    }

    var shareService: ShareService {
        didSet {
            try! keychain.setDexcomShareUsername(shareService.username, password: shareService.password, url: shareService.url)
        }
    }

    private let keychain = KeychainManager()

    init() {
        if let (username, password, url) = keychain.getDexcomShareCredentials() {
            shareService = ShareService(username: username, password: password, url: url)
        } else {
            shareService = ShareService(username: nil, password: nil, url: nil)
        }

        if let (siteURL, APISecret) = keychain.getNightscoutCredentials() {
            nightscoutService = NightscoutService(siteURL: siteURL, APISecret: APISecret)
            UIDevice.current.isBatteryMonitoringEnabled = true
        } else {
            nightscoutService = NightscoutService(siteURL: nil, APISecret: nil)
        }
    }
}


protocol RemoteDataManagerDelegate: class {
    func remoteDataManagerDidUpdateServices(_ dataManager: RemoteDataManager)
}
