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
            UIDevice.currentDevice().batteryMonitoringEnabled = false
        }
    }

    func uploadDeviceStatus(pumpStatus: NightscoutUploadKit.PumpStatus? /*, loopStatus: LoopStatus */) {

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


        // Mock out some loop data for testing
        //            let loopTime = NSDate()
        //            let iob = IOBStatus(iob: 3.0, basaliob: 1.2, timestamp: NSDate())
        //            let loopSuggested = LoopSuggested(timestamp: loopTime, rate: 1.2, duration: NSTimeInterval(30*60), correction: 0, eventualBG: 200, reason: "Test Reason", bg: 205, tick: 5)
        //            let loopEnacted = LoopEnacted(rate: 1.2, duration: NSTimeInterval(30*60), timestamp: loopTime, received: true)
        //            let loopStatus = LoopStatus(name: "TestLoopName", timestamp: NSDate(), iob: iob, suggested: loopSuggested, enacted: loopEnacted, failureReason: nil)

        // Build DeviceStatus
        let deviceStatus = DeviceStatus(device: uploaderDevice.name, timestamp: NSDate(), pumpStatus: pumpStatus, uploaderStatus: uploaderStatus)

        uploader.uploadDeviceStatus(deviceStatus)
    }

}