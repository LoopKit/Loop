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
import ShareClient
import WatchConnectivity
import xDripG5

enum State<T> {
    case NeedsConfiguration
    case Ready(T)
}


class DeviceDataManager: NSObject, CarbStoreDelegate, TransmitterDelegate, WCSessionDelegate {
    /// Notification posted by the instance when new glucose data was processed
    static let GlucoseUpdatedNotification = "com.loudnate.Naterade.notification.GlucoseUpdated"

    /// Notification posted by the instance when new pump data was processed
    static let PumpStatusUpdatedNotification = "com.loudnate.Naterade.notification.PumpStatusUpdated"

    enum Error: ErrorType {
        case ValueError(String)
    }

    // MARK: - Utilities

    lazy var logger = DiagnosticLogger()

    /// Manages all the RileyLinks
    let rileyLinkManager: RileyLinkDeviceManager

    /// The share server client
    private let shareClient: ShareClient?

    /// The G5 transmitter object
    var transmitter: Transmitter? {
        switch transmitterState {
        case .Ready(let transmitter):
            return transmitter
        case .NeedsConfiguration:
            return nil
        }
    }

    // MARK: - RileyLink

    private var rileyLinkManagerObserver: AnyObject? {
        willSet {
            if let observer = rileyLinkManagerObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    private var rileyLinkDevicePacketObserver: AnyObject? {
        willSet {
            if let observer = rileyLinkDevicePacketObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    private func receivedRileyLinkManagerNotification(note: NSNotification) {
        NSNotificationCenter.defaultCenter().postNotificationName(note.name, object: self, userInfo: note.userInfo)
    }

    private func receivedRileyLinkPacketNotification(note: NSNotification) {
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
                case is MySentryAlertMessageBody, is MySentryAlertClearedMessageBody:
                    break
                case let body:
                    logger?.addMessage(["messageType": Int(message.messageType.rawValue), "messageBody": body.txData.hexadecimalString], toCollection: "sentryOther")
                }
            default:
                break
            }
        }
    }

    func connectToRileyLink(device: RileyLinkDevice) {
        connectedPeripheralIDs.insert(device.peripheral.identifier.UUIDString)

        rileyLinkManager.connectDevice(device)

        AnalyticsManager.didChangeRileyLinkConnectionState()
    }

    func disconnectFromRileyLink(device: RileyLinkDevice) {
        connectedPeripheralIDs.remove(device.peripheral.identifier.UUIDString)

        rileyLinkManager.disconnectDevice(device)

        AnalyticsManager.didChangeRileyLinkConnectionState()
    }

    // MARK: Pump data

    var latestPumpStatus: MySentryPumpStatusMessageBody?

    var latestReservoirValue: ReservoirValue?

    /**
     Handles receiving a MySentry status message, which are only posted by MM x23 pumps.
     
     This message has two important pieces of info about the pump: reservoir volume and battery.

     Because the RileyLink must actively listen for these packets, they are not the most reliable heartbeat. However, we can still use them to assert glucose data is current.

     - parameter status: The status message body
     - parameter device: The RileyLink that received the message
     */
    private func updatePumpStatus(status: MySentryPumpStatusMessageBody, fromDevice device: RileyLinkDevice) {
        status.pumpDateComponents.timeZone = pumpState?.timeZone

        // The pump sends the same message 3x, so ignore it if we've already seen it.
        guard status != latestPumpStatus, let pumpDate = status.pumpDateComponents.date else {
            return
        }

        latestPumpStatus = status

        backfillGlucoseFromShareIfNeeded()

        updateReservoirVolume(status.reservoirRemainingUnits, atDate: pumpDate, withTimeLeft: NSTimeInterval(minutes: Double(status.reservoirRemainingMinutes)))

        // Check for an empty battery. Sentry packets are still broadcast for a few hours after this value reaches 0.
        if status.batteryRemainingPercent == 0 {
            NotificationManager.sendPumpBatteryLowNotification()
        }
    }

    /**
     Store a new reservoir volume and notify observers of new pump data.

     - parameter units:    The number of units remaining
     - parameter date:     The date the reservoir was read
     - parameter timeLeft: The approximate time before the reservoir is empty
     */
    private func updateReservoirVolume(units: Double, atDate date: NSDate, withTimeLeft timeLeft: NSTimeInterval?) {
        doseStore.addReservoirValue(units, atDate: date) { (newValue, previousValue, error) -> Void in
            if let error = error {
                self.logger?.addError(error, fromSource: "DoseStore")
                return
            }

            self.latestReservoirValue = newValue

            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.PumpStatusUpdatedNotification, object: self)

            // Send notifications for low reservoir if necessary
            if let newVolume = newValue?.unitVolume, previousVolume = previousValue?.unitVolume {
                guard newVolume > 0 else {
                    NotificationManager.sendPumpReservoirEmptyNotification()
                    return
                }

                let warningThresholds: [Double] = [10, 20, 30]

                for threshold in warningThresholds {
                    if newVolume <= threshold && previousVolume > threshold {
                        NotificationManager.sendPumpReservoirLowNotificationForAmount(newVolume, andTimeRemaining: timeLeft)
                    }
                }
            }
        }
    }

