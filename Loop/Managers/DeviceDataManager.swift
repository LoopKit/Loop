//
//  DeviceDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import CarbKit
import CoreData
import G4ShareSpy
import GlucoseKit
import HealthKit
import InsulinKit
import LoopKit
import MinimedKit
import NightscoutUploadKit
import RileyLinkKit
import ShareClient
import xDripG5


final class DeviceDataManager: CarbStoreDelegate, DoseStoreDelegate, TransmitterDelegate, ReceiverDelegate {
    /// Notification posted by the instance when new glucose data was processed
    static let GlucoseUpdatedNotification = "com.loudnate.Naterade.notification.GlucoseUpdated"

    /// Notification posted by the instance when new pump data was processed
    static let PumpStatusUpdatedNotification = "com.loudnate.Naterade.notification.PumpStatusUpdated"

    /// Notification posted by the instance when loop configuration was changed
    static let LoopSettingsUpdatedNotification = "com.loudnate.Naterade.notification.LoopSettingsUpdated"

    // MARK: - Utilities

    let logger = DiagnosticLogger()

    /// Manages all the RileyLinks
    let rileyLinkManager: RileyLinkDeviceManager

    /// Manages remote data (TODO: the lazy initialization isn't thread-safe)
    lazy var remoteDataManager = RemoteDataManager()

    private var nightscoutDataManager: NightscoutDataManager!

    // The Dexcom Share receiver object
    private var receiver: Receiver? {
        didSet {
            receiver?.delegate = self
            enableRileyLinkHeartbeatIfNeeded()
        }
    }

    var receiverEnabled: Bool {
        get {
            return receiver != nil
        }
        set {
            receiver = newValue ? Receiver() : nil
            NSUserDefaults.standardUserDefaults().receiverEnabled = newValue
        }
    }

