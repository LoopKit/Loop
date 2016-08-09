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
//import CarbKit
import InsulinKit
import LoopKit
//import MinimedKit


class NightscoutDataManager {

    unowned let deviceDataManager: DeviceDataManager

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
        
        deviceDataManager.loopManager.getLoopStatus { (predictedGlucose, recommendedTempBasal, lastTempBasal, lastLoopCompleted, insulinOnBoard, lastLoopError) in
            
            self.deviceDataManager.loopManager.getRecommendedBolus { (bolusUnits, error) in
                if error != nil {
                    self.deviceDataManager.logger.addError(error!, fromSource: "LoopManager")
                }
                self.uploadLoopStatus(insulinOnBoard, predictedGlucose: predictedGlucose, recommendedTempBasal: recommendedTempBasal, recommendedBolus: bolusUnits, lastTempBasal: lastTempBasal, lastLoopError: lastLoopError)
            }
        }

        
    }
    
    private var lastTempBasalUploaded: DoseEntry?

    private func uploadLoopStatus(insulinOnBoard: InsulinValue?, predictedGlucose: [GlucoseValue]?, recommendedTempBasal: LoopDataManager.TempBasalRecommendation?, recommendedBolus: Double?, lastTempBasal: DoseEntry?, lastLoopError: ErrorType?) {
        
        let statusTime = NSDate()
        
        // Is this just predictedGlucose[0]?
        let glucose = deviceDataManager.glucoseStore?.latestGlucose
        
        let iob: IOBStatus?
        
        if let insulinOnBoard = insulinOnBoard {
            iob = IOBStatus(timestamp: insulinOnBoard.startDate, iob: insulinOnBoard.value)
        } else {
            iob = nil
        }
        
        let eventualBG = predictedGlucose?.last?.quantity
        
        let loopSuggested: LoopSuggested?
        
        let glucoseVal = glucose?.quantity
        
        let predBGs: PredictedBG?
        
        if let predicted = predictedGlucose {
            let values = predicted.map({ (value) -> HKQuantity in
                value.quantity
            })
            predBGs = PredictedBG(values: values)
        } else {
            predBGs = nil
        }
        
        if let recommendation = recommendedTempBasal, let glucoseVal = glucoseVal, let eventualBG = eventualBG {
            loopSuggested = LoopSuggested(timestamp: recommendation.recommendedDate, rate: recommendation.rate, duration: recommendation.duration, eventualBG: eventualBG, bg: glucoseVal, correction: recommendedBolus, predBGs: predBGs)
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
        
        let loopStatus = LoopStatus(name: loopName, version: loopVersion, timestamp: statusTime, iob: iob, suggested: loopSuggested, enacted: loopEnacted, failureReason: lastLoopError)
        
        deviceDataManager.remoteDataManager.uploadDeviceStatus(nil, loopStatus: loopStatus)

    }

}