    /**
     Ensures pump data is current by either waking and polling, or ensuring we're listening to sentry packets.
     */
    private func assertCurrentPumpData() {
        guard let device = rileyLinkManager.firstConnectedDevice else {
            return
        }

        // TODO: Allow RileyLinkManager to enable/disable idle listening
        device.assertIdleListening()

        // How long should we wait before we poll for new reservoir data?
        let reservoirTolerance = sentryEnabled ? NSTimeInterval(minutes: 11) : NSTimeInterval(minutes: 1)

        // If we don't yet have reservoir data, or it's old, poll for it.
        if latestReservoirValue == nil || latestReservoirValue!.startDate.timeIntervalSinceNow <= -reservoirTolerance {
            device.ops?.readRemainingInsulin { (result) in
                switch result {
                case .Success(let units):
                    self.updateReservoirVolume(units, atDate: NSDate(), withTimeLeft: nil)
                case .Failure:
                    // Try to troubleshoot communications errors with the pump

                    // How long should we wait before we re-tune the RileyLink?
                    let tuneTolerance = NSTimeInterval(minutes: 14)

                    if device.lastTuned?.timeIntervalSinceNow <= -tuneTolerance {
                        device.tunePumpWithResultHandler { (result) in
                            switch result {
                            case .Success(let scanResult):
                                self.logger?.addError("Device auto-tuned to \(scanResult.bestFrequency) MHz", fromSource: "RileyLink")
                            case .Failure(let error):
                                self.logger?.addError("Device auto-tune failed with error: \(error)", fromSource: "RileyLink")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - G5 Transmitter
    /**
     The G5 transmitter is a reliable heartbeat by which we can assert the loop state.
     */

    // MARK: TransmitterDelegate

    func transmitter(transmitter: Transmitter, didError error: ErrorType) {
        logger?.addMessage([
            "error": "\(error)",
            "collectedAt": NSDateFormatter.ISO8601StrictDateFormatter().stringFromDate(NSDate())
            ], toCollection: "g5"
        )

        assertCurrentPumpData()
    }

    func transmitter(transmitter: Transmitter, didReadGlucose glucose: GlucoseRxMessage) {
        transmitterStartTime = transmitter.startTimeInterval

        if glucose != latestGlucoseMessage {
            latestGlucoseMessage = glucose

            if glucose.glucose >= 20, let startDate = latestGlucoseMessageDate, glucoseStore = glucoseStore {
                let quantity = HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: Double(glucose.glucose))

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

        assertCurrentPumpData()
    }

    // MARK: G5 data

    private var transmitterStartTime: NSTimeInterval? = NSUserDefaults.standardUserDefaults().transmitterStartTime {
        didSet {
            if oldValue != transmitterStartTime {
                NSUserDefaults.standardUserDefaults().transmitterStartTime = transmitterStartTime

                if let transmitterStartTime = transmitterStartTime, drift = oldValue?.distanceTo(transmitterStartTime) where abs(drift) > 1 {
                    AnalyticsManager.transmitterTimeDidDrift(drift)
                }
            }
        }
    }

    var latestGlucoseMessage: GlucoseRxMessage?

    var latestGlucoseMessageDate: NSDate? {
        guard let glucose = latestGlucoseMessage, startTime = transmitterStartTime else {
            return nil
        }

        return NSDate(timeIntervalSince1970: startTime).dateByAddingTimeInterval(NSTimeInterval(glucose.timestamp))
    }

    /**
     Attempts to backfill glucose data from the share servers if the G5 connection hasn't been established.
     */
    private func backfillGlucoseFromShareIfNeeded() {
        if self.latestGlucoseMessageDate == nil,
            let shareClient = self.shareClient, glucoseStore = self.glucoseStore
        {
            // Load glucose from Share if our xDripG5 connection hasn't started
            shareClient.fetchLast(1) { (error, glucose) in
                if let error = error {
                    self.logger?.addError(error, fromSource: "ShareClient")
                }

                guard let glucose = glucose?.first else {
                    return
                }

                // Ignore glucose values that are less than a minute newer than our previous value
                if let latestGlucose = glucoseStore.latestGlucose where latestGlucose.startDate.timeIntervalSinceDate(glucose.startDate) > -NSTimeInterval(minutes: 1)  {
                    return
                }

                glucoseStore.addGlucose(glucose.quantity, date: glucose.startDate, displayOnly: false, device: nil) { (_, value, error) -> Void in
                    if let error = error {
                        self.logger?.addError(error, fromSource: "GlucoseStore")
                    }

                    NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
                }
            }
        }
    }

    // MARK: - Configuration

    private var transmitterState: State<Transmitter> = .NeedsConfiguration {
        didSet {
            switch transmitterState {
            case .Ready(let transmitter):
                transmitter.delegate = self
                rileyLinkManager.timerTickEnabled = false
            case .NeedsConfiguration:
                rileyLinkManager.timerTickEnabled = true
            }
        }
    }

    private var connectedPeripheralIDs: Set<String> = Set(NSUserDefaults.standardUserDefaults().connectedPeripheralIDs) {
        didSet {
            NSUserDefaults.standardUserDefaults().connectedPeripheralIDs = Array(connectedPeripheralIDs)
        }
    }

    var pumpID: String? {
        get {
            return pumpState?.pumpID
        }
        set {
            guard newValue?.characters.count == 6 && newValue != pumpState?.pumpID else {
                return
            }

            if let pumpID = newValue {
                let pumpState = PumpState(pumpID: pumpID)

                if let timeZone = self.pumpState?.timeZone {
                    pumpState.timeZone = timeZone
                }

                self.pumpState = pumpState
            } else {
                self.pumpState = nil
            }

            doseStore.pumpID = pumpID

            NSUserDefaults.standardUserDefaults().pumpID = pumpID
        }
    }

    var pumpState: PumpState? {
        didSet {
            rileyLinkManager.pumpState = pumpState

            if let oldValue = oldValue {
                NSNotificationCenter.defaultCenter().removeObserver(self, name: PumpState.ValuesDidChangeNotification, object: oldValue)
            }

            if let pumpState = pumpState {
                NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(pumpStateValuesDidChange(_:)), name: PumpState.ValuesDidChangeNotification, object: pumpState)
            }
        }
    }

    @objc private func pumpStateValuesDidChange(note: NSNotification) {
        switch note.userInfo?[PumpState.PropertyKey] as? String {
        case "timeZone"?:
            NSUserDefaults.standardUserDefaults().pumpTimeZone = pumpState?.timeZone

            if let pumpTimeZone = pumpState?.timeZone {
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
            }
        case "pumpModel"?:
            if let sentrySupported = pumpState?.pumpModel?.larger where !sentrySupported {
                sentryEnabled = false
            }

            NSUserDefaults.standardUserDefaults().pumpModelNumber = pumpState?.pumpModel?.rawValue
        case "lastHistoryDump"?, "awakeUntil"?:
            break
        default:
            break
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

            AnalyticsManager.didChangeBasalRateSchedule()
        }
    }

    var carbRatioSchedule: CarbRatioSchedule? = NSUserDefaults.standardUserDefaults().carbRatioSchedule {
        didSet {
            carbStore?.carbRatioSchedule = carbRatioSchedule

            NSUserDefaults.standardUserDefaults().carbRatioSchedule = carbRatioSchedule

            AnalyticsManager.didChangeCarbRatioSchedule()
        }
    }

    var insulinActionDuration: NSTimeInterval? = NSUserDefaults.standardUserDefaults().insulinActionDuration {
        didSet {
            doseStore.insulinActionDuration = insulinActionDuration

            NSUserDefaults.standardUserDefaults().insulinActionDuration = insulinActionDuration

            if oldValue != insulinActionDuration {
                AnalyticsManager.didChangeInsulinActionDuration()
            }
        }
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule? = NSUserDefaults.standardUserDefaults().insulinSensitivitySchedule {
        didSet {
            carbStore?.insulinSensitivitySchedule = insulinSensitivitySchedule
            doseStore.insulinSensitivitySchedule = insulinSensitivitySchedule

            NSUserDefaults.standardUserDefaults().insulinSensitivitySchedule = insulinSensitivitySchedule

            AnalyticsManager.didChangeInsulinSensitivitySchedule()
        }
    }

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule? = NSUserDefaults.standardUserDefaults().glucoseTargetRangeSchedule {
        didSet {
            NSUserDefaults.standardUserDefaults().glucoseTargetRangeSchedule = glucoseTargetRangeSchedule

            AnalyticsManager.didChangeGlucoseTargetRangeSchedule()
        }
    }

    var maximumBasalRatePerHour: Double? = NSUserDefaults.standardUserDefaults().maximumBasalRatePerHour {
        didSet {
            NSUserDefaults.standardUserDefaults().maximumBasalRatePerHour = maximumBasalRatePerHour

            AnalyticsManager.didChangeMaximumBasalRate()
        }
    }

    var maximumBolus: Double? = NSUserDefaults.standardUserDefaults().maximumBolus {
        didSet {
            NSUserDefaults.standardUserDefaults().maximumBolus = maximumBolus

            AnalyticsManager.didChangeMaximumBolus()
        }
    }

    /// Whether the RileyLink should listen for sentry packets.
    var sentryEnabled: Bool = true

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
            let userInfo = WatchContext(pumpStatus: latestPumpStatus, glucose: latestGlucoseMessage, glucoseMessageDate: latestGlucoseMessageDate).rawValue

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
                } else {
                    AnalyticsManager.didAddCarbsFromWatch(carbEntry.value)
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
                    } else {
                        AnalyticsManager.didSetBolusFromWatch(bolus.value)
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
        let pumpID = NSUserDefaults.standardUserDefaults().pumpID

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

        if let pumpID = pumpID {
            let pumpState = PumpState(pumpID: pumpID)

            if let timeZone = NSUserDefaults.standardUserDefaults().pumpTimeZone {
                pumpState.timeZone = timeZone
            }

            if let pumpModelNumber = NSUserDefaults.standardUserDefaults().pumpModelNumber {
                if let model = PumpModel(rawValue: pumpModelNumber) {
                    pumpState.pumpModel = model

                    sentryEnabled = model.larger
                }
            }

            self.pumpState = pumpState
        }

        rileyLinkManager = RileyLinkDeviceManager(
            pumpState: self.pumpState,
            autoConnectIDs: connectedPeripheralIDs
        )

        if let  settings = NSBundle.mainBundle().remoteSettings,
                username = settings["ShareAccountName"],
                password = settings["ShareAccountPassword"]
            where !username.isEmpty && !password.isEmpty
        {
            shareClient = ShareClient(username: username, password: password)
        } else {
            shareClient = nil
        }

        super.init()

        rileyLinkManagerObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: rileyLinkManager, queue: nil) { [weak self] (note) -> Void in
            self?.receivedRileyLinkManagerNotification(note)
        }

        // TODO: Use delegation instead.
        rileyLinkDevicePacketObserver = NSNotificationCenter.defaultCenter().addObserverForName(RileyLinkDevice.DidReceiveIdleMessageNotification, object: nil, queue: nil) { [weak self] (note) -> Void in
            self?.receivedRileyLinkPacketNotification(note)
        }

        if let pumpState = pumpState {
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(pumpStateValuesDidChange(_:)), name: PumpState.ValuesDidChangeNotification, object: pumpState)
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
    convenience init(pumpStatus: MySentryPumpStatusMessageBody?, glucose: GlucoseRxMessage?, glucoseMessageDate: NSDate?) {
        self.init()

        if let glucose = glucose, date = glucoseMessageDate where glucose.state > 5 {
            glucoseValue = Int(glucose.glucose)
            glucoseTrend = Int(glucose.trend)
            glucoseDate = date
        }

        if let status = pumpStatus, date = status.pumpDateComponents.date {
            IOB = status.iob
            reservoir = status.reservoirRemainingUnits
            pumpDate = date
        }
    }
}

