//
//  DeviceDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import CarbKit
import GlucoseKit
import HealthKit
import InsulinKit
import LoopKit
import MinimedKit
import RileyLinkKit
import WatchConnectivity
import xDripG5

enum State<T> {
    case NeedsConfiguration
    case Ready(T)
}


class DeviceDataManager: NSObject, CarbStoreDelegate, TransmitterDelegate, WCSessionDelegate {
    static let GlucoseUpdatedNotification = "com.loudnate.Naterade.notification.GlucoseUpdated"
    static let PumpStatusUpdatedNotification = "com.loudnate.Naterade.notification.PumpStatusUpdated"

    enum Error: ErrorType {
        case ValueError(String)
    }

    // MARK: - Observed state

    lazy var logger = DiagnosticLogger()

    let rileyLinkManager: RileyLinkDeviceManager

    var transmitter: Transmitter? {
        switch transmitterState {
        case .Ready(let transmitter):
            return transmitter
        case .NeedsConfiguration:
            return nil
        }
    }

    // MARK: - RileyLink

    var rileyLinkManagerObserver: AnyObject? {
        willSet {
            if let observer = rileyLinkManagerObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    var rileyLinkDevicePacketObserver: AnyObject? {
        willSet {
            if let observer = rileyLinkDevicePacketObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    func receivedRileyLinkManagerNotification(note: NSNotification) {
        NSNotificationCenter.defaultCenter().postNotificationName(note.name, object: self, userInfo: note.userInfo)
    }

    func receivedRileyLinkPacketNotification(note: NSNotification) {
        if let
            device = note.object as? RileyLinkDevice,
            data = note.userInfo?[RileyLinkDevice.IdleMessageDataKey] as? NSData,
            message = PumpMessage(rxData: data)
        {
            switch message.packetType {
            case .MySentry:
                switch message.messageBody {
                case let body as MySentryPumpStatusMessageBody:
                    updatePumpStatus(body, fromDevice: device)
                case is MySentryAlertMessageBody:
                    break
                    // TODO: de-dupe
//                    logger?.addMessage(body.dictionaryRepresentation, toCollection: "sentryAlert")
                case is MySentryAlertClearedMessageBody:
                    break
                    // TODO: de-dupe
//                    logger?.addMessage(body.dictionaryRepresentation, toCollection: "sentryAlert")
                case let body as UnknownMessageBody:
                    logger?.addMessage(body.dictionaryRepresentation, toCollection: "sentryOther")
                default:
                    break
                }
            default:
                break
            }
        }
    }

    func connectToRileyLink(device: RileyLinkDevice) {
        connectedPeripheralIDs.insert(device.peripheral.identifier.UUIDString)

        rileyLinkManager.connectDevice(device)
    }

    func disconnectFromRileyLink(device: RileyLinkDevice) {
        connectedPeripheralIDs.remove(device.peripheral.identifier.UUIDString)

        rileyLinkManager.disconnectDevice(device)
    }

    private func updatePumpStatus(status: MySentryPumpStatusMessageBody, fromDevice device: RileyLinkDevice) {
        status.pumpDateComponents.timeZone = pumpTimeZone

        if status != latestPumpStatus, let pumpDate = status.pumpDateComponents.date {
            latestPumpStatus = status

            doseStore.addReservoirValue(status.reservoirRemainingUnits, atDate: pumpDate) { (newValue, previousValue, error) -> Void in
                if let error = error {
                    self.logger?.addError(error, fromSource: "DoseStore")
                } else {
                    NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.PumpStatusUpdatedNotification, object: self)
                }

                if let newVolume = newValue?.unitVolume, previousVolume = previousValue?.unitVolume {
                    self.checkPumpReservoirForAmount(newVolume, previousAmount: previousVolume, timeLeft: NSTimeInterval(minutes: Double(status.reservoirRemainingMinutes)))
                }
            }

            if status.batteryRemainingPercent == 0 {
                NotificationManager.sendPumpBatteryLowNotification()
            }
        }
    }

    private func checkPumpReservoirForAmount(newAmount: Double, previousAmount: Double, timeLeft: NSTimeInterval) {

        guard newAmount > 0 else {
            NotificationManager.sendPumpReservoirEmptyNotification()
            return
        }

        let warningThresholds: [Double] = [10, 20, 30]

        for threshold in warningThresholds {
            if newAmount <= threshold && previousAmount > threshold {
                NotificationManager.sendPumpReservoirLowNotificationForAmount(newAmount, andTimeRemaining: timeLeft)
                return
            }
        }
    }

    // MARK: - Transmitter

    // MARK: TransmitterDelegate

    func transmitter(transmitter: Transmitter, didError error: ErrorType) {
        logger?.addMessage([
            "error": "\(error)",
            "collectedAt": NSDateFormatter.ISO8601StrictDateFormatter().stringFromDate(NSDate())
            ], toCollection: "g5"
        )

        self.rileyLinkManager.firstConnectedDevice?.assertIdleListening()
    }

    func transmitter(transmitter: Transmitter, didReadGlucose glucose: GlucoseRxMessage) {
        transmitterStartTime = transmitter.startTimeInterval

        if glucose != latestGlucoseMessage {
            latestGlucoseMessage = glucose

            if glucose.glucose >= 20, let transmitterStartTime = transmitterStartTime, glucoseStore = glucoseStore {
                let quantity = HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: Double(glucose.glucose))

                let startDate = NSDate(timeIntervalSince1970: transmitterStartTime).dateByAddingTimeInterval(NSTimeInterval(glucose.timestamp))

                let device = HKDevice(name: "xDripG5", manufacturer: "Dexcom", model: "G5 Mobile", hardwareVersion: nil, firmwareVersion: nil, softwareVersion: String(xDripG5VersionNumber), localIdentifier: nil, UDIDeviceIdentifier: "00386270000002")

                glucoseStore.addGlucose(quantity, date: startDate, displayOnly: glucose.glucoseIsDisplayOnly, device: device, resultHandler: { (_, value, error) -> Void in
                    if let error = error {
                        self.logger?.addError(error, fromSource: "GlucoseStore")
                    }

                    NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
                })

                updateWatch()
            } else {
                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
            }
        }

        self.rileyLinkManager.firstConnectedDevice?.assertIdleListening()
    }

    // MARK: - Managed state

    var transmitterStartTime: NSTimeInterval? = NSUserDefaults.standardUserDefaults().transmitterStartTime {
        didSet {
            if oldValue != transmitterStartTime {
                NSUserDefaults.standardUserDefaults().transmitterStartTime = transmitterStartTime
            }
        }
    }

    var latestGlucoseMessage: GlucoseRxMessage?

    var latestPumpStatus: MySentryPumpStatusMessageBody?

    // TODO: Keep a single copy of this value in PumpState
    var pumpTimeZone: NSTimeZone? = NSUserDefaults.standardUserDefaults().pumpTimeZone {
        didSet {
            NSUserDefaults.standardUserDefaults().pumpTimeZone = pumpTimeZone

            if let pumpTimeZone = pumpTimeZone {
                if let basalRateSchedule = basalRateSchedule {
                    self.basalRateSchedule = BasalRateSchedule(dailyItems: basalRateSchedule.items, timeZone: pumpTimeZone)
                }

                if let carbRatioSchedule = carbRatioSchedule {
                    self.carbRatioSchedule = CarbRatioSchedule(unit: carbRatioSchedule.unit, dailyItems: carbRatioSchedule.items, timeZone: pumpTimeZone)
                }

                if let insulinSensitivitySchedule = insulinSensitivitySchedule {
                    self.insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: insulinSensitivitySchedule.unit, dailyItems: insulinSensitivitySchedule.items, timeZone: pumpTimeZone)
                }

                if let glucoseTargetRangeSchedule = glucoseTargetRangeSchedule {
                    self.glucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: glucoseTargetRangeSchedule.unit, dailyItems: glucoseTargetRangeSchedule.items, timeZone: pumpTimeZone)
                }

                if let pumpState = rileyLinkManager.pumpState {
                    pumpState.timeZone = pumpTimeZone
                }
            }
        }
    }