    var sensorInfo: SensorDisplayable? {
        return latestGlucoseG5 ?? latestGlucoseG4 ?? latestPumpStatusFromMySentry
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
                    updatePumpStatus(body, from: device)
                case is MySentryAlertMessageBody, is MySentryAlertClearedMessageBody:
                    break
                case let body:
                    logger.addMessage(["messageType": Int(message.messageType.rawValue), "messageBody": body.txData.hexadecimalString], toCollection: "sentryOther")
                }
            default:
                break
            }
        }
    }

    @objc private func receivedRileyLinkTimerTickNotification(note: NSNotification) {
        backfillGlucoseFromShareIfNeeded() {
            self.assertCurrentPumpData()
        }
    }

    func connectToRileyLink(device: RileyLinkDevice) {
        connectedPeripheralIDs.insert(device.peripheral.identifier.UUIDString)

        rileyLinkManager.connectDevice(device)

        AnalyticsManager.sharedManager.didChangeRileyLinkConnectionState()
    }

    func disconnectFromRileyLink(device: RileyLinkDevice) {
        connectedPeripheralIDs.remove(device.peripheral.identifier.UUIDString)

        rileyLinkManager.disconnectDevice(device)

        AnalyticsManager.sharedManager.didChangeRileyLinkConnectionState()

        if connectedPeripheralIDs.count == 0 {
            NotificationManager.clearLoopNotRunningNotifications()
        }
    }

    func enableRileyLinkHeartbeatIfNeeded() {
        if transmitter != nil {
            rileyLinkManager.timerTickEnabled = false
        } else if receiverEnabled {
            rileyLinkManager.timerTickEnabled = false
        } else {
            rileyLinkManager.timerTickEnabled = true
        }
    }

    // MARK: Pump data

    var latestPumpStatusFromMySentry: MySentryPumpStatusMessageBody?

    /**
     Handles receiving a MySentry status message, which are only posted by MM x23 pumps.

     This message has two important pieces of info about the pump: reservoir volume and battery.

     Because the RileyLink must actively listen for these packets, they are not a reliable heartbeat. However, we can still use them to assert glucose data is current.

     - parameter status: The status message body
     - parameter device: The RileyLink that received the message
     */
    private func updatePumpStatus(status: MySentryPumpStatusMessageBody, from device: RileyLinkDevice) {
        status.pumpDateComponents.timeZone = pumpState?.timeZone
        status.glucoseDateComponents?.timeZone = pumpState?.timeZone

        // The pump sends the same message 3x, so ignore it if we've already seen it.
        guard status != latestPumpStatusFromMySentry, let pumpDate = status.pumpDateComponents.date else {
            return
        }

        // Report battery changes to Analytics
        if let latestPumpStatusFromMySentry = latestPumpStatusFromMySentry where status.batteryRemainingPercent - latestPumpStatusFromMySentry.batteryRemainingPercent >= 50 {
            AnalyticsManager.sharedManager.pumpBatteryWasReplaced()
        }

        latestPumpStatusFromMySentry = status

        // Gather PumpStatus from MySentry packet
        let pumpStatus: NightscoutUploadKit.PumpStatus?
        if let pumpDate = status.pumpDateComponents.date, let pumpID = pumpID {

            let batteryStatus = BatteryStatus(percent: status.batteryRemainingPercent)
            let iobStatus = IOBStatus(timestamp: pumpDate, iob: status.iob)

            pumpStatus = NightscoutUploadKit.PumpStatus(clock: pumpDate, pumpID: pumpID, iob: iobStatus, battery: batteryStatus, reservoir: status.reservoirRemainingUnits)
        } else {
            pumpStatus = nil
            self.logger.addError("Could not interpret pump clock: \(status.pumpDateComponents)", fromSource: "RileyLink")
        }

        // Trigger device status upload, even if something is wrong with pumpStatus
        nightscoutDataManager.uploadDeviceStatus(pumpStatus)

        backfillGlucoseFromShareIfNeeded()

        // Minimed sensor glucose
        switch status.glucose {
        case .Active(glucose: let glucose):
            if let date = status.glucoseDateComponents?.date {
                glucoseStore?.addGlucose(
                    HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: Double(glucose)),
                    date: date,
                    isDisplayOnly: false,
                    device: nil
                ) { (success, _, error) in
                    if let error = error {
                        self.logger.addError(error, fromSource: "GlucoseStore")
                    }

                    if success {
                        NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
                    }
                }
            }
        default:
            break
        }

        // Upload sensor glucose to Nightscout
        remoteDataManager.nightscoutUploader?.uploadSGVFromMySentryPumpStatus(status, device: device.deviceURI)

        // Sentry packets are sent in groups of 3, 5s apart. Wait 11s before allowing the loop data to continue to avoid conflicting comms.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(11 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
            self.updateReservoirVolume(status.reservoirRemainingUnits, atDate: pumpDate, withTimeLeft: NSTimeInterval(minutes: Double(status.reservoirRemainingMinutes)))
        }

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
        doseStore.addReservoirValue(units, atDate: date) { (newValue, previousValue, areStoredValuesContinuous, error) -> Void in
            if let error = error {
                self.logger.addError(error, fromSource: "DoseStore")
                return
            }

            if self.preferredInsulinDataSource == .pumpHistory || !areStoredValuesContinuous {
                self.fetchPumpHistory { (error) in
                    // Notify and trigger a loop as long as we have fresh, reliable pump data.
                    if error == nil || areStoredValuesContinuous {
                        NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.PumpStatusUpdatedNotification, object: self)
                    }
                }
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

                if newVolume > previousVolume + 1 {
                    AnalyticsManager.sharedManager.reservoirWasRewound()
                }
            }
        }
    }


    /**
     Polls the pump for new history events and stores them.
     
     - parameter completion: A closure called after the fetch is complete. This closure takes a single argument:
        - error: An error describing why the fetch and/or store failed
     */
    private func fetchPumpHistory(completionHandler: (error: ErrorType?) -> Void) {
        guard let device = rileyLinkManager.firstConnectedDevice else {
            return
        }

        let startDate = doseStore.pumpEventQueryAfterDate

        device.ops?.getHistoryEventsSinceDate(startDate) { (result) in
            switch result {
            case let .Success(events, _):
                self.doseStore.add(events) { (error) in
                    if let error = error {
                        self.logger.addError("Failed to store history: \(error)", fromSource: "DoseStore")
                    }

                    completionHandler(error: error)
                }
            case .Failure(let error):
                self.logger.addError("Failed to fetch history: \(error)", fromSource: "RileyLink")

                completionHandler(error: error)
            }
        }
    }

    /**
     Read the pump's current state, including reservoir and clock

     - parameter completion: A closure called after the command is complete. This closure takes a single Result argument:
        - Success(status, date): The pump status, and the resolved date according to the pump's clock
        - Failure(error): An error describing why the command failed
     */
    private func readPumpData(completion: (Either<(status: RileyLinkKit.PumpStatus, date: NSDate), ErrorType>) -> Void) {
        guard let device = rileyLinkManager.firstConnectedDevice, let ops = device.ops else {
            completion(.Failure(LoopError.ConfigurationError))
            return
        }

        ops.readPumpStatus { (result) in
            switch result {
            case .Success(let status):
                status.clock.timeZone = ops.pumpState.timeZone
                guard let date = status.clock.date else {
                    self.logger.addError("Could not interpret pump clock: \(status.clock)", fromSource: "RileyLink")
                    completion(.Failure(LoopError.ConfigurationError))
                    return
                }
                completion(.Success(status: status, date: date))
            case .Failure(let error):
                self.logger.addError("Failed to fetch pump status: \(error)", fromSource: "RileyLink")
                completion(.Failure(error))
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

        // How long should we wait before we poll for new pump data?
        let pumpStatusAgeTolerance = rileyLinkManager.idleListeningEnabled ? NSTimeInterval(minutes: 11) : NSTimeInterval(minutes: 4)

        // If we don't yet have pump status, or it's old, poll for it.
        if  doseStore.lastReservoirValue == nil ||
            doseStore.lastReservoirValue!.startDate.timeIntervalSinceNow <= -pumpStatusAgeTolerance {
            readPumpData { (result) in
                let nsPumpStatus: NightscoutUploadKit.PumpStatus?
                switch result {
                case .Success(let (status, date)):
                    self.updateReservoirVolume(status.reservoir, atDate: date, withTimeLeft: nil)
                    let battery = BatteryStatus(voltage: status.batteryVolts, status: BatteryIndicator(batteryStatus: status.batteryStatus))
                    nsPumpStatus = NightscoutUploadKit.PumpStatus(clock: date, pumpID: status.pumpID, iob: nil, battery: battery, suspended: status.suspended, bolusing: status.bolusing, reservoir: status.reservoir)
                case .Failure(let error):
                    self.troubleshootPumpCommsWithDevice(device)
                    self.nightscoutDataManager.uploadLoopStatus(loopError: error)
                    nsPumpStatus = nil
                }
                self.nightscoutDataManager.uploadDeviceStatus(nsPumpStatus)
            }
        }
    }

    /**
     Send a bolus command and handle the result
 
     - parameter completion: A closure called after the command is complete. This closure takes a single argument:
        - error: An error describing why the command failed
     */
    func enactBolus(units: Double, completion: (error: ErrorType?) -> Void) {
        guard units > 0 else {
            completion(error: nil)
            return
        }

        guard let device = rileyLinkManager.firstConnectedDevice else {
            completion(error: LoopError.ConnectionError)
            return
        }

        guard let ops = device.ops else {
            completion(error: LoopError.ConfigurationError)
            return
        }

        let setBolus = {
            ops.setNormalBolus(units) { (error) in
                if let error = error {
                    self.logger.addError(error, fromSource: "Bolus")
                    completion(error: LoopError.CommunicationError)
                } else {
                    self.loopManager.recordBolus(units, atDate: NSDate())
                    completion(error: nil)
                }
            }
        }

        // If we don't have recent pump data, or the pump was recently rewound, read new pump data before bolusing.
        if  doseStore.lastReservoirValue == nil ||
            doseStore.lastReservoirVolumeDrop < 0 ||
            doseStore.lastReservoirValue!.startDate.timeIntervalSinceNow <= NSTimeInterval(minutes: -5)
        {
            readPumpData { (result) in
                switch result {
                case .Success(let (status, date)):
                    self.doseStore.addReservoirValue(status.reservoir, atDate: date) { (newValue, _, _, error) in
                        if let error = error {
                            self.logger.addError(error, fromSource: "Bolus")
                            completion(error: error)
                        } else {
                            setBolus()
                        }
                    }
                case .Failure(let error):
                    completion(error: error)
                }
            }
        } else {
            setBolus()
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
                    self.logger.addError("Device auto-tuned to \(scanResult.bestFrequency) MHz", fromSource: "RileyLink")
                case .Failure(let error):
                    self.logger.addError("Device auto-tune failed with error: \(error)", fromSource: "RileyLink")
                }
            }
        }
    }

    // MARK: - G5 Transmitter
    /**
     The G5 transmitter is a reliable heartbeat by which we can assert the loop state.
     */

    // MARK: TransmitterDelegate

    func transmitter(transmitter: xDripG5.Transmitter, didError error: ErrorType) {
        logger.addMessage([
                "error": "\(error)",
                "collectedAt": NSDateFormatter.ISO8601StrictDateFormatter().stringFromDate(NSDate())
            ], toCollection: "g5"
        )

        assertCurrentPumpData()
    }

    func transmitter(transmitter: xDripG5.Transmitter, didRead glucose: xDripG5.Glucose) {
        assertCurrentPumpData()

        guard glucose != latestGlucoseG5 else {
            return
        }

        latestGlucoseG5 = glucose

        guard let glucoseStore = glucoseStore, let quantity = glucose.glucose else {
            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
            return
        }

        let device = HKDevice(name: "xDripG5", manufacturer: "Dexcom", model: "G5 Mobile", hardwareVersion: nil, firmwareVersion: nil, softwareVersion: String(xDripG5VersionNumber), localIdentifier: nil, UDIDeviceIdentifier: "00386270000002")

        glucoseStore.addGlucose(quantity, date: glucose.readDate, isDisplayOnly: glucose.isDisplayOnly, device: device) { (success, _, error) -> Void in
            if let error = error {
                self.logger.addError(error, fromSource: "GlucoseStore")
            }

            if success {
                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
            }
        }
    }

    // MARK: G5 data

    private var latestGlucoseG5: xDripG5.Glucose?

    /**
     Attempts to backfill glucose data from the share servers if a G5 connection hasn't been established.
     
     - parameter completion: An optional closure called after the command is complete.
     */
    private func backfillGlucoseFromShareIfNeeded(completion: (() -> Void)? = nil) {
        // We should have no G4 Share or G5 data, and a configured ShareClient and GlucoseStore.
        guard latestGlucoseG4 == nil && latestGlucoseG5 == nil, let shareClient = remoteDataManager.shareClient, glucoseStore = glucoseStore else {
            completion?()
            return
        }

        // If our last glucose was less than 4.5 minutes ago, don't fetch.
        if let latestGlucose = glucoseStore.latestGlucose where latestGlucose.startDate.timeIntervalSinceNow > -NSTimeInterval(minutes: 4.5) {
            completion?()
            return
        }

        shareClient.fetchLast(6) { (error, glucose) in
            guard let glucose = glucose else {
                if let error = error {
                    self.logger.addError(error, fromSource: "ShareClient")
                }
                completion?()
                return
            }

            // Ignore glucose values that are up to a minute newer than our previous value, to account for possible time shifting in Share data
            let newGlucose = glucose.filterDateRange(glucoseStore.latestGlucose?.startDate.dateByAddingTimeInterval(NSTimeInterval(minutes: 1)), nil).map {
                return (quantity: $0.quantity, date: $0.startDate, isDisplayOnly: false)
            }

            glucoseStore.addGlucoseValues(newGlucose, device: nil) { (success, _, error) -> Void in
                if let error = error {
                    self.logger.addError(error, fromSource: "GlucoseStore")
                }

                if success {
                    NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
                }

                completion?()
            }
        }
    }

    // MARK: - Share Receiver

    // MARK: ReceiverDelegate

    private var latestGlucoseG4: GlucoseG4?

    func receiver(receiver: Receiver, didReadGlucoseHistory glucoseHistory: [GlucoseG4]) {
        assertCurrentPumpData()

        guard let latest = glucoseHistory.sort({ $0.sequence < $1.sequence }).last where latest != latestGlucoseG4 else {
            return
        }
        latestGlucoseG4 = latest

        guard let glucoseStore = glucoseStore else {
            return
        }

        // In the event that some of the glucose history was already backfilled from Share, don't overwrite it.
        let includeAfter = glucoseStore.latestGlucose?.startDate.dateByAddingTimeInterval(NSTimeInterval(minutes: 1))

        let validGlucose = glucoseHistory.flatMap({
            $0.isValid ? $0 : nil
        }).filterDateRange(includeAfter, nil).map({
            (quantity: $0.quantity, date: $0.startDate, isDisplayOnly: $0.isDisplayOnly)
        })

        // "Dexcom G4 Platinum Transmitter (Retail) US" - see https://accessgudid.nlm.nih.gov/devices/search?query=dexcom+g4
        let device = HKDevice(name: "G4ShareSpy", manufacturer: "Dexcom", model: "G4 Share", hardwareVersion: nil, firmwareVersion: nil, softwareVersion: String(G4ShareSpyVersionNumber), localIdentifier: nil, UDIDeviceIdentifier: "40386270000048")

        glucoseStore.addGlucoseValues(validGlucose, device: device) { (success, _, error) -> Void in
            if let error = error {
                self.logger.addError(error, fromSource: "GlucoseStore")
            }

            if success {
                NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.GlucoseUpdatedNotification, object: self)
            }
        }
    }

    func receiver(receiver: Receiver, didError error: ErrorType) {
        logger.addMessage(["error": "\(error)", "collectedAt": NSDateFormatter.ISO8601StrictDateFormatter().stringFromDate(NSDate())], toCollection: "g4")

        assertCurrentPumpData()
    }

    func receiver(receiver: Receiver, didLogBluetoothEvent event: String) {
        // Uncomment to debug communication
        // logger.addMessage(["event": "\(event)", "collectedAt": NSDateFormatter.ISO8601StrictDateFormatter().stringFromDate(NSDate())], toCollection: "g4")
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

            remoteDataManager.nightscoutUploader?.reset()
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
                    self.glucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: glucoseTargetRangeSchedule.unit, dailyItems: glucoseTargetRangeSchedule.items, workoutRange: glucoseTargetRangeSchedule.workoutRange, timeZone: pumpTimeZone)
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
    var preferredInsulinDataSource = NSUserDefaults.standardUserDefaults().preferredInsulinDataSource ?? .pumpHistory {
        didSet {
            NSUserDefaults.standardUserDefaults().preferredInsulinDataSource = preferredInsulinDataSource
        }
    }

    // MARK: G5 Transmitter

    internal private(set) var transmitter: Transmitter? {
        didSet {
            transmitter?.delegate = self
            enableRileyLinkHeartbeatIfNeeded()
        }
    }

    var transmitterID: String? {
        get {
            return transmitter?.ID
        }
        set {
            guard transmitterID != newValue else { return }

            if let transmitterID = newValue where transmitterID.characters.count == 6 {
                transmitter = Transmitter(ID: transmitterID, passiveModeEnabled: true)
            } else {
                transmitter = nil
            }

            NSUserDefaults.standardUserDefaults().transmitterID = newValue
        }
    }

    // MARK: Loop model inputs

    var basalRateSchedule: BasalRateSchedule? = NSUserDefaults.standardUserDefaults().basalRateSchedule {
        didSet {
            doseStore.basalProfile = basalRateSchedule

            NSUserDefaults.standardUserDefaults().basalRateSchedule = basalRateSchedule

            AnalyticsManager.sharedManager.didChangeBasalRateSchedule()
        }
    }

    var carbRatioSchedule: CarbRatioSchedule? = NSUserDefaults.standardUserDefaults().carbRatioSchedule {
        didSet {
            carbStore?.carbRatioSchedule = carbRatioSchedule

            NSUserDefaults.standardUserDefaults().carbRatioSchedule = carbRatioSchedule

            AnalyticsManager.sharedManager.didChangeCarbRatioSchedule()
        }
    }

    var insulinActionDuration: NSTimeInterval? = NSUserDefaults.standardUserDefaults().insulinActionDuration {
        didSet {
            doseStore.insulinActionDuration = insulinActionDuration

            NSUserDefaults.standardUserDefaults().insulinActionDuration = insulinActionDuration

            if oldValue != insulinActionDuration {
                AnalyticsManager.sharedManager.didChangeInsulinActionDuration()
            }
        }
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule? = NSUserDefaults.standardUserDefaults().insulinSensitivitySchedule {
        didSet {
            carbStore?.insulinSensitivitySchedule = insulinSensitivitySchedule
            doseStore.insulinSensitivitySchedule = insulinSensitivitySchedule

            NSUserDefaults.standardUserDefaults().insulinSensitivitySchedule = insulinSensitivitySchedule

            AnalyticsManager.sharedManager.didChangeInsulinSensitivitySchedule()
        }
    }

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule? = NSUserDefaults.standardUserDefaults().glucoseTargetRangeSchedule {
        didSet {
            NSUserDefaults.standardUserDefaults().glucoseTargetRangeSchedule = glucoseTargetRangeSchedule

            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopSettingsUpdatedNotification, object: self)

            AnalyticsManager.sharedManager.didChangeGlucoseTargetRangeSchedule()
        }
    }

    var workoutModeEnabled: Bool? {
        guard let range = glucoseTargetRangeSchedule else {
            return nil
        }

        guard let override = range.temporaryOverride else {
            return false
        }

        return override.endDate.timeIntervalSinceNow > 0
    }

    /// Attempts to enable workout glucose targets until the given date, and returns true if successful.
    /// TODO: This can live on the schedule itself once its a value type, since didSet would invoke when mutated.
    func enableWorkoutMode(until endDate: NSDate) -> Bool {
        guard let glucoseTargetRangeSchedule = glucoseTargetRangeSchedule else {
            return false
        }

        glucoseTargetRangeSchedule.setWorkoutOverrideUntilDate(endDate)

        NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopSettingsUpdatedNotification, object: self)

        return true
    }

    func disableWorkoutMode() {
        glucoseTargetRangeSchedule?.clearOverride()

        NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.LoopSettingsUpdatedNotification, object: self)
    }

    var maximumBasalRatePerHour: Double? = NSUserDefaults.standardUserDefaults().maximumBasalRatePerHour {
        didSet {
            NSUserDefaults.standardUserDefaults().maximumBasalRatePerHour = maximumBasalRatePerHour

            AnalyticsManager.sharedManager.didChangeMaximumBasalRate()
        }
    }

    var maximumBolus: Double? = NSUserDefaults.standardUserDefaults().maximumBolus {
        didSet {
            NSUserDefaults.standardUserDefaults().maximumBolus = maximumBolus

            AnalyticsManager.sharedManager.didChangeMaximumBolus()
        }
    }

    // MARK: - CarbKit

    let carbStore: CarbStore?

    // MARK: CarbStoreDelegate

    func carbStore(_: CarbStore, didError error: CarbStore.Error) {
        logger.addError(error, fromSource: "CarbStore")
    }

    // MARK: - GlucoseKit

    let glucoseStore: GlucoseStore? = GlucoseStore()

    // MARK: - InsulinKit

    let doseStore: DoseStore

    // MARK: DoseStoreDelegate

    func doseStore(doseStore: DoseStore, hasEventsNeedingUpload pumpEvents: [PersistedPumpEvent], fromPumpID pumpID: String, withCompletion completionHandler: (uploadedObjects: [NSManagedObjectID]) -> Void) {
        guard let uploader = remoteDataManager.nightscoutUploader, pumpModel = pumpState?.pumpModel else {
            completionHandler(uploadedObjects: pumpEvents.map({ $0.objectID }))
            return
        }

        var objectIDs = [NSManagedObjectID]()
        var timestampedPumpEvents = [TimestampedHistoryEvent]()

        // TODO: LoopKit should return these in chronological order instead of reversing here.
        for event in pumpEvents.reverse() {
            objectIDs.append(event.objectID)

            if let raw = event.raw where raw.length > 0, let type = MinimedKit.PumpEventType(rawValue: raw[0])?.eventType, pumpEvent = type.init(availableData: raw, pumpModel: pumpModel) {
                timestampedPumpEvents.append(TimestampedHistoryEvent(pumpEvent: pumpEvent, date: event.date))
            }
        }

        uploader.upload(timestampedPumpEvents, forSource: "loop://\(UIDevice.currentDevice().name)", from: pumpModel) { (error) in
            if let error = error {
                self.logger.addError(error, fromSource: "NightscoutUploadKit")
                completionHandler(uploadedObjects: [])
            } else {
                completionHandler(uploadedObjects: objectIDs)
            }
        }
    }

    // MARK: - WatchKit

    private(set) var watchManager: WatchDataManager!

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

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(receivedRileyLinkManagerNotification(_:)), name: nil, object: rileyLinkManager)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(receivedRileyLinkPacketNotification(_:)), name: RileyLinkDevice.DidReceiveIdleMessageNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(receivedRileyLinkTimerTickNotification(_:)), name: RileyLinkDevice.DidUpdateTimerTickNotification, object: nil)

        if let pumpState = pumpState {
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(pumpStateValuesDidChange(_:)), name: PumpState.ValuesDidChangeNotification, object: pumpState)
        }

        loopManager = LoopDataManager(deviceDataManager: self)
        watchManager = WatchDataManager(deviceDataManager: self)
        nightscoutDataManager = NightscoutDataManager(deviceDataManager: self)

        carbStore?.delegate = self
        doseStore.delegate = self

        if NSUserDefaults.standardUserDefaults().receiverEnabled {
            receiver = Receiver()
            receiver?.delegate = self
        }

        if let transmitterID = NSUserDefaults.standardUserDefaults().transmitterID {
            transmitter = Transmitter(ID: transmitterID, passiveModeEnabled: true)
            transmitter?.delegate = self
        }

        enableRileyLinkHeartbeatIfNeeded()
    }
}
