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
import xDripG5
import NightscoutUploadKit

enum State<T> {
    case NeedsConfiguration
    case Ready(T)
}


class DeviceDataManager: CarbStoreDelegate, TransmitterDelegate {
    /// Notification posted by the instance when new glucose data was processed
    static let GlucoseUpdatedNotification = "com.loudnate.Naterade.notification.GlucoseUpdated"

    /// Notification posted by the instance when new pump data was processed
    static let PumpStatusUpdatedNotification = "com.loudnate.Naterade.notification.PumpStatusUpdated"

    // MARK: - Utilities

    lazy var logger = DiagnosticLogger()

    /// Manages all the RileyLinks
    let rileyLinkManager: RileyLinkDeviceManager

    /// The share server client
    private let shareClient: ShareClient?

    /// Nightscout Uploader
    var nightscoutUploader: NightscoutUploader?

    // Timestamp of last event we've retrieved from pump
    var observingPumpEventsSince = NSDate(timeIntervalSinceNow: NSTimeInterval(hours: -24))

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

    @objc private func receivedRileyLinkManagerNotification(note: NSNotification) {
        NSNotificationCenter.defaultCenter().postNotificationName(note.name, object: self, userInfo: note.userInfo)
    }

    /**
     Called when a new idle message is received by the RileyLink.

     Only MySentryPumpStatus messages are handled.

     - parameter note: The notification object
     */
    @objc private func receivedRileyLinkPacketNotification(note: NSNotification) {
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

    @objc private func receivedRileyLinkTimerTickNotification(note: NSNotification) {
        assertCurrentPumpData()

        backfillGlucoseFromShareIfNeeded()
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

        // Sentry packets are sent in groups of 3, 5s apart. Wait 11s before allowing the loop data to continue to avoid conflicting comms.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(11 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
            self.updateReservoirVolume(status.reservoirRemainingUnits, atDate: pumpDate, withTimeLeft: NSTimeInterval(minutes: Double(status.reservoirRemainingMinutes)))
        }

        // Check for an empty battery. Sentry packets are still broadcast for a few hours after this value reaches 0.
        if status.batteryRemainingPercent == 0 {
            NotificationManager.sendPumpBatteryLowNotification()
        }

        nightscoutUploader?.handlePumpStatus(status, device: device.deviceURI)
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

            if self.preferredInsulinDataSource == .PumpHistory {
                self.fetchPumpHistory()
            } else {
                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.PumpStatusUpdatedNotification, object: self)
            }

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

        device.assertIdleListening()

        // How long should we wait before we poll for new reservoir data?
        let reservoirTolerance = rileyLinkManager.idleListeningEnabled ? NSTimeInterval(minutes: 11) : NSTimeInterval(minutes: 4)

