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
import LoopKit


final class NightscoutDataManager {

    unowned let deviceManager: DeviceDataManager
    
    // Last time we uploaded device status
    var lastDeviceStatusUpload: Date?

    init(deviceDataManager: DeviceDataManager) {
        self.deviceManager = deviceDataManager

        NotificationCenter.default.addObserver(self, selector: #selector(loopDataUpdated(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)
    }
    
    @objc func loopDataUpdated(_ note: Notification) {
        guard
            deviceManager.remoteDataManager.nightscoutService.uploader != nil,
            let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
            let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext),
            case .tempBasal = context
        else {
            return
        }

        deviceManager.loopManager.getLoopState { (manager, state) in
            var loopError = state.error
            let recommendedBolus: Double?

            recommendedBolus = state.recommendedBolus?.recommendation.amount

            let carbsOnBoard = state.carbsOnBoard
            let predictedGlucose = state.predictedGlucose
            let recommendedTempBasal = state.recommendedTempBasal
            let lastTempBasal = state.lastTempBasal

            manager.doseStore.insulinOnBoard(at: Date()) { (result) in
                let insulinOnBoard: InsulinValue?

                switch result {
                case .success(let value):
                    insulinOnBoard = value
                case .failure(let error):
                    insulinOnBoard = nil

                    if loopError == nil {
                        loopError = error
                    }
                }

                self.uploadLoopStatus(
                    insulinOnBoard: insulinOnBoard,
                    carbsOnBoard: carbsOnBoard,
                    predictedGlucose: predictedGlucose,
                    recommendedTempBasal: recommendedTempBasal,
                    recommendedBolus: recommendedBolus,
                    lastTempBasal: lastTempBasal,
                    loopError: loopError
                )
            }
        }
    }
    
    private var lastTempBasalUploaded: DoseEntry?

    func uploadLoopStatus(insulinOnBoard: InsulinValue? = nil, carbsOnBoard: CarbValue? = nil, predictedGlucose: [GlucoseValue]? = nil, recommendedTempBasal: (recommendation: TempBasalRecommendation, date: Date)? = nil, recommendedBolus: Double? = nil, lastTempBasal: DoseEntry? = nil, loopError: Error? = nil) {

        guard deviceManager.remoteDataManager.nightscoutService.uploader != nil else {
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

        if let (recommendation: recommendation, date: date) = recommendedTempBasal {
            recommended = RecommendedTempBasal(timestamp: date, rate: recommendation.unitsPerHour, duration: recommendation.duration)
        } else {
            recommended = nil
        }

        let loopEnacted: LoopEnacted?
        if let tempBasal = lastTempBasal, lastTempBasalUploaded?.startDate != tempBasal.startDate {
            let duration = tempBasal.endDate.timeIntervalSince(tempBasal.startDate)
            loopEnacted = LoopEnacted(rate: tempBasal.unitsPerHour, duration: duration, timestamp: tempBasal.startDate, received:
                true)
            lastTempBasalUploaded = tempBasal
        } else {
            loopEnacted = nil
        }
        
        let loopName = Bundle.main.bundleDisplayName
        let loopVersion = Bundle.main.shortVersionString

        let loopStatus = LoopStatus(name: loopName, version: loopVersion, timestamp: statusTime, iob: iob, cob: cob, predicted: predicted, recommendedTempBasal: recommended, recommendedBolus: recommendedBolus, enacted: loopEnacted, failureReason: loopError)
       
        
        
        let pumpStatus: NightscoutUploadKit.PumpStatus?
        
        if let pumpManagerStatus = deviceManager.pumpManagerStatus
        {
            
            let battery: BatteryStatus?
            
            if let chargeRemaining = pumpManagerStatus.pumpBatteryChargeRemaining {
                battery = BatteryStatus(percent: Int(round(chargeRemaining * 100)), voltage: nil, status: nil)
            } else {
                battery = nil
            }
            
            let bolusing: Bool
            if case .inProgress = pumpManagerStatus.bolusState {
                bolusing = true
            } else {
                bolusing = false
            }
            
            pumpStatus = NightscoutUploadKit.PumpStatus(
                clock: Date(),
                pumpID: pumpManagerStatus.device.localIdentifier ?? "Unknown",
                iob: nil,
                battery: battery,
                suspended: pumpManagerStatus.basalDeliveryState == .suspended,
                bolusing: bolusing,
                reservoir: deviceManager.loopManager.doseStore.lastReservoirValue?.unitVolume,
                secondsFromGMT: pumpManagerStatus.timeZone.secondsFromGMT())
        } else {
            pumpStatus = nil
        }
        
        upload(pumpStatus: pumpStatus, loopStatus: loopStatus, deviceName: nil, firmwareVersion: nil, uploaderStatus: getUploaderStatus())

    }
    
    private func getUploaderStatus() -> UploaderStatus {
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

    func upload(pumpStatus: NightscoutUploadKit.PumpStatus?, deviceName: String?, firmwareVersion: String?) {
        upload(pumpStatus: pumpStatus, loopStatus: nil, deviceName: deviceName, firmwareVersion: firmwareVersion, uploaderStatus: nil)
    }

    private func upload(pumpStatus: NightscoutUploadKit.PumpStatus?, loopStatus: LoopStatus?, deviceName: String?, firmwareVersion: String?, uploaderStatus: UploaderStatus?) {

        guard let uploader = deviceManager.remoteDataManager.nightscoutService.uploader else {
            return
        }
        
        if pumpStatus == nil && loopStatus == nil && uploaderStatus != nil {
            // If we're just uploading phone status, limit it to once every 5 minutes
            if self.lastDeviceStatusUpload != nil && self.lastDeviceStatusUpload!.timeIntervalSinceNow > -(TimeInterval(minutes: 5)) {
                return
            }
        }

        let uploaderDevice = UIDevice.current

        // Build DeviceStatus
        let deviceStatus = DeviceStatus(device: "loop://\(uploaderDevice.name)", timestamp: Date(), pumpStatus: pumpStatus, uploaderStatus: uploaderStatus, loopStatus: loopStatus, radioAdapter: nil)

        self.lastDeviceStatusUpload = Date()
        uploader.uploadDeviceStatus(deviceStatus)
    }

    func uploadGlucose(_ values: [GlucoseValue], sensorState: SensorDisplayable?) {
        guard let uploader = deviceManager.remoteDataManager.nightscoutService.uploader else {
            return
        }

        let device = "loop://\(UIDevice.current.name)"
        let direction: String? = {
            switch sensorState?.trendType {
            case .up?:
                return "SingleUp"
            case .upUp?, .upUpUp?:
                return "DoubleUp"
            case .down?:
                return "SingleDown"
            case .downDown?, .downDownDown?:
                return "DoubleDown"
            case .flat?:
                return "Flat"
            case .none:
                return nil
            }
        }()

        for value in values {
            uploader.uploadSGV(
                glucoseMGDL: Int(value.quantity.doubleValue(for: .milligramsPerDeciliter)),
                at: value.startDate,
                direction: direction,
                device: device
            )
        }
    }
}

