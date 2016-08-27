//
//  NightscoutDataManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import HealthKit
import InsulinKit
import LoopKit

class NightscoutDataManager {

    unowned let deviceDataManager: DeviceDataManager
    
    // Last time we uploaded device status
    var lastDeviceStatusUpload: NSDate?

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(loopDataUpdated(_:)), name: LoopDataManager.LoopDataUpdatedNotification, object: deviceDataManager.loopManager)
    }
    
    @objc func loopDataUpdated(note: NSNotification) {
        guard
            let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
            let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext),
            case .TempBasal = context
            else {
                return
        }

        deviceDataManager.loopManager.getLoopStatus { (predictedGlucose, recommendedTempBasal, lastTempBasal, lastLoopCompleted, insulinOnBoard, loopError) in
            
            self.deviceDataManager.loopManager.getRecommendedBolus { (bolusUnits, getBolusError) in
                if getBolusError != nil {
                    self.deviceDataManager.logger.addError(getBolusError!, fromSource: "NightscoutDataManager")
                }
                self.uploadLoopStatus(insulinOnBoard, predictedGlucose: predictedGlucose, recommendedTempBasal: recommendedTempBasal, recommendedBolus: bolusUnits, lastTempBasal: lastTempBasal, loopError: loopError ?? getBolusError)
            }
        }

        
    }
    
    private var lastTempBasalUploaded: DoseEntry?

    func uploadLoopStatus(insulinOnBoard: InsulinValue? = nil, predictedGlucose: [GlucoseValue]? = nil, recommendedTempBasal: LoopDataManager.TempBasalRecommendation? = nil, recommendedBolus: Double? = nil, lastTempBasal: DoseEntry? = nil, loopError: ErrorType? = nil) {

        guard deviceDataManager.remoteDataManager.nightscoutUploader != nil else {
            return
        }
        
        let statusTime = NSDate()
        
        let iob: IOBStatus?
        
        if let insulinOnBoard = insulinOnBoard {
            iob = IOBStatus(timestamp: insulinOnBoard.startDate, iob: insulinOnBoard.value)
        } else {
            iob = nil
        }
        
        let predicted: PredictedBG?
        if let predictedGlucose = predictedGlucose, startDate = predictedGlucose.first?.startDate {
            let values = predictedGlucose.map { $0.quantity }
            predicted = PredictedBG(startDate: startDate, values: values)
        } else {
            predicted = nil
        }

        let recommended: RecommendedTempBasal?

        if let recommendation = recommendedTempBasal {
            recommended = RecommendedTempBasal(timestamp: recommendation.recommendedDate, rate: recommendation.rate, duration: recommendation.duration)
        } else {
            recommended = nil
        }

        let loopEnacted: LoopEnacted?
        if let tempBasal = lastTempBasal where tempBasal.unit == .unitsPerHour &&
            lastTempBasalUploaded?.startDate != tempBasal.startDate {
            let duration = tempBasal.endDate.timeIntervalSinceDate(tempBasal.startDate)
            loopEnacted = LoopEnacted(rate: tempBasal.value, duration: duration, timestamp: tempBasal.startDate, received:
                true)
            lastTempBasalUploaded = tempBasal
        } else {
            loopEnacted = nil
        }
        
        let loopName = NSBundle.mainBundle().bundleDisplayName
        let loopVersion = NSBundle.mainBundle().shortVersionString

        let loopStatus = LoopStatus(name: loopName, version: loopVersion, timestamp: statusTime, iob: iob, predicted: predicted, recommendedTempBasal: recommended, recommendedBolus: recommendedBolus, enacted: loopEnacted, failureReason: loopError)
        
        uploadDeviceStatus(nil, loopStatus: loopStatus, includeUploaderStatus: false)

    }
    
    func getUploaderStatus() -> UploaderStatus {
        // Gather UploaderStatus
        let uploaderDevice = UIDevice.currentDevice()

        let battery: Int?
        if uploaderDevice.batteryMonitoringEnabled {
            battery = Int(uploaderDevice.batteryLevel * 100)
        } else {
            battery = nil
        }
        return UploaderStatus(name: uploaderDevice.name, timestamp: NSDate(), battery: battery)
    }

    func uploadDeviceStatus(pumpStatus: NightscoutUploadKit.PumpStatus? = nil, loopStatus: LoopStatus? = nil, includeUploaderStatus: Bool = true) {

        guard let uploader = deviceDataManager.remoteDataManager.nightscoutUploader else {
            return
        }
        
        if pumpStatus == nil && loopStatus == nil && includeUploaderStatus {
            // If we're just uploading phone status, limit it to once every 5 minutes
            if self.lastDeviceStatusUpload != nil && self.lastDeviceStatusUpload!.timeIntervalSinceNow > -(NSTimeInterval(minutes: 5)) {
                return
            }
        }

        let uploaderDevice = UIDevice.currentDevice()

        let uploaderStatus: UploaderStatus? = includeUploaderStatus ? getUploaderStatus() : nil

        // Build DeviceStatus
        let deviceStatus = DeviceStatus(device: "loop://\(uploaderDevice.name)", timestamp: NSDate(), pumpStatus: pumpStatus, uploaderStatus: uploaderStatus, loopStatus: loopStatus)

        self.lastDeviceStatusUpload = NSDate()
        uploader.uploadDeviceStatus(deviceStatus)
    }
}