        // If we don't yet have reservoir data, or it's old, poll for it.
        if latestReservoirValue == nil || latestReservoirValue!.startDate.timeIntervalSinceNow <= -reservoirTolerance {
            device.ops?.readRemainingInsulin { (result) in
                switch result {
                case .Success(let units):
                    self.updateReservoirVolume(units, atDate: NSDate(), withTimeLeft: nil)
                case .Failure(let error):
                    self.logger?.addError("Failed to fetch reservoir: \(error)", fromSource: "RileyLink")
                    self.troubleshootPumpCommsWithDevice(device)
                }
            }
        }
    }

    private func fetchPumpHistory() {
        guard let device = rileyLinkManager.firstConnectedDevice else {
            return
        }

        /*
         This is where we fetch history.
         */

        // TODO: Reconcile these
        //let startDate = doseStore.pumpEventQueryAfterDate
        let startDate = nightscoutUploader?.observingPumpEventsSince ?? observingPumpEventsSince

        device.ops?.getHistoryEventsSinceDate(startDate) { (result) in
            switch result {
            case let .Success(events, pumpModel):
                // TODO: Surface raw pump event data and add DoseEntry conformance
                //                self.doseStore.addPumpEvents(events.map({ ($0.date, nil, nil, $0.isMutable()) })) { (error) in
                //                    if let error = error {
                //                        self.logger?.addError("Failed to store history: \(error)", fromSource: "DoseStore")
                //                    }
                //                }

                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.PumpStatusUpdatedNotification, object: self)
                self.nightscoutUploader?.processPumpEvents(events, source: device.deviceURI, pumpModel: pumpModel)


                var lastFinalDate: NSDate?
                var firstMutableDate: NSDate?

                for event in events {
                    if event.isMutable() {
                        firstMutableDate = min(event.date, firstMutableDate ?? event.date)
                    } else {
                        lastFinalDate = max(event.date, lastFinalDate ?? event.date)
                    }
                }
                if let mutableDate = firstMutableDate {
                    self.observingPumpEventsSince = mutableDate
                } else if let finalDate = lastFinalDate {
                    self.observingPumpEventsSince = finalDate
                }


            case .Failure(let error):
                self.logger?.addError("Failed to fetch history: \(error)", fromSource: "RileyLink")
                self.troubleshootPumpCommsWithDevice(device)
            }
        }
    }

    /**
     Attempts to fix an extended communication failure between a RileyLink device and the pump

     - parameter device: The RileyLink device
     */
    private func troubleshootPumpCommsWithDevice(device: RileyLinkDevice) {

        // How long we should wait before we re-tune the RileyLink
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

    func transmitter(transmitter: Transmitter, didReadGlucose glucoseMessage: GlucoseRxMessage) {
        transmitterStartTime = transmitter.startTimeInterval

        assertCurrentPumpData()

        guard glucoseMessage != latestGlucoseMessage else {
            return
        }

        latestGlucoseMessage = glucoseMessage

        guard let glucose = TransmitterGlucose(glucoseMessage: glucoseMessage, startTime: transmitter.startTimeInterval), glucoseStore = glucoseStore else {
            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
            return
        }

        latestGlucoseValue = glucose

        let device = HKDevice(name: "xDripG5", manufacturer: "Dexcom", model: "G5 Mobile", hardwareVersion: nil, firmwareVersion: nil, softwareVersion: String(xDripG5VersionNumber), localIdentifier: nil, UDIDeviceIdentifier: "00386270000002")

        glucoseStore.addGlucose(glucose.quantity, date: glucose.startDate, displayOnly: glucoseMessage.glucoseIsDisplayOnly, device: device, resultHandler: { (_, _, error) -> Void in
            if let error = error {
                self.logger?.addError(error, fromSource: "GlucoseStore")
            }

            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
        })
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

    var latestGlucoseValue: GlucoseValue?

    /**
     Attempts to backfill glucose data from the share servers if the G5 connection hasn't been established.
     */
    private func backfillGlucoseFromShareIfNeeded() {
        if latestGlucoseMessage == nil,
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

                    self.latestGlucoseValue = value

                    NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
                }
            }
        }
    }

    // MARK: - Configuration

    // MARK: Pump

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

            nightscoutUploader?.pumpID = pumpID
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
                rileyLinkManager.idleListeningEnabled = false
            }

            NSUserDefaults.standardUserDefaults().pumpModelNumber = pumpState?.pumpModel?.rawValue
        case "lastHistoryDump"?, "awakeUntil"?:
            break
        default:
            break
        }
    }

    /// The user's preferred method of fetching insulin data from the pump
    var preferredInsulinDataSource = NSUserDefaults.standardUserDefaults().preferredInsulinDataSource ?? .PumpHistory {
        didSet {
            NSUserDefaults.standardUserDefaults().preferredInsulinDataSource = preferredInsulinDataSource
        }
    }

    // MARK: G5 Transmitter

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

    // MARK: Loop model inputs

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

    private(set) var watchManager: WatchDataManager!

    @objc private func loopDataDidUpdateNotification(_: NSNotification) {
        watchManager.updateWatch()
    }

    // MARK: - Initialization

    static let sharedManager = DeviceDataManager()

    private(set) var loopManager: LoopDataManager!

    init() {
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

        var idleListeningEnabled = true

        if let pumpID = pumpID {
            let pumpState = PumpState(pumpID: pumpID)

            if let timeZone = NSUserDefaults.standardUserDefaults().pumpTimeZone {
                pumpState.timeZone = timeZone
            }

            if let pumpModelNumber = NSUserDefaults.standardUserDefaults().pumpModelNumber {
                if let model = PumpModel(rawValue: pumpModelNumber) {
                    pumpState.pumpModel = model

                    idleListeningEnabled = model.larger
                }
            }

            self.pumpState = pumpState
        }

        rileyLinkManager = RileyLinkDeviceManager(
            pumpState: self.pumpState,
            autoConnectIDs: connectedPeripheralIDs
        )
        rileyLinkManager.idleListeningEnabled = idleListeningEnabled

        if let  settings = NSBundle.mainBundle().remoteSettings,
            username = settings["ShareAccountName"],
            password = settings["ShareAccountPassword"]
            where !username.isEmpty && !password.isEmpty
        {
            shareClient = ShareClient(username: username, password: password)
        } else {
            shareClient = nil
        }

        if let  settings = NSBundle.mainBundle().remoteSettings,
            siteURL = settings["NightscoutSiteURL"],
            APISecret = settings["NightscoutAPISecret"]
        {
            nightscoutUploader = NightscoutUploader(siteURL: siteURL, APISecret: APISecret, pumpID: pumpID)
            nightscoutUploader!.errorHandler = { (error: ErrorType, context: String) -> Void in
                print("Error \(error), while \(context)")
            }

        } else {
            nightscoutUploader = nil
        }

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(receivedRileyLinkManagerNotification(_:)), name: nil, object: rileyLinkManager)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(receivedRileyLinkPacketNotification(_:)), name: RileyLinkDevice.DidReceiveIdleMessageNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(receivedRileyLinkTimerTickNotification(_:)), name: RileyLinkDevice.DidUpdateTimerTickNotification, object: nil)

        if let pumpState = pumpState {
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(pumpStateValuesDidChange(_:)), name: PumpState.ValuesDidChangeNotification, object: pumpState)
        }

        loopManager = LoopDataManager(deviceDataManager: self)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(loopDataDidUpdateNotification(_:)), name: LoopDataManager.LoopDataUpdatedNotification, object: loopManager)

        watchManager = WatchDataManager(deviceDataManager: self)

        carbStore?.delegate = self

        defer {
            transmitterID = NSUserDefaults.standardUserDefaults().transmitterID
        }
    }
}

