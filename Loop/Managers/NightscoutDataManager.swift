//
//  NightscoutDataManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import CarbKit
import HealthKit
import InsulinKit
import LoopKit
import RileyLinkKit

class NightscoutDataManager {

    unowned let deviceDataManager: DeviceDataManager
    
    // Last time we uploaded device status
    var lastDeviceStatusUpload: Date?

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager

        NotificationCenter.default.addObserver(self, selector: #selector(loopDataUpdated(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)
    }
    
    @objc func loopDataUpdated(_ note: Notification) {
        guard
            let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
            let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext),
            case .tempBasal = context
            else {
                return
        }

        deviceDataManager.loopManager.getLoopStatus { (predictedGlucose, _, recommendedTempBasal, lastTempBasal, _, insulinOnBoard, carbsOnBoard, loopError) in
            
            self.deviceDataManager.loopManager.getRecommendedBolus { (recommendation, getBolusError) in
                if let getBolusError = getBolusError {
                    self.deviceDataManager.logger.addError(getBolusError, fromSource: "NightscoutDataManager")
                }
                self.uploadLoopStatus(insulinOnBoard, carbsOnBoard: carbsOnBoard, predictedGlucose: predictedGlucose, recommendedTempBasal: recommendedTempBasal, recommendedBolus: recommendation?.amount, lastTempBasal: lastTempBasal, loopError: loopError ?? getBolusError)
            }
        }
    }
    
    private var lastTempBasalUploaded: DoseEntry?

    func uploadLoopStatus(_ insulinOnBoard: InsulinValue? = nil, carbsOnBoard: CarbValue? = nil, predictedGlucose: [GlucoseValue]? = nil, recommendedTempBasal: LoopDataManager.TempBasalRecommendation? = nil, recommendedBolus: Double? = nil, lastTempBasal: DoseEntry? = nil, loopError: Error? = nil) {

        guard deviceDataManager.remoteDataManager.nightscoutService.uploader != nil else {
            return
        }
        
        let statusTime = Date()
        
        let iob: IOBStatus?
        
        if let insulinOnBoard = insulinOnBoard {
            iob = IOBStatus(timestamp: insulinOnBoard.startDate, iob: insulinOnBoard.value)
        } else {
            iob = nil
        }

        let cob: COBStatus?

        if let carbsOnBoard = carbsOnBoard {
            cob = COBStatus(cob: carbsOnBoard.quantity.doubleValue(for: HKUnit.gram()), timestamp: carbsOnBoard.startDate)
        } else {
            cob = nil
        }
        
        let predicted: PredictedBG?
        if let predictedGlucose = predictedGlucose, let startDate = predictedGlucose.first?.startDate {
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
        if let tempBasal = lastTempBasal, tempBasal.unit == .unitsPerHour &&
            lastTempBasalUploaded?.startDate != tempBasal.startDate {
            let duration = tempBasal.endDate.timeIntervalSince(tempBasal.startDate)
            loopEnacted = LoopEnacted(rate: tempBasal.value, duration: duration, timestamp: tempBasal.startDate, received:
                true)
            lastTempBasalUploaded = tempBasal
        } else {
            loopEnacted = nil
        }
        
        let loopName = Bundle.main.bundleDisplayName
        let loopVersion = Bundle.main.shortVersionString

        let loopStatus = LoopStatus(name: loopName, version: loopVersion, timestamp: statusTime, iob: iob, cob: cob, predicted: predicted, recommendedTempBasal: recommended, recommendedBolus: recommendedBolus, enacted: loopEnacted, failureReason: loopError)
        
        uploadDeviceStatus(nil, loopStatus: loopStatus, includeUploaderStatus: false)

    }
    
    func getUploaderStatus() -> UploaderStatus {
        // Gather UploaderStatus
        let uploaderDevice = UIDevice.current

        let battery: Int?
        if uploaderDevice.isBatteryMonitoringEnabled {
            battery = Int(uploaderDevice.batteryLevel * 100)
        } else {
            battery = nil
        }
        return UploaderStatus(name: uploaderDevice.name, timestamp: Date(), battery: battery)
    }

    func uploadDeviceStatus(_ pumpStatus: NightscoutUploadKit.PumpStatus? = nil, loopStatus: LoopStatus? = nil, rileylinkDevice: RileyLinkKit.RileyLinkDevice? = nil, includeUploaderStatus: Bool = true) {

        guard let uploader = deviceDataManager.remoteDataManager.nightscoutService.uploader else {
            return
        }
        
        if pumpStatus == nil && loopStatus == nil && includeUploaderStatus {
            // If we're just uploading phone status, limit it to once every 5 minutes
            if self.lastDeviceStatusUpload != nil && self.lastDeviceStatusUpload!.timeIntervalSinceNow > -(TimeInterval(minutes: 5)) {
                return
            }
        }

        let uploaderDevice = UIDevice.current

        let uploaderStatus: UploaderStatus? = includeUploaderStatus ? getUploaderStatus() : nil

        var radioAdapter: NightscoutUploadKit.RadioAdapter? = nil

        if let device = rileylinkDevice {
            radioAdapter = NightscoutUploadKit.RadioAdapter(hardware: "RileyLink", frequency: device.radioFrequency, name: device.name ?? "Unknown", lastTuned: device.lastTuned, firmwareVersion: device.firmwareVersion ?? "Unknown", RSSI: device.RSSI, pumpRSSI: device.pumpRSSI)
        }

        // Build DeviceStatus
        let deviceStatus = DeviceStatus(device: "loop://\(uploaderDevice.name)", timestamp: Date(), pumpStatus: pumpStatus, uploaderStatus: uploaderStatus, loopStatus: loopStatus, radioAdapter: radioAdapter)

        self.lastDeviceStatusUpload = Date()
        uploader.uploadDeviceStatus(deviceStatus)
    }
}
