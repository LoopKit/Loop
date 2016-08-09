//
//  NightscoutDataManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutUploadKit


class NightscoutDataManager {

    unowned let deviceDataManager: DeviceDataManager

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(uploadLoopStatus(_:)), name: LoopDataManager.LoopDataUpdatedNotification, object: deviceDataManager.loopManager)
    }

    @objc func uploadLoopStatus(note: NSNotification) {

    }

}