    var transmitterState: State<Transmitter> = .NeedsConfiguration {
        didSet {
            switch transmitterState {
            case .Ready(let transmitter):
                transmitter.delegate = self
            case .NeedsConfiguration:
                break
            }
        }
    }

    var connectedPeripheralIDs: Set<String> = Set(NSUserDefaults.standardUserDefaults().connectedPeripheralIDs) {
        didSet {
            NSUserDefaults.standardUserDefaults().connectedPeripheralIDs = Array(connectedPeripheralIDs)
        }
    }

    // TODO: Store this in PumpState
    var pumpID: String? = NSUserDefaults.standardUserDefaults().pumpID {
        didSet {
            if pumpID?.characters.count != 6 {
                pumpID = nil
            }

            if let pumpID = pumpID {
                let pumpState = PumpState(pumpID: pumpID)

                if let timeZone = pumpTimeZone {
                    pumpState.timeZone = timeZone
                }

                rileyLinkManager.pumpState = pumpState
            } else {
                rileyLinkManager.pumpState = nil
            }

            doseStore.pumpID = pumpID

            NSUserDefaults.standardUserDefaults().pumpID = pumpID
        }
    }

    var transmitterID: String? {
        didSet {
            if transmitterID?.characters.count != 6 {
                transmitterID = nil
            }

            switch (transmitterState, transmitterID) {
            case (.NeedsConfiguration, let transmitterID?):
                transmitterState = .Ready(Transmitter(
                    ID: transmitterID,
                    startTimeInterval: NSUserDefaults.standardUserDefaults().transmitterStartTime,
                    passiveModeEnabled: true
                ))
            case (.Ready, .None):
                transmitterState = .NeedsConfiguration
            case (.Ready(let transmitter), let transmitterID?):
                transmitter.ID = transmitterID
                transmitter.startTimeInterval = nil
            case (.NeedsConfiguration, .None):
                break
            }

            NSUserDefaults.standardUserDefaults().transmitterID = transmitterID
        }
    }

