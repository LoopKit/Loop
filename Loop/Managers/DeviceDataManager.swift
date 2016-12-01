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


final class DeviceDataManager: CarbStoreDelegate, CarbStoreSyncDelegate, DoseStoreDelegate, TransmitterDelegate, ReceiverDelegate {

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
            UserDefaults.standard.receiverEnabled = newValue
        }
    }

    var sensorInfo: SensorDisplayable? {
        return latestGlucoseG5 ?? latestGlucoseG4 ?? latestGlucoseFromShare ?? latestPumpStatusFromMySentry
    }

    var latestPumpStatus: RileyLinkKit.PumpStatus?

    // Returns a value in the range 0 - 1
    var pumpBatteryChargeRemaining: Double? {
        get {
            if let status = latestPumpStatusFromMySentry {
                return Double(status.batteryRemainingPercent) / 100
            } else if let status = latestPumpStatus {
                return batteryChemistry.chargeRemaining(voltage: status.batteryVolts)
            } else {
                return nil
            }
        }
    }

    // Battery monitor
    func observeBatteryDuring(_ block: () -> Void) {
        let oldVal = pumpBatteryChargeRemaining
        block()
        if let newVal = pumpBatteryChargeRemaining {
            if newVal == 0 {
                NotificationManager.sendPumpBatteryLowNotification()
            }

            if let oldVal = oldVal, newVal - oldVal >= 0.5 {
                AnalyticsManager.sharedManager.pumpBatteryWasReplaced()
            }
        }
    }


    // MARK: - RileyLink

    @objc private func receivedRileyLinkManagerNotification(_ note: Notification) {
        NotificationCenter.default.post(name: note.name, object: self, userInfo: note.userInfo)
    }

    /**
     Called when a new idle message is received by the RileyLink.

     Only MySentryPumpStatus messages are handled.

     - parameter note: The notification object
     */
    @objc private func receivedRileyLinkPacketNotification(_ note: Notification) {
        if let
            device = note.object as? RileyLinkDevice,
            let data = note.userInfo?[RileyLinkDevice.IdleMessageDataKey] as? Data,
            let message = PumpMessage(rxData: data)
        {
            switch message.packetType {
            case .mySentry:
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

    @objc private func receivedRileyLinkTimerTickNotification(_ note: Notification) {
        backfillGlucoseFromShareIfNeeded() {
            self.assertCurrentPumpData()
        }
    }

    func connectToRileyLink(_ device: RileyLinkDevice) {
        connectedPeripheralIDs.insert(device.peripheral.identifier.uuidString)

        rileyLinkManager.connectDevice(device)

        AnalyticsManager.sharedManager.didChangeRileyLinkConnectionState()
    }

    func disconnectFromRileyLink(_ device: RileyLinkDevice) {
        connectedPeripheralIDs.remove(device.peripheral.identifier.uuidString)

        rileyLinkManager.disconnectDevice(device)

        AnalyticsManager.sharedManager.didChangeRileyLinkConnectionState()

        if connectedPeripheralIDs.count == 0 {
            NotificationManager.clearPendingNotificationRequests()
        }
    }

    /// Controls the management of the RileyLink timer tick, which is a reliably-changing BLE
    /// characteristic which can cause the app to wake. For most users, the G5 Transmitter and 
    /// G4 Receiver are reliable as hearbeats, but users who find their resources extremely constrained
    /// due to greedy apps or older devices may choose to always enable the timer by always setting `true`
    private func enableRileyLinkHeartbeatIfNeeded() {
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
    private func updatePumpStatus(_ status: MySentryPumpStatusMessageBody, from device: RileyLinkDevice) {
        var pumpDateComponents = status.pumpDateComponents
        var glucoseDateComponents = status.glucoseDateComponents

        pumpDateComponents.timeZone = pumpState?.timeZone
        glucoseDateComponents?.timeZone = pumpState?.timeZone

        // The pump sends the same message 3x, so ignore it if we've already seen it.
        guard status != latestPumpStatusFromMySentry, let pumpDate = pumpDateComponents.date else {
            return
        }

        observeBatteryDuring {
            latestPumpStatusFromMySentry = status
        }

        // Gather PumpStatus from MySentry packet
        let pumpStatus: NightscoutUploadKit.PumpStatus?
        if let pumpDate = pumpDateComponents.date, let pumpID = pumpID {

            let batteryStatus = BatteryStatus(percent: status.batteryRemainingPercent)
            let iobStatus = IOBStatus(timestamp: pumpDate, iob: status.iob)

            pumpStatus = NightscoutUploadKit.PumpStatus(clock: pumpDate, pumpID: pumpID, iob: iobStatus, battery: batteryStatus, reservoir: status.reservoirRemainingUnits)
        } else {
            pumpStatus = nil
            self.logger.addError("Could not interpret pump clock: \(pumpDateComponents)", fromSource: "RileyLink")
        }

        // Trigger device status upload, even if something is wrong with pumpStatus
        nightscoutDataManager.uploadDeviceStatus(pumpStatus)

        backfillGlucoseFromShareIfNeeded()

        // Minimed sensor glucose
        switch status.glucose {
        case .active(glucose: let glucose):
            if let date = glucoseDateComponents?.date {
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
                        NotificationCenter.default.post(name: .GlucoseUpdated, object: self)
                    }
                }
            }
        default:
            break
        }

        // Upload sensor glucose to Nightscout
        remoteDataManager.nightscoutUploader?.uploadSGVFromMySentryPumpStatus(status, device: device.deviceURI)

        // Sentry packets are sent in groups of 3, 5s apart. Wait 11s before allowing the loop data to continue to avoid conflicting comms.
        DispatchQueue.global(qos: DispatchQoS.QoSClass.utility).asyncAfter(deadline: DispatchTime.now() + Double(Int64(11 * NSEC_PER_SEC)) / Double(NSEC_PER_SEC)) {
            self.updateReservoirVolume(status.reservoirRemainingUnits, at: pumpDate, withTimeLeft: TimeInterval(minutes: Double(status.reservoirRemainingMinutes)))
        }

    }

    /**
     Store a new reservoir volume and notify observers of new pump data.

     - parameter units:    The number of units remaining
     - parameter date:     The date the reservoir was read
     - parameter timeLeft: The approximate time before the reservoir is empty
     */
    private func updateReservoirVolume(_ units: Double, at date: Date, withTimeLeft timeLeft: TimeInterval?) {
        doseStore.addReservoirValue(units, atDate: date) { (newValue, previousValue, areStoredValuesContinuous, error) -> Void in
            if let error = error {
                self.logger.addError(error, fromSource: "DoseStore")
                return
            }

            if self.preferredInsulinDataSource == .pumpHistory || !areStoredValuesContinuous {
                self.fetchPumpHistory { (error) in
                    // Notify and trigger a loop as long as we have fresh, reliable pump data.
                    if error == nil || areStoredValuesContinuous {
                        NotificationCenter.default.post(name: .PumpStatusUpdated, object: self)
                    }
                }
            } else {
                NotificationCenter.default.post(name: .PumpStatusUpdated, object: self)
            }

            // Send notifications for low reservoir if necessary
            if let newVolume = newValue?.unitVolume, let previousVolume = previousValue?.unitVolume {
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
    private func fetchPumpHistory(_ completionHandler: @escaping (_ error: Error?) -> Void) {
        guard let device = rileyLinkManager.firstConnectedDevice else {
            return
        }

        let startDate = doseStore.pumpEventQueryAfterDate

        device.ops?.getHistoryEvents(since: startDate) { (result) in
            switch result {
            case let .success(events, _):
                self.doseStore.add(events) { (error) in
                    if let error = error {
                        self.logger.addError("Failed to store history: \(error)", fromSource: "DoseStore")
                    }

                    completionHandler(error)
                }
            case .failure(let error):
                self.logger.addError("Failed to fetch history: \(error)", fromSource: "RileyLink")

                completionHandler(error)
            }
        }
    }

    /**
     Read the pump's current state, including reservoir and clock

     - parameter completion: A closure called after the command is complete. This closure takes a single Result argument:
        - Success(status, date): The pump status, and the resolved date according to the pump's clock
        - Failure(error): An error describing why the command failed
     */
    private func readPumpData(_ completion: @escaping (RileyLinkKit.Either<(status: RileyLinkKit.PumpStatus, date: Date), Error>) -> Void) {
        guard let device = rileyLinkManager.firstConnectedDevice, let ops = device.ops else {
            completion(.failure(LoopError.configurationError))
            return
        }

        ops.readPumpStatus { (result) in
            switch result {
            case .success(let status):
                var clock = status.clock
                clock.timeZone = ops.pumpState.timeZone

                guard let date = clock.date else {
                    self.logger.addError("Could not interpret pump clock: \(clock)", fromSource: "RileyLink")
                    completion(.failure(LoopError.configurationError))
                    return
                }
                completion(.success(status: status, date: date))
            case .failure(let error):
                self.logger.addError("Failed to fetch pump status: \(error)", fromSource: "RileyLink")
                completion(.failure(error))
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
        let pumpStatusAgeTolerance = rileyLinkManager.idleListeningEnabled ? TimeInterval(minutes: 11) : TimeInterval(minutes: 4)

        // If we don't yet have pump status, or it's old, poll for it.
        if  doseStore.lastReservoirValue == nil ||
            doseStore.lastReservoirValue!.startDate.timeIntervalSinceNow <= -pumpStatusAgeTolerance {
            readPumpData { (result) in
                let nsPumpStatus: NightscoutUploadKit.PumpStatus?
                switch result {
                case .success(let (status, date)):
                    self.observeBatteryDuring {
                        self.latestPumpStatus = status
                    }

                    self.updateReservoirVolume(status.reservoir, at: date, withTimeLeft: nil)
                    let battery = BatteryStatus(voltage: status.batteryVolts, status: BatteryIndicator(batteryStatus: status.batteryStatus))


                    nsPumpStatus = NightscoutUploadKit.PumpStatus(clock: date, pumpID: status.pumpID, iob: nil, battery: battery, suspended: status.suspended, bolusing: status.bolusing, reservoir: status.reservoir)
                case .failure(let error):
                    self.troubleshootPumpComms(using: device)
                    self.nightscoutDataManager.uploadLoopStatus(loopError: error)
                    nsPumpStatus = nil
                }
                self.nightscoutDataManager.uploadDeviceStatus(nsPumpStatus)
            }
        }
    }

    /// Send a bolus command and handle the result
    ///
    /// - parameter units:      The number of units to deliver
    /// - parameter completion: A clsure called after the command is complete. This closure takes a single argument:
    ///     - error: An error describing why the command failed
    func enactBolus(units: Double, completion: @escaping (_ error: Error?) -> Void) {
        guard units > 0 else {
            completion(nil)
            return
        }

        guard let device = rileyLinkManager.firstConnectedDevice else {
            completion(LoopError.connectionError)
            return
        }

        guard let ops = device.ops else {
            completion(LoopError.configurationError)
            return
        }

        let setBolus = {
            ops.setNormalBolus(units: units) { (error) in
                if let error = error {
                    self.logger.addError(error, fromSource: "Bolus")
                    completion(LoopError.communicationError)
                } else {
                    self.loopManager.recordBolus(units, at: Date())
                    completion(nil)
                }
            }
        }

        // If we don't have recent pump data, or the pump was recently rewound, read new pump data before bolusing.
        if  doseStore.lastReservoirValue == nil ||
            doseStore.lastReservoirVolumeDrop < 0 ||
            doseStore.lastReservoirValue!.startDate.timeIntervalSinceNow <= TimeInterval(minutes: -5)
        {
            readPumpData { (result) in
                switch result {
                case .success(let (status, date)):
                    self.doseStore.addReservoirValue(status.reservoir, atDate: date) { (newValue, _, _, error) in
                        if let error = error {
                            self.logger.addError(error, fromSource: "Bolus")
                            completion(error)
                        } else {
                            setBolus()
                        }
                    }
                case .failure(let error):
                    completion(error)
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
    private func troubleshootPumpComms(using device: RileyLinkDevice) {

        // How long we should wait before we re-tune the RileyLink
        let tuneTolerance = TimeInterval(minutes: 14)

        if device.lastTuned == nil || device.lastTuned!.timeIntervalSinceNow <= -tuneTolerance {
            device.tunePump { (result) in
                switch result {
                case .success(let scanResult):
                    self.logger.addError("Device auto-tuned to \(scanResult.bestFrequency) MHz", fromSource: "RileyLink")
                case .failure(let error):
                    self.logger.addError("Device auto-tune failed with error: \(error)", fromSource: "RileyLink")
                }
            }
        }
    }

    // MARK: - G5 Transmitter
    /// The G5 transmitter is a reliable heartbeat by which we can assert the loop state.

    // MARK: TransmitterDelegate

    func transmitter(_ transmitter: xDripG5.Transmitter, didError error: Error) {
        logger.addMessage([
                "error": "\(error)",
                "collectedAt": DateFormatter.ISO8601StrictDateFormatter().string(from: Date())
            ], toCollection: "g5"
        )

        assertCurrentPumpData()
    }

    func transmitter(_ transmitter: xDripG5.Transmitter, didRead glucose: xDripG5.Glucose) {
        assertCurrentPumpData()

        guard glucose != latestGlucoseG5 else {
            return
        }

        latestGlucoseG5 = glucose

        guard let glucoseStore = glucoseStore, let quantity = glucose.glucose else {
            NotificationCenter.default.post(name: .GlucoseUpdated, object: self)
            return
        }

        let device = HKDevice(name: "xDripG5", manufacturer: "Dexcom", model: "G5 Mobile", hardwareVersion: nil, firmwareVersion: nil, softwareVersion: String(xDripG5VersionNumber), localIdentifier: nil, udiDeviceIdentifier: "00386270000002")

        glucoseStore.addGlucose(quantity, date: glucose.readDate, isDisplayOnly: glucose.isDisplayOnly, device: device) { (success, _, error) -> Void in
            if let error = error {
                self.logger.addError(error, fromSource: "GlucoseStore")
            }

            if success {
                NotificationCenter.default.post(name: .GlucoseUpdated, object: self)
            }
        }
    }

    public func transmitter(_ transmitter: Transmitter, didReadUnknownData data: Data) {
        logger.addMessage([
                "unknownData": data.hexadecimalString,
                "collectedAt": DateFormatter.ISO8601StrictDateFormatter().string(from: Date())
            ], toCollection: "g5"
        )
    }

    // MARK: G5 data

    fileprivate var latestGlucoseG5: xDripG5.Glucose?

    fileprivate var latestGlucoseFromShare: ShareGlucose?

    /**
     Attempts to backfill glucose data from the share servers if a G5 connection hasn't been established.
     
     - parameter completion: An optional closure called after the command is complete.
     */
    private func backfillGlucoseFromShareIfNeeded(_ completion: (() -> Void)? = nil) {
        // We should have no G4 Share or G5 data, and a configured ShareClient and GlucoseStore.
        guard latestGlucoseG4 == nil && latestGlucoseG5 == nil, let shareClient = remoteDataManager.shareClient, let glucoseStore = glucoseStore else {
            completion?()
            return
        }

        // If our last glucose was less than 4.5 minutes ago, don't fetch.
        if let latestGlucose = glucoseStore.latestGlucose, latestGlucose.startDate.timeIntervalSinceNow > -TimeInterval(minutes: 4.5) {
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

            self.latestGlucoseFromShare = glucose.first

            // Ignore glucose values that are up to a minute newer than our previous value, to account for possible time shifting in Share data
            let newGlucose = glucose.filterDateRange(glucoseStore.latestGlucose?.startDate.addingTimeInterval(TimeInterval(minutes: 1)), nil).map {
                return (quantity: $0.quantity, date: $0.startDate, isDisplayOnly: false)
            }

            glucoseStore.addGlucoseValues(newGlucose, device: nil) { (success, _, error) -> Void in
                if let error = error {
                    self.logger.addError(error, fromSource: "GlucoseStore")
                }

                if success {
                    NotificationCenter.default.post(name: .GlucoseUpdated, object: self)
                }

                completion?()
            }
        }
    }

    // MARK: - Share Receiver

    // MARK: ReceiverDelegate

    fileprivate var latestGlucoseG4: GlucoseG4?

    func receiver(_ receiver: Receiver, didReadGlucoseHistory glucoseHistory: [GlucoseG4]) {
        assertCurrentPumpData()

        guard let latest = glucoseHistory.sorted(by: { $0.sequence < $1.sequence }).last, latest != latestGlucoseG4 else {
            return
        }
        latestGlucoseG4 = latest

        guard let glucoseStore = glucoseStore else {
            return
        }

        // In the event that some of the glucose history was already backfilled from Share, don't overwrite it.
        let includeAfter = glucoseStore.latestGlucose?.startDate.addingTimeInterval(TimeInterval(minutes: 1))

        let validGlucose = glucoseHistory.flatMap({
            $0.isStateValid ? $0 : nil
        }).filterDateRange(includeAfter, nil).map({
            (quantity: $0.quantity, date: $0.startDate, isDisplayOnly: $0.isDisplayOnly)
        })

        // "Dexcom G4 Platinum Transmitter (Retail) US" - see https://accessgudid.nlm.nih.gov/devices/search?query=dexcom+g4
        let device = HKDevice(name: "G4ShareSpy", manufacturer: "Dexcom", model: "G4 Share", hardwareVersion: nil, firmwareVersion: nil, softwareVersion: String(G4ShareSpyVersionNumber), localIdentifier: nil, udiDeviceIdentifier: "40386270000048")

        glucoseStore.addGlucoseValues(validGlucose, device: device) { (success, _, error) -> Void in
            if let error = error {
                self.logger.addError(error, fromSource: "GlucoseStore")
            }

            if success {
                NotificationCenter.default.post(name: .GlucoseUpdated, object: self)
            }
        }
    }

    func receiver(_ receiver: Receiver, didError error: Error) {
        logger.addMessage(["error": "\(error)", "collectedAt": DateFormatter.ISO8601StrictDateFormatter().string(from: Date())], toCollection: "g4")

        assertCurrentPumpData()
    }

    func receiver(_ receiver: Receiver, didLogBluetoothEvent event: String) {
        // Uncomment to debug communication
        // logger.addMessage(["event": "\(event)", "collectedAt": NSDateFormatter.ISO8601StrictDateFormatter().stringFromDate(NSDate())], toCollection: "g4")
    }

    // MARK: - Configuration

    // MARK: Pump

    private var connectedPeripheralIDs: Set<String> = Set(UserDefaults.standard.connectedPeripheralIDs) {
        didSet {
            UserDefaults.standard.connectedPeripheralIDs = Array(connectedPeripheralIDs)
        }
    }

    var pumpID: String? {
        get {
            return pumpState?.pumpID
        }
        set {
            guard newValue != pumpState?.pumpID else {
                return
            }

            var pumpID = newValue

            if let pumpID = pumpID, pumpID.characters.count == 6 {
                let pumpState = PumpState(pumpID: pumpID, pumpRegion: self.pumpState?.pumpRegion ?? .northAmerica)

                if let timeZone = self.pumpState?.timeZone {
                    pumpState.timeZone = timeZone
                }

                self.pumpState = pumpState
            } else {
                pumpID = nil
                self.pumpState = nil
            }

            remoteDataManager.nightscoutUploader?.reset()
            doseStore.pumpID = pumpID

            UserDefaults.standard.pumpID = pumpID
        }
    }

    var pumpState: PumpState? {
        didSet {
            rileyLinkManager.pumpState = pumpState

            if let oldValue = oldValue {
                NotificationCenter.default.removeObserver(self, name: .PumpStateValuesDidChange, object: oldValue)
            }

            if let pumpState = pumpState {
                NotificationCenter.default.addObserver(self, selector: #selector(pumpStateValuesDidChange(_:)), name: .PumpStateValuesDidChange, object: pumpState)
            }
        }
    }

    @objc private func pumpStateValuesDidChange(_ note: Notification) {
        switch note.userInfo?[PumpState.PropertyKey] as? String {
        case "timeZone"?:
            UserDefaults.standard.pumpTimeZone = pumpState?.timeZone

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
            if let sentrySupported = pumpState?.pumpModel?.hasMySentry, !sentrySupported {
                rileyLinkManager.idleListeningEnabled = false
            }

            UserDefaults.standard.pumpModelNumber = pumpState?.pumpModel?.rawValue
        case "pumpRegion"?:
            UserDefaults.standard.pumpRegion = pumpState?.pumpRegion
        case "lastHistoryDump"?, "awakeUntil"?:
            break
        default:
            break
        }
    }

    /// The user's preferred method of fetching insulin data from the pump
    var preferredInsulinDataSource = UserDefaults.standard.preferredInsulinDataSource ?? .pumpHistory {
        didSet {
            UserDefaults.standard.preferredInsulinDataSource = preferredInsulinDataSource
        }
    }
    
    /// The Default battery chemistry is Alkaline
    var batteryChemistry = UserDefaults.standard.batteryChemistry ?? .alkaline {
        didSet {
            UserDefaults.standard.batteryChemistry = batteryChemistry
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

            if let transmitterID = newValue, transmitterID.characters.count == 6 {
                transmitter = Transmitter(ID: transmitterID, passiveModeEnabled: true)
            } else {
                transmitter = nil
            }

            UserDefaults.standard.transmitterID = newValue
        }
    }

    // MARK: Loop model inputs

    var basalRateSchedule: BasalRateSchedule? = UserDefaults.standard.basalRateSchedule {
        didSet {
            doseStore.basalProfile = basalRateSchedule

            UserDefaults.standard.basalRateSchedule = basalRateSchedule

            AnalyticsManager.sharedManager.didChangeBasalRateSchedule()
        }
    }

    var carbRatioSchedule: CarbRatioSchedule? = UserDefaults.standard.carbRatioSchedule {
        didSet {
            carbStore?.carbRatioSchedule = carbRatioSchedule

            UserDefaults.standard.carbRatioSchedule = carbRatioSchedule

            AnalyticsManager.sharedManager.didChangeCarbRatioSchedule()
        }
    }

    var insulinActionDuration: TimeInterval? = UserDefaults.standard.insulinActionDuration {
        didSet {
            doseStore.insulinActionDuration = insulinActionDuration

            UserDefaults.standard.insulinActionDuration = insulinActionDuration

            if oldValue != insulinActionDuration {
                AnalyticsManager.sharedManager.didChangeInsulinActionDuration()
            }
        }
    }

    var insulinSensitivitySchedule: InsulinSensitivitySchedule? = UserDefaults.standard.insulinSensitivitySchedule {
        didSet {
            carbStore?.insulinSensitivitySchedule = insulinSensitivitySchedule
            doseStore.insulinSensitivitySchedule = insulinSensitivitySchedule

            UserDefaults.standard.insulinSensitivitySchedule = insulinSensitivitySchedule

            AnalyticsManager.sharedManager.didChangeInsulinSensitivitySchedule()
        }
    }

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule? = UserDefaults.standard.glucoseTargetRangeSchedule {
        didSet {
            UserDefaults.standard.glucoseTargetRangeSchedule = glucoseTargetRangeSchedule

            NotificationCenter.default.post(name: .LoopSettingsUpdated, object: self)

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
    @discardableResult
    func enableWorkoutMode(until endDate: Date) -> Bool {
        guard let glucoseTargetRangeSchedule = glucoseTargetRangeSchedule else {
            return false
        }

        _ = glucoseTargetRangeSchedule.setWorkoutOverride(until: endDate)

        NotificationCenter.default.post(name: .LoopSettingsUpdated, object: self)

        return true
    }

    func disableWorkoutMode() {
        glucoseTargetRangeSchedule?.clearOverride()

        NotificationCenter.default.post(name: .LoopSettingsUpdated, object: self)
    }

    var maximumBasalRatePerHour: Double? = UserDefaults.standard.maximumBasalRatePerHour {
        didSet {
            UserDefaults.standard.maximumBasalRatePerHour = maximumBasalRatePerHour

            AnalyticsManager.sharedManager.didChangeMaximumBasalRate()
        }
    }

    var maximumBolus: Double? = UserDefaults.standard.maximumBolus {
        didSet {
            UserDefaults.standard.maximumBolus = maximumBolus

            AnalyticsManager.sharedManager.didChangeMaximumBolus()
        }
    }

    // MARK: - CarbKit

    let carbStore: CarbStore?

    // MARK: CarbStoreDelegate

    func carbStore(_: CarbStore, didError error: CarbStore.CarbStoreError) {
        logger.addError(error, fromSource: "CarbStore")
    }

    func carbStore(_ carbStore: CarbStore, hasEntriesNeedingUpload entries: [CarbEntry], withCompletion completionHandler: @escaping (_ uploadedObjects: [String]) -> Void) {

        guard let uploader = remoteDataManager.nightscoutUploader else {
            completionHandler([])
            return
        }

        let nsCarbEntries = entries.map({ MealBolusNightscoutTreatment(carbEntry: $0)})

        uploader.upload(nsCarbEntries) { (result) in
            switch result {
            case .success(let ids):
                // Pass new ids back
                completionHandler(ids)
            case .failure(let error):
                self.logger.addError(error, fromSource: "NightscoutUploader")
                completionHandler([])
            }
        }
    }

    func carbStore(_ carbStore: CarbStore, hasModifiedEntries entries: [CarbEntry], withCompletion completionHandler: @escaping (_ uploadedObjects: [String]) -> Void) {
        
        guard let uploader = remoteDataManager.nightscoutUploader else {
            completionHandler([])
            return
        }

        let nsCarbEntries = entries.map({ MealBolusNightscoutTreatment(carbEntry: $0)})

        uploader.modifyTreatments(nsCarbEntries) { (error) in
            if let error = error {
                self.logger.addError(error, fromSource: "NightscoutUploader")
                completionHandler([])
            } else {
                completionHandler(entries.map { $0.externalId ?? "" } )
            }
        }

    }

    func carbStore(_ carbStore: CarbStore, hasDeletedEntries ids: [String], withCompletion completionHandler: @escaping ([String]) -> Void) {

        guard let uploader = remoteDataManager.nightscoutUploader else {
            completionHandler([])
            return
        }

        uploader.deleteTreatmentsById(ids) { (error) in
            if let error = error {
                self.logger.addError(error, fromSource: "NightscoutUploader")
                completionHandler([])
            } else {
                completionHandler(ids)
            }
        }
        completionHandler([])
    }


    // MARK: - GlucoseKit

    let glucoseStore: GlucoseStore? = GlucoseStore()

    // MARK: - InsulinKit

    let doseStore: DoseStore

    // MARK: DoseStoreDelegate

    func doseStore(_ doseStore: DoseStore, hasEventsNeedingUpload pumpEvents: [PersistedPumpEvent], fromPumpID pumpID: String, withCompletion completionHandler: @escaping (_ uploadedObjects: [NSManagedObjectID]) -> Void) {
        guard let uploader = remoteDataManager.nightscoutUploader, let pumpModel = pumpState?.pumpModel else {
            completionHandler(pumpEvents.map({ $0.objectID }))
            return
        }

        var objectIDs = [NSManagedObjectID]()
        var timestampedPumpEvents = [TimestampedHistoryEvent]()

        for event in pumpEvents {
            objectIDs.append(event.objectID)

            if let raw = event.raw, raw.count > 0, let type = MinimedKit.PumpEventType(rawValue: raw[0])?.eventType, let pumpEvent = type.init(availableData: raw, pumpModel: pumpModel) {
                timestampedPumpEvents.append(TimestampedHistoryEvent(pumpEvent: pumpEvent, date: event.date))
            }
        }

        uploader.upload(timestampedPumpEvents, forSource: "loop://\(UIDevice.current.name)", from: pumpModel) { (error) in
            if let error = error {
                self.logger.addError(error, fromSource: "NightscoutUploadKit")
                completionHandler([])
            } else {
                completionHandler(objectIDs)
            }
        }
    }

    // MARK: - WatchKit

    private(set) var watchManager: WatchDataManager!
    
    // MARK: - Status Extension
    
    private(set) var statusExtensionManager: StatusExtensionDataManager!

    // MARK: - Initialization

    private(set) var loopManager: LoopDataManager!

    init() {
        let pumpID = UserDefaults.standard.pumpID

        doseStore = DoseStore(
            pumpID: pumpID,
            insulinActionDuration: insulinActionDuration,
            basalProfile: basalRateSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
        )

        carbStore = CarbStore(
            defaultAbsorptionTimes: (fast: TimeInterval(hours: 2), medium: TimeInterval(hours: 3), slow: TimeInterval(hours: 4)),
            carbRatioSchedule: carbRatioSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule
        )

        var idleListeningEnabled = true

        if let pumpID = pumpID {
            let pumpState = PumpState(pumpID: pumpID, pumpRegion: UserDefaults.standard.pumpRegion ?? .northAmerica)

            if let timeZone = UserDefaults.standard.pumpTimeZone {
                pumpState.timeZone = timeZone
            }

            if let pumpModelNumber = UserDefaults.standard.pumpModelNumber {
                if let model = PumpModel(rawValue: pumpModelNumber) {
                    pumpState.pumpModel = model

                    idleListeningEnabled = model.hasMySentry
                }
            }

            self.pumpState = pumpState
        }

        rileyLinkManager = RileyLinkDeviceManager(
            pumpState: self.pumpState,
            autoConnectIDs: connectedPeripheralIDs
        )
        rileyLinkManager.idleListeningEnabled = idleListeningEnabled

        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkManagerNotification(_:)), name: nil, object: rileyLinkManager)
        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkPacketNotification(_:)), name: .RileyLinkDeviceDidReceiveIdleMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkTimerTickNotification(_:)), name: .RileyLinkDeviceDidUpdateTimerTick, object: nil)

        if let pumpState = pumpState {
            NotificationCenter.default.addObserver(self, selector: #selector(pumpStateValuesDidChange(_:)), name: .PumpStateValuesDidChange, object: pumpState)
        }

        loopManager = LoopDataManager(deviceDataManager: self)
        watchManager = WatchDataManager(deviceDataManager: self)
        statusExtensionManager = StatusExtensionDataManager(deviceDataManager: self)
        nightscoutDataManager = NightscoutDataManager(deviceDataManager: self)

        carbStore?.delegate = self
        carbStore?.syncDelegate = self
        doseStore.delegate = self

        if UserDefaults.standard.receiverEnabled {
            receiver = Receiver()
            receiver?.delegate = self
        }

        if let transmitterID = UserDefaults.standard.transmitterID, transmitterID.characters.count == 6 {
            transmitter = Transmitter(ID: transmitterID, passiveModeEnabled: true)
            transmitter?.delegate = self
        }

        enableRileyLinkHeartbeatIfNeeded()
    }
}


extension DeviceDataManager: CustomDebugStringConvertible {
    var debugDescription: String {
        return [
            "## DeviceDataManager",
            "receiverEnabled: \(receiverEnabled)",
            "latestPumpStatusFromMySentry: \(latestPumpStatusFromMySentry)",
            "latestGlucoseG5: \(latestGlucoseG5)",
            "latestGlucoseFromShare: \(latestGlucoseFromShare)",
            "latestGlucoseG4: \(latestGlucoseG4)",
            "pumpState: \(String(reflecting: pumpState))",
            "preferredInsulinDataSource: \(preferredInsulinDataSource)",
            "transmitterID: \(transmitterID)",
            "glucoseTargetRangeSchedule: \(glucoseTargetRangeSchedule?.debugDescription ?? "")",
            "workoutModeEnabled: \(workoutModeEnabled)",
            "maximumBasalRatePerHour: \(maximumBasalRatePerHour)",
            "maximumBolus: \(maximumBolus)",
            String(reflecting: rileyLinkManager)
        ].joined(separator: "\n")
    }
}


extension Notification.Name {
    /// Notification posted by the instance when new glucose data was processed
    static let GlucoseUpdated = Notification.Name(rawValue:  "com.loudnate.Naterade.notification.GlucoseUpdated")

    /// Notification posted by the instance when new pump data was processed
    static let PumpStatusUpdated = Notification.Name(rawValue: "com.loudnate.Naterade.notification.PumpStatusUpdated")

    /// Notification posted by the instance when loop configuration was changed
    static let LoopSettingsUpdated = Notification.Name(rawValue: "com.loudnate.Naterade.notification.LoopSettingsUpdated")
}

