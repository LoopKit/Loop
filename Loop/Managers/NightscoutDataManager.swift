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

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager

        // Temporarily disabled, until new code for uploading to new NS 'loop' plugin is in place
        //NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(loopDataUpdated(_:)), name: LoopDataManager.LoopDataUpdatedNotification, object: deviceDataManager.loopManager)
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

    private func uploadLoopStatus(insulinOnBoard: InsulinValue?, predictedGlucose: [GlucoseValue]?, recommendedTempBasal: LoopDataManager.TempBasalRecommendation?, recommendedBolus: Double?, lastTempBasal: DoseEntry?, loopError: ErrorType?) {

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
        
        let eventualBG = predictedGlucose?.last?.quantity
        
        let loopSuggested: LoopSuggested?

        let glucoseVal = predictedGlucose?.first?.quantity
        
        let predBGs: PredictedBG?
        
        if let predicted = predictedGlucose {
            let values = predicted.map { $0.quantity }
            predBGs = PredictedBG(values: values)
        } else {
            predBGs = nil
        }

        // If the last recommendedTempBasal was successfully enacted, then lastTempBasal will be set, and
        // recommendedTempBasal will be nil. We can use lastTempBasal in lieu of recommendedTempBasal in this
        // case to populate the 'suggested' fields for NS.
        let suggestedTimestamp: NSDate?
        let suggestedRate: Double?
        let suggestedDuration: NSTimeInterval?

        if let recommendation = recommendedTempBasal {
            suggestedTimestamp = recommendation.recommendedDate
            suggestedRate = recommendation.rate
            suggestedDuration = recommendation.duration
        } else if let tempBasal = lastTempBasal where tempBasal.unit == .unitsPerHour {
            suggestedTimestamp = tempBasal.startDate
            suggestedRate = tempBasal.value
            suggestedDuration = tempBasal.endDate.timeIntervalSinceDate(tempBasal.startDate)
        } else {
            suggestedTimestamp = nil
            suggestedRate = nil
            suggestedDuration = nil
        }

        if let suggestedTimestamp = suggestedTimestamp, suggestedRate = suggestedRate, suggestedDuration = suggestedDuration, glucoseVal = glucoseVal, eventualBG = eventualBG
        {
            loopSuggested = LoopSuggested(timestamp: suggestedTimestamp, rate: suggestedRate, duration: suggestedDuration, eventualBG: eventualBG, bg: glucoseVal, correction: recommendedBolus, predBGs: predBGs)
        } else {
            loopSuggested = nil
        }
        
        let loopEnacted: LoopEnacted?
        if let tempBasal = lastTempBasal where tempBasal.unit == .unitsPerHour &&
            lastTempBasalUploaded?.startDate != tempBasal.startDate {
            let duration = tempBasal.endDate.timeIntervalSinceDate(tempBasal.startDate)
            loopEnacted = LoopEnacted(rate: tempBasal.value, duration: duration, timestamp: tempBasal.startDate, received:
                true)
            lastTempBasalUploaded = tempBasal
        } else if let recommendation = recommendedTempBasal {
            // notEnacted
            loopEnacted = LoopEnacted(rate: recommendation.rate, duration: recommendation.duration, timestamp: recommendation.recommendedDate, received: false)
        } else {
            loopEnacted = nil
        }
        
        let loopName = NSBundle.mainBundle().bundleDisplayName
        let loopVersion = NSBundle.mainBundle().shortVersionString

        let loopStatus = LoopStatus(name: loopName, version: loopVersion, timestamp: statusTime, iob: iob, suggested: loopSuggested, enacted: loopEnacted, failureReason: loopError)
        
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

        let uploaderDevice = UIDevice.currentDevice()

        let uploaderStatus: UploaderStatus? = includeUploaderStatus ? getUploaderStatus() : nil

        // Build DeviceStatus
        let deviceStatus = DeviceStatus(device: "loop://\(uploaderDevice.name)", timestamp: NSDate(), pumpStatus: pumpStatus, uploaderStatus: uploaderStatus, loopStatus: loopStatus)

        uploader.uploadDeviceStatus(deviceStatus)
    }
}