    var basalRateSchedule: BasalRateSchedule? = NSUserDefaults.standardUserDefaults().basalRateSchedule {
        didSet {
            doseStore.basalProfile = basalRateSchedule

            NSUserDefaults.standardUserDefaults().basalRateSchedule = basalRateSchedule
        }
    }

    var carbRatioSchedule: CarbRatioSchedule? = NSUserDefaults.standardUserDefaults().carbRatioSchedule {
        didSet {
            carbStore?.carbRatioSchedule = carbRatioSchedule

            NSUserDefaults.standardUserDefaults().carbRatioSchedule = carbRatioSchedule
        }
    }

    var insulinActionDuration: NSTimeInterval? = NSUserDefaults.standardUserDefaults().insulinActionDuration {
        didSet {
            doseStore.insulinActionDuration = insulinActionDuration

            NSUserDefaults.standardUserDefaults().insulinActionDuration = insulinActionDuration
        }
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule? = NSUserDefaults.standardUserDefaults().insulinSensitivitySchedule {
        didSet {
            carbStore?.insulinSensitivitySchedule = insulinSensitivitySchedule
            doseStore.insulinSensitivitySchedule = insulinSensitivitySchedule

            NSUserDefaults.standardUserDefaults().insulinSensitivitySchedule = insulinSensitivitySchedule
        }
    }

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule? = NSUserDefaults.standardUserDefaults().glucoseTargetRangeSchedule {
        didSet {
            NSUserDefaults.standardUserDefaults().glucoseTargetRangeSchedule = glucoseTargetRangeSchedule
        }
    }

    var maximumBasalRatePerHour: Double? = NSUserDefaults.standardUserDefaults().maximumBasalRatePerHour {
        didSet {
            NSUserDefaults.standardUserDefaults().maximumBasalRatePerHour = maximumBasalRatePerHour
        }
    }

    var maximumBolus: Double? = NSUserDefaults.standardUserDefaults().maximumBolus {
        didSet {
            NSUserDefaults.standardUserDefaults().maximumBolus = maximumBolus
        }
    }

    // MARK: - CarbKit

    let carbStore: CarbStore?

    // MARK: CarbStoreDelegate

    func carbStore(_: CarbStore, didError error: CarbStore.Error) {
        logger?.addError(error, fromSource: "CarbStore")
    }

    // MARK: - GlucoseKit

    let glucoseStore: GlucoseStore? = GlucoseStore()

    // MARK: - InsulinKit

    let doseStore: DoseStore

    // MARK: - WatchKit

    private var watchSession: WCSession? = {
        if WCSession.isSupported() {
            return WCSession.defaultSession()
        } else {
            return nil
        }
    }()

    private func updateWatch() {
        if let session = watchSession {
            switch session.activationState {
            case .NotActivated, .Inactive:
                session.activateSession()
            case .Activated:
                sendWatchContext()
            }
        }
    }

    private var latestComplicationGlucose: GlucoseRxMessage?

    private func sendWatchContext() {
        if let session = watchSession where session.paired && session.watchAppInstalled {
            let userInfo = WatchContext(pumpStatus: latestPumpStatus, glucose: latestGlucoseMessage, transmitterStartTime: transmitterStartTime).rawValue

            let complicationShouldUpdate: Bool

            if let complicationGlucose = latestComplicationGlucose, glucose = latestGlucoseMessage {
                complicationShouldUpdate = Int(glucose.timestamp) - Int(complicationGlucose.timestamp) >= 30 * 60 || abs(Int(glucose.glucose) - Int(complicationGlucose.glucose)) >= 20
            } else {
                complicationShouldUpdate = true
            }

            if session.complicationEnabled && complicationShouldUpdate, let glucose = latestGlucoseMessage {
                session.transferCurrentComplicationUserInfo(userInfo)
                latestComplicationGlucose = glucose
            } else {
                do {
                    try session.updateApplicationContext(userInfo)
                } catch let error {
                    self.logger?.addError(error, fromSource: "WCSession")
                }
            }
        }
    }

    private func addCarbEntryFromWatchMessage(message: [String: AnyObject], completionHandler: ((units: Double?, error: ErrorType?) -> Void)? = nil) {
        if let carbStore = carbStore, carbEntry = CarbEntryUserInfo(rawValue: message) {
            let newEntry = NewCarbEntry(
                quantity: HKQuantity(unit: carbStore.preferredUnit, doubleValue: carbEntry.value),
                startDate: carbEntry.startDate,
                foodType: nil,
                absorptionTime: carbEntry.absorptionTimeType.absorptionTimeFromDefaults(carbStore.defaultAbsorptionTimes)
            )

            loopManager.addCarbEntryAndRecommendBolus(newEntry) { (units, error) in
                if let error = error {
                    self.logger?.addError(error, fromSource: error is CarbStore.Error ? "CarbStore" : "Bolus")
                }

                completionHandler?(units: units, error: error)
            }
        } else {
            completionHandler?(units: nil, error: Error.ValueError("Unable to parse CarbEntryUserInfo: \(message)"))
        }
    }

    // MARK: WCSessionDelegate

    func session(session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String: AnyObject]) -> Void) {
        switch message["name"] as? String {
        case CarbEntryUserInfo.name?:
            addCarbEntryFromWatchMessage(message) { (units, error) in
                replyHandler(BolusSuggestionUserInfo(recommendedBolus: units ?? 0).rawValue)
            }
        case SetBolusUserInfo.name?:
            if let bolus = SetBolusUserInfo(rawValue: message) {
                self.loopManager.enactBolus(bolus.value) { (success, error) in
                    if !success {
                        NotificationManager.sendBolusFailureNotificationForAmount(bolus.value, atDate: bolus.startDate)
                    }

                    replyHandler([:])
                }
            } else {
                replyHandler([:])
            }
        default:
            break
        }
    }

    func session(session: WCSession, didReceiveUserInfo userInfo: [String : AnyObject]) {
        addCarbEntryFromWatchMessage(userInfo)
    }

    func session(session: WCSession, activationDidCompleteWithState activationState: WCSessionActivationState, error: NSError?) {
        switch activationState {
        case .Activated:
            if let error = error {
                logger?.addError(error, fromSource: "WCSession")
            }
        case .Inactive, .NotActivated:
            break
        }
    }

    func sessionDidBecomeInactive(session: WCSession) {
        // Nothing to do here
    }

    func sessionDidDeactivate(session: WCSession) {
        watchSession = WCSession.defaultSession()
        watchSession?.delegate = self
        watchSession?.activateSession()
    }

    // MARK: - Initialization

    static let sharedManager = DeviceDataManager()

    private(set) var loopManager: LoopDataManager!

    override init() {
        doseStore = DoseStore(
            pumpID: pumpID,
            insulinActionDuration: insulinActionDuration,
            basalProfile: basalRateSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
        )
        carbStore = CarbStore(
            carbRatioSchedule: carbRatioSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
        )

        let pumpState: PumpState?

        if let pumpID = pumpID {
            pumpState = PumpState(pumpID: pumpID)

            if let timeZone = pumpTimeZone {
                pumpState?.timeZone = timeZone
            }
        } else {
            pumpState = nil
        }

        rileyLinkManager = RileyLinkDeviceManager(
            pumpState: pumpState,
            autoConnectIDs: connectedPeripheralIDs
        )

        super.init()

        rileyLinkManager.timerTickEnabled = false
        rileyLinkManagerObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: rileyLinkManager, queue: nil) { [weak self] (note) -> Void in
            self?.receivedRileyLinkManagerNotification(note)
        }

        // TODO: Use delegation instead.
        rileyLinkDevicePacketObserver = NSNotificationCenter.defaultCenter().addObserverForName(RileyLinkDevice.DidReceiveIdleMessageNotification, object: nil, queue: nil) { [weak self] (note) -> Void in
            self?.receivedRileyLinkPacketNotification(note)
        }

        loopManager = LoopDataManager(deviceDataManager: self)

        watchSession?.delegate = self
        watchSession?.activateSession()

        carbStore?.delegate = self

        defer {
            transmitterID = NSUserDefaults.standardUserDefaults().transmitterID
        }
    }

    deinit {
        rileyLinkManagerObserver = nil
        rileyLinkDevicePacketObserver = nil
    }
}


extension WatchContext {
    convenience init(pumpStatus: MySentryPumpStatusMessageBody?, glucose: GlucoseRxMessage?, transmitterStartTime: NSTimeInterval?) {
        self.init()

        if let glucose = glucose, transmitterStartTime = transmitterStartTime where glucose.state > 5 {
            glucoseValue = Int(glucose.glucose)
            glucoseTrend = Int(glucose.trend)
            glucoseDate = NSDate(timeIntervalSince1970: transmitterStartTime).dateByAddingTimeInterval(NSTimeInterval(glucose.timestamp))
        }

        if let status = pumpStatus, date = status.pumpDateComponents.date {
            IOB = status.iob
            reservoir = status.reservoirRemainingUnits
            pumpDate = date
        }
    }
}

