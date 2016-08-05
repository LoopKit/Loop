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

    func uploadDeviceStatus(pumpStatus: NightscoutUploadKit.PumpStatus? = nil, loopStatus: LoopStatus? = nil) {

        guard let uploader = nightscoutUploader else {
            return
        }

        // Gather UploaderStatus
        let uploaderDevice = UIDevice.currentDevice()

        let battery: Int?
        if uploaderDevice.batteryMonitoringEnabled {
            battery = Int(uploaderDevice.batteryLevel * 100)
        } else {
            battery = nil
        }
        let uploaderStatus = UploaderStatus(name: uploaderDevice.name, timestamp: NSDate(), battery: battery)

        // Build DeviceStatus
        let deviceStatus = DeviceStatus(device: "loop://\(uploaderDevice.name)", timestamp: NSDate(), pumpStatus: pumpStatus, uploaderStatus: uploaderStatus, loopStatus: loopStatus)

        uploader.uploadDeviceStatus(deviceStatus)
    }

}