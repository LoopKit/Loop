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
import GlucoseKit
import HealthKit
import InsulinKit
import LoopKit
import LoopUI
import MinimedKit
import NightscoutUploadKit
import RileyLinkKit
import RileyLinkKitUI
import RileyLinkBLEKit


final class DeviceDataManager {

    private let queue = DispatchQueue(label: "com.loopkit.DeviceManagerQueue", qos: .utility)

    let logger = DiagnosticLogger.shared!

    /// Remember the launch date of the app for diagnostic reporting
    private let launchDate = Date()

    /// Manages all the RileyLinks
    let rileyLinkManager: RileyLinkDeviceManager

    /// Manages authentication for remote services
    let remoteDataManager = RemoteDataManager()

    private var nightscoutDataManager: NightscoutDataManager!

    // TODO: Isolate to queue
    private var latestPumpStatus: RileyLinkKit.PumpStatus?

    // Main queue access only
    private(set) var lastError: (date: Date, error: Error)?

    /// Isolated to queue
    private var lastTimerTick: Date = .distantPast

    private func setLastError(error: Error) {
        DispatchQueue.main.async { // Synchronize writes
            self.lastError = (date: Date(), error: error)
            // TODO: Notify observers of change
        }
    }

    // TODO: Isolate to queue
    // Returns a value in the range 0 - 1
    var pumpBatteryChargeRemaining: Double? {
        get {
            if let status = latestPumpStatusFromMySentry {
                return Double(status.batteryRemainingPercent) / 100
            } else if let status = latestPumpStatus {
                return batteryChemistry.chargeRemaining(voltage: status.batteryVolts)
            } else {
                return statusExtensionManager.context?.batteryPercentage
            }
        }
    }

    // Battery monitor
    private func observeBatteryDuring(_ block: () -> Void) {
        let oldVal = pumpBatteryChargeRemaining
        block()
        if let newVal = pumpBatteryChargeRemaining {
            if newVal == 0 {
                NotificationManager.sendPumpBatteryLowNotification()
            }

            if let oldVal = oldVal, newVal - oldVal >= 0.5 {
                AnalyticsManager.shared.pumpBatteryWasReplaced()
            }
        }
    }

    // MARK: - RileyLink

    @objc private func deviceStatusDidChange(_ note: Notification) {
        switch note.name {
        case Notification.Name.DeviceConnectionStateDidChange,
             Notification.Name.DeviceNameDidChange:
            updateDoseStoreDeviceFromRileyLink(state: pumpState)
        default:
            break
        }
    }

    private func updateDoseStoreDeviceFromRileyLink(state: PumpState?) {
        // Update the HKDevice to include the name, pump model, or connection status change
        rileyLinkManager.getDevices { (devices) in
            devices.firstConnected?.getStatus { (status) in
                self.loopManager.doseStore.setDevice(status.device(settings: self.pumpSettings, pumpState: state))
            }
        }
    }

    @objc private func deviceStateDidChange(_ note: Notification) {
        guard
            let device = note.object as? RileyLinkDevice,
            let deviceState = note.userInfo?[RileyLinkDevice.notificationDeviceStateKey] as? DeviceState
            else {
                return
        }

        queue.async {
            self.deviceStates[device.peripheralIdentifier] = deviceState
        }
    }

    /**
     Called when a new idle message is received by the RileyLink.

     Only MySentryPumpStatus messages are handled.

     - parameter note: The notification object
     */
    @objc private func receivedRileyLinkPacketNotification(_ note: Notification) {
        guard let device = note.object as? RileyLinkDevice,
            let packet = note.userInfo?[RileyLinkDevice.notificationPacketKey] as? RFPacket,
            let data = MinimedPacket(encodedData: packet.data)?.data,
            let message = PumpMessage(rxData: data),
            let address = pumpSettings?.pumpID,
            message.address.hexadecimalString == address,
            case .mySentry = message.packetType
        else {
            return
        }

        queue.async {
            switch message.messageBody {
            case let body as MySentryPumpStatusMessageBody:
                self.updatePumpStatus(body, from: device)
            case is MySentryAlertMessageBody, is MySentryAlertClearedMessageBody:
                break
            case let body:
                // TODO: I think we've learned everything we're going to learn here.
                self.logger.forCategory("MySentry").info(["messageType": Int(message.messageType.rawValue), "messageBody": body.txData.hexadecimalString])
            }
        }
    }

    @objc private func receivedRileyLinkTimerTickNotification(_: Notification) {
        queue.async {
            self.lastTimerTick = Date()

            self.cgmManager?.fetchNewDataIfNeeded(with: self) { (result) in
                if case .newData = result {
                    AnalyticsManager.shared.didFetchNewCGMData()
                }

                // TODO: Isolate to queue?
                self.cgmManager(self.cgmManager!, didUpdateWith: result)
            }
        }
    }

    func connectToRileyLink(_ device: RileyLinkDevice) {
        queue.async {
            self.connectedPeripheralIDs.insert(device.peripheralIdentifier.uuidString)

            self.rileyLinkManager.connect(device)

            AnalyticsManager.shared.didChangeRileyLinkConnectionState()
        }
    }

    func disconnectFromRileyLink(_ device: RileyLinkDevice) {
        queue.async {
            self.connectedPeripheralIDs.remove(device.peripheralIdentifier.uuidString)

            self.rileyLinkManager.disconnect(device)

            AnalyticsManager.shared.didChangeRileyLinkConnectionState()

            if self.connectedPeripheralIDs.count == 0 {
                NotificationManager.clearPendingNotificationRequests()
            }
        }
    }

    /// TODO: Isolate to queue
    func updateTimerTickPreference() {
        queue.async {
            /// Controls the management of the RileyLink timer tick, which is a reliably-changing BLE
            /// characteristic which can cause the app to wake. For most users, the G5/G6 Transmitter and
            /// G4 Receiver are reliable as hearbeats, but users who find their resources extremely constrained
            /// due to greedy apps or older devices may choose to always enable the timer by always setting `true`
            self.rileyLinkManager.timerTickEnabled = self.isPumpDataStale() || !(self.cgmManager?.providesBLEHeartbeat == true)
        }
    }

    /**
     Attempts to fix an extended communication failure between a RileyLink device and the pump

     - parameter device: The RileyLink device
     */
    private func troubleshootPumpComms(using device: RileyLinkDevice) {
        /// TODO: Isolate to queue?
        // Ensuring timer tick is enabled will allow more tries to bring the pump data up-to-date.
        updateTimerTickPreference()

        guard let pumpOps = pumpOps else {
            return
        }

        // How long we should wait before we re-tune the RileyLink
        let tuneTolerance = TimeInterval(minutes: 14)

        let deviceState = deviceStates[device.peripheralIdentifier, default: DeviceState()]
        let lastTuned = deviceState.lastTuned ?? .distantPast

        if lastTuned.timeIntervalSinceNow <= -tuneTolerance {
            pumpOps.runSession(withName: "Tune pump", using: device) { (session) in
                do {
                    let scanResult = try session.tuneRadio(current: deviceState.lastValidFrequency)
                    self.logger.addError("Device \(device.name ?? "") auto-tuned to \(scanResult.bestFrequency) MHz", fromSource: "RileyLink")

                    self.queue.async {
                        self.deviceStates[device.peripheralIdentifier] = DeviceState(
                            lastTuned: Date(),
                            lastValidFrequency: scanResult.bestFrequency
                        )
                    }
                } catch let error {
                    self.logger.addError("Device \(device.name ?? "") auto-tune failed with error: \(error)", fromSource: "RileyLink")
                    self.rileyLinkManager.deprioritize(device)
                    self.setLastError(error: error)
                }
            }
        } else {
            rileyLinkManager.deprioritize(device)
        }
    }

    // MARK: Pump data

    /// TODO: Isolate to queue
    fileprivate var latestPumpStatusFromMySentry: MySentryPumpStatusMessageBody? {
        didSet {
            if let manager = cgmManager as? EnliteCGMManager {
                manager.sensorState = latestPumpStatusFromMySentry
            }
        }
    }

    /**
     Handles receiving a MySentry status message, which are only posted by MM x23 pumps.

     This message has two important pieces of info about the pump: reservoir volume and battery.

     Because the RileyLink must actively listen for these packets, they are not a reliable heartbeat. However, we can still use them to assert glucose data is current.

     - parameter status: The status message body
     - parameter device: The RileyLink that received the message
     */
    private func updatePumpStatus(_ status: MySentryPumpStatusMessageBody, from device: RileyLinkDevice) {
        dispatchPrecondition(condition: .onQueue(queue))

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
        if let pumpID = pumpSettings?.pumpID {
            let batteryStatus = BatteryStatus(percent: status.batteryRemainingPercent)
            let iobStatus = IOBStatus(timestamp: pumpDate, iob: status.iob)

            pumpStatus = NightscoutUploadKit.PumpStatus(clock: pumpDate, pumpID: pumpID, iob: iobStatus, battery: batteryStatus, reservoir: status.reservoirRemainingUnits)
        } else {
            pumpStatus = nil
            logger.addError("Could not interpret pump clock: \(pumpDateComponents)", fromSource: "RileyLink")
        }

        device.getStatus { (status) in
            // Trigger device status upload, even if something is wrong with pumpStatus
            self.queue.async {
                self.nightscoutDataManager.uploadDeviceStatus(pumpStatus, rileylinkDevice: status, deviceState: self.deviceStates[device.peripheralIdentifier])
            }
        }

        switch status.glucose {
        case .active(glucose: let glucose):
            // Enlite data is included
            if let date = glucoseDateComponents?.date {
                loopManager.addGlucose([(
                    quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliter(), doubleValue: Double(glucose)),
                    date: date,
                    isDisplayOnly: false
                )], from: nil)
            }
        case .off:
            // Enlite is disabled, so assert glucose from another source
            cgmManager?.fetchNewDataIfNeeded(with: self) { (result) in
                switch result {
                case .newData(let values):
                    self.loopManager.addGlucose(values, from: self.cgmManager?.device)
                case .noData:
                    break
                case .error(let error):
                    self.setLastError(error: error)
                    break
                }
            }
        default:
            break
        }

        // Upload sensor glucose to Nightscout
        remoteDataManager.nightscoutService.uploader?.uploadSGVFromMySentryPumpStatus(status, device: device.deviceURI)

        // Sentry packets are sent in groups of 3, 5s apart. Wait 11s before allowing the loop data to continue to avoid conflicting comms.
        queue.asyncAfter(deadline: .now() + .seconds(11)) {
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
        loopManager.addReservoirValue(units, at: date) { (result) in
            /// TODO: Isolate to queue

            switch result {
            case .failure(let error):
                self.setLastError(error: error)
                self.logger.addError(error, fromSource: "DoseStore")
            case .success(let (newValue, lastValue, areStoredValuesContinuous)):
                // Run a loop as long as we have fresh, reliable pump data.
                if self.preferredInsulinDataSource == .pumpHistory || !areStoredValuesContinuous {
                    self.fetchPumpHistory { (error) in
                        if let error = error {
                            self.setLastError(error: error)
                        }

                        if error == nil || areStoredValuesContinuous {
                            self.loopManager.loop()
                        }
                    }
                } else {
                    self.loopManager.loop()
                }

                // Send notifications for low reservoir if necessary
                if let previousVolume = lastValue?.unitVolume {
                    guard newValue.unitVolume > 0 else {
                        NotificationManager.sendPumpReservoirEmptyNotification()
                        return
                    }

                    let warningThresholds: [Double] = [10, 20, 30]

                    for threshold in warningThresholds {
                        if newValue.unitVolume <= threshold && previousVolume > threshold {
                            NotificationManager.sendPumpReservoirLowNotificationForAmount(newValue.unitVolume, andTimeRemaining: timeLeft)
                        }
                    }

                    if newValue.unitVolume > previousVolume + 1 {
                        AnalyticsManager.shared.reservoirWasRewound()
                    }
                }
            }

            // New reservoir data means we may want to adjust our timer tick requirements
            self.updateTimerTickPreference()
        }
    }

    /// TODO: Isolate to queue
    /// Polls the pump for new history events and passes them to the loop manager
    ///
    /// - Parameters:
    ///   - completion: A closure called once upon completion
    ///   - error: An error describing why the fetch and/or store failed
    private func fetchPumpHistory(_ completion: @escaping (_ error: Error?) -> Void) {
        rileyLinkManager.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                completion(LoopError.connectionError)
                return
            }

            guard let ops = self.pumpOps else {
                completion(LoopError.configurationError("Pump ID"))
                return
            }

            ops.runSession(withName: "Fetch Pump History", using: device) { (session) in
                do {
                    // TODO: This should isn't safe to access synchronously
                    let startDate = self.loopManager.doseStore.pumpEventQueryAfterDate

                    let (events, model) = try session.getHistoryEvents(since: startDate)
                    self.loopManager.addPumpEvents(events, from: model) { (error) in
                        if let error = error {
                            self.logger.addError("Failed to store history: \(error)", fromSource: "DoseStore")
                        }

                        completion(error)
                    }
                } catch let error {
                    self.troubleshootPumpComms(using: device)
                    self.logger.addError("Failed to fetch history: \(error)", fromSource: "RileyLink")

                    completion(error)
                }
            }
        }
    }

    /// TODO: Isolate to queue
    private func isPumpDataStale() -> Bool {
        // How long should we wait before we poll for new pump data?
        let pumpStatusAgeTolerance = rileyLinkManager.idleListeningEnabled ? TimeInterval(minutes: 6) : TimeInterval(minutes: 4)

        return isReservoirDataOlderThan(timeIntervalSinceNow: -pumpStatusAgeTolerance)
    }

    private func isReservoirDataOlderThan(timeIntervalSinceNow: TimeInterval) -> Bool {
        // TODO: lastReservoirValue isn't safe to read from any queue
        var lastReservoirDate = loopManager.doseStore.lastReservoirValue?.startDate ?? .distantPast

        // Look for reservoir data from MySentry that hasn't yet been written (due to 11-second imposed delay)
        if let sentryStatus = latestPumpStatusFromMySentry, let timeZone = pumpState?.timeZone {
            var components = sentryStatus.pumpDateComponents
            components.timeZone = timeZone

            lastReservoirDate = max(components.date ?? .distantPast, lastReservoirDate)
        }

        return lastReservoirDate.timeIntervalSinceNow <= timeIntervalSinceNow
    }

    /**
     Ensures pump data is current by either waking and polling, or ensuring we're listening to sentry packets.
     */
    /// TODO: Isolate to queue
    private func assertCurrentPumpData() {
        rileyLinkManager.assertIdleListening(forcingRestart: true)

        guard isPumpDataStale() else {
            return
        }

        rileyLinkManager.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                let error = LoopError.connectionError
                self.logger.addError("Failed to fetch pump status: \(error)", fromSource: "RileyLink")
                self.setLastError(error: error)
                return
            }

            guard let ops = self.pumpOps else {
                let error = LoopError.configurationError("Pump ID")
                self.setLastError(error: error)
                return
            }

            ops.runSession(withName: "Get Pump Status", using: device) { (session) in
                let nsPumpStatus: NightscoutUploadKit.PumpStatus?
                do {
                    let status = try session.getCurrentPumpStatus()
                    guard let date = status.clock.date else {
                        assertionFailure("Could not interpret a valid date from \(status.clock) in the system calendar")
                        return
                    }

                    // Check if the clock should be reset
                    if abs(date.timeIntervalSinceNow) > .seconds(20) {
                        self.logger.addError("Pump clock is more than 20 seconds off. Resetting.", fromSource: "RileyLink")
                        AnalyticsManager.shared.pumpTimeDidDrift(date.timeIntervalSinceNow)
                        try session.setTime { () -> DateComponents in
                            let calendar = Calendar(identifier: .gregorian)
                            return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
                        }
                    }

                    self.observeBatteryDuring {
                        self.latestPumpStatus = status
                    }

                    self.updateReservoirVolume(status.reservoir, at: date, withTimeLeft: nil)
                    let battery = BatteryStatus(voltage: status.batteryVolts, status: BatteryIndicator(batteryStatus: status.batteryStatus))

                    nsPumpStatus = NightscoutUploadKit.PumpStatus(clock: date, pumpID: status.pumpID, iob: nil, battery: battery, suspended: status.suspended, bolusing: status.bolusing, reservoir: status.reservoir)
                } catch let error {
                    self.logger.addError("Failed to fetch pump status: \(error)", fromSource: "RileyLink")
                    self.setLastError(error: error)
                    self.troubleshootPumpComms(using: device)
                    self.nightscoutDataManager.uploadLoopStatus(loopError: error)
                    nsPumpStatus = nil
                }

                device.getStatus { (status) in
                    self.queue.async {
                        self.nightscoutDataManager.uploadDeviceStatus(nsPumpStatus, rileylinkDevice: status, deviceState: self.deviceStates[device.peripheralIdentifier])
                    }
                }
            }
        }
    }

    /// TODO: Isolate to queue
    /// Send a bolus command and handle the result
    ///
    /// - parameter units:      The number of units to deliver
    /// - parameter completion: A clsure called after the command is complete. This closure takes a single argument:
    ///     - error: An error describing why the command failed
    func enactBolus(units: Double, at startDate: Date = Date(), completion: @escaping (_ error: Error?) -> Void) {
        let notify = { (error: Error?) -> Void in
            if let error = error {
                NotificationManager.sendBolusFailureNotification(for: error, units: units, at: startDate)
            }

            completion(error)
        }

        guard units > 0 else {
            notify(nil)
            return
        }

        guard let ops = pumpOps else {
            notify(LoopError.configurationError("Pump ID"))
            return
        }

        // If we don't have recent pump data, or the pump was recently rewound, read new pump data before bolusing.
        let shouldReadReservoir = isReservoirDataOlderThan(timeIntervalSinceNow: .minutes(-6))

        ops.runSession(withName: "Bolus", using: rileyLinkManager.firstConnectedDevice) { (session) in
            guard let session = session else {
                notify(LoopError.connectionError)
                return
            }

            if shouldReadReservoir {
                do {
                    let reservoir = try session.getRemainingInsulin()

                    self.loopManager.addReservoirValue(reservoir.units, at: reservoir.clock.date!) { (result) in
                        switch result {
                        case .failure(let error):
                            self.logger.addError(error, fromSource: "Bolus")
                        case .success:
                            break
                        }
                    }
                } catch let error as PumpOpsError {
                    self.logger.addError("Failed to fetch pump status: \(error)", fromSource: "RileyLink")
                    notify(SetBolusError.certain(error))
                    return
                } catch let error as PumpCommandError {
                    self.logger.addError("Failed to fetch pump status: \(error)", fromSource: "RileyLink")
                    switch error {
                    case .arguments(let error):
                        notify(SetBolusError.certain(error))
                    case .command(let error):
                        notify(SetBolusError.certain(error))
                    }
                    return
                } catch let error {
                    notify(error)
                    return
                }
            }

            do {
                let semaphore = DispatchSemaphore(value: 0)
                self.loopManager.addRequestedBolus(units: units, at: Date()) {
                    semaphore.signal()
                }
                semaphore.wait()

                try session.setNormalBolus(units: units)
                self.loopManager.addConfirmedBolus(units: units, at: Date()) {
                    notify(nil)
                }
            } catch let error {
                self.logger.addError(error, fromSource: "Bolus")
                notify(error)
            }
        }
    }

    // MARK: - CGM

    var cgm: CGM? = UserDefaults.appGroup.cgm {
        didSet {
            if cgm != oldValue {
                setupCGM()
            }

            UserDefaults.appGroup.cgm = cgm
        }
    }

    private(set) var cgmManager: CGMManager?

    /// TODO: Isolate to queue
    private func setupCGM() {
        cgmManager = cgm?.createManager()
        cgmManager?.delegate = self
        loopManager.glucoseStore.managedDataInterval = cgmManager?.managedDataInterval

        updateTimerTickPreference()
    }

    var sensorInfo: SensorDisplayable? {
        return cgmManager?.sensorState
    }

    // MARK: - Configuration

    // MARK: Pump

    /// TODO: Isolate to queue
    private var connectedPeripheralIDs: Set<String> = Set(UserDefaults.appGroup.connectedPeripheralIDs) {
        didSet {
            UserDefaults.appGroup.connectedPeripheralIDs = Array(connectedPeripheralIDs)
        }
    }

    // TODO: Isolate to queue
    private var deviceStates: [UUID: DeviceState] = [:]

    func getStateForDevice(_ device: RileyLinkDevice, completion: @escaping (_ deviceState: DeviceState, _ pumpState: PumpState?, _ pumpSettings: PumpSettings?, _ pumpOps: PumpOps?) -> Void) {
        queue.async {
            completion(self.deviceStates[device.peripheralIdentifier, default: DeviceState()], self.pumpState, self.pumpSettings, self.pumpOps)
        }
    }

    private(set) var pumpOps: PumpOps? {
        didSet {
            if pumpOps == nil {
                UserDefaults.appGroup.pumpState = nil
            }
        }
    }

    private(set) var pumpSettings: PumpSettings? {
        get {
            return UserDefaults.appGroup.pumpSettings
        }
        set {
            if let settings = newValue {
                if let pumpOps = pumpOps {
                    pumpOps.updateSettings(settings)
                } else {
                    pumpOps = PumpOps(pumpSettings: settings, pumpState: nil, delegate: self)
                }
            } else {
                pumpOps = nil
                loopManager.doseStore.resetPumpData()
            }

            UserDefaults.appGroup.pumpSettings = newValue
        }
    }

    func setPumpID(_ pumpID: String?) {
        var newValue = pumpID

        if newValue?.count != 6 {
            newValue = nil
        }

        if let newValue = newValue {
            if pumpSettings != nil {
                pumpSettings?.pumpID = newValue
            } else {
                pumpSettings = PumpSettings(pumpID: newValue)
            }
        }
    }

    func setPumpRegion(_ pumpRegion: PumpRegion) {
        pumpSettings?.pumpRegion = pumpRegion
    }

    var pumpState: PumpState? {
        return UserDefaults.appGroup.pumpState
    }

    // TODO: Isolate to queue
    /// The user's preferred method of fetching insulin data from the pump
    var preferredInsulinDataSource = UserDefaults.appGroup.preferredInsulinDataSource ?? .pumpHistory {
        didSet {
            UserDefaults.appGroup.preferredInsulinDataSource = preferredInsulinDataSource
        }
    }

    // TODO: Isolate to queue
    /// The pump battery chemistry, for voltage -> percentage calculation
    var batteryChemistry = UserDefaults.appGroup.batteryChemistry ?? .alkaline {
        didSet {
            UserDefaults.appGroup.batteryChemistry = batteryChemistry
        }
    }

    // MARK: - WatchKit

    fileprivate var watchManager: WatchDataManager!

    // MARK: - Status Extension

    fileprivate var statusExtensionManager: StatusExtensionDataManager!

    // MARK: - Initialization

    private(set) var loopManager: LoopDataManager!

    init() {
        rileyLinkManager = RileyLinkDeviceManager(
            autoConnectIDs: connectedPeripheralIDs
        )

        // Pump communication
        var idleListeningEnabled = true

        if let pumpSettings = UserDefaults.appGroup.pumpSettings {
            let pumpState = self.pumpState

            idleListeningEnabled = pumpState?.pumpModel?.hasMySentry ?? true

            self.pumpOps = PumpOps(pumpSettings: pumpSettings, pumpState: pumpState, delegate: self)
        }

        rileyLinkManager.idleListeningState = idleListeningEnabled ? LoopSettings.idleListeningEnabledDefaults : .disabled

        // Listen for device notifications
        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkPacketNotification(_:)), name: .DevicePacketReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(receivedRileyLinkTimerTickNotification(_:)), name: .DeviceTimerDidTick, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceStatusDidChange(_:)), name: .DeviceConnectionStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceStatusDidChange(_:)), name: .DeviceNameDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceStateDidChange(_:)), name: .DeviceStateDidChange, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(deviceStatusDidChange(_:)), name: .ManagerDevicesDidChange, object: rileyLinkManager)

        remoteDataManager.delegate = self
        statusExtensionManager = StatusExtensionDataManager(deviceDataManager: self)
        loopManager = LoopDataManager(
            delegate: self,
            lastLoopCompleted: statusExtensionManager.context?.loop?.lastCompleted,
            lastTempBasal: statusExtensionManager.context?.netBasal?.tempBasal
        )
        watchManager = WatchDataManager(deviceDataManager: self)
        nightscoutDataManager = NightscoutDataManager(deviceDataManager: self)

        loopManager.carbStore.syncDelegate = remoteDataManager.nightscoutService.uploader
        loopManager.doseStore.delegate = self
        // Proliferate PumpModel preferences to DoseStore
        if let pumpModel = pumpState?.pumpModel {
            loopManager.doseStore.pumpRecordsBasalProfileStartEvents = pumpModel.recordsBasalProfileStartEvents
        }

        setupCGM()
    }
}


extension DeviceDataManager: RemoteDataManagerDelegate {
    func remoteDataManagerDidUpdateServices(_ dataManager: RemoteDataManager) {
        loopManager.carbStore.syncDelegate = dataManager.nightscoutService.uploader
    }
}


extension DeviceDataManager: CGMManagerDelegate {
    func cgmManager(_ manager: CGMManager, didUpdateWith result: CGMResult) {
        /// TODO: Isolate to queue
        switch result {
        case .newData(let values):
            loopManager.addGlucose(values, from: manager.device) { _ in
                self.assertCurrentPumpData()
            }
        case .noData:
            self.assertCurrentPumpData()
            break
        case .error(let error):
            self.setLastError(error: error)
            self.assertCurrentPumpData()
        }

        updateTimerTickPreference()
    }

    func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        // TODO: This shouldn't be safe to access synchronously
        return loopManager.glucoseStore.latestGlucose?.startDate
    }
}


extension DeviceDataManager: DoseStoreDelegate {
    func doseStore(_ doseStore: DoseStore,
        hasEventsNeedingUpload pumpEvents: [PersistedPumpEvent],
        completion completionHandler: @escaping (_ uploadedObjects: [NSManagedObjectID]) -> Void
    ) {
        /// TODO: Isolate to queue
        guard let uploader = remoteDataManager.nightscoutService.uploader, let pumpModel = pumpState?.pumpModel else {
            completionHandler(pumpEvents.map({ $0.objectID }))
            return
        }

        uploader.upload(pumpEvents, from: pumpModel) { (result) in
            switch result {
            case .success(let objects):
                completionHandler(objects)
            case .failure(let error):
                let logger = DiagnosticLogger.shared!.forCategory("NightscoutUploader")
                logger.error(error)
                completionHandler([])
            }
        }
    }
}


extension DeviceDataManager: LoopDataManagerDelegate {
    func loopDataManager(
        _ manager: LoopDataManager,
        didRecommendBasalChange basal: (recommendation: TempBasalRecommendation, date: Date),
        completion: @escaping (_ result: Result<DoseEntry>) -> Void
    ) {
        guard let pumpOps = pumpOps else {
            completion(.failure(LoopError.configurationError("Pump ID")))
            return
        }

        pumpOps.runSession(withName: "Set Temp Basal", using: rileyLinkManager.firstConnectedDevice) { (session) in
            guard let session = session else {
                completion(.failure(LoopError.connectionError))
                return
            }

            do {
                let response = try session.setTempBasal(basal.recommendation.unitsPerHour, duration: basal.recommendation.duration)

                let now = Date()
                let endDate = now.addingTimeInterval(response.timeRemaining)
                let startDate = endDate.addingTimeInterval(-basal.recommendation.duration)
                completion(.success(DoseEntry(
                    type: .tempBasal,
                    startDate: startDate,
                    endDate: endDate,
                    value: response.rate,
                    unit: .unitsPerHour
                )))

                // Continue below
            } catch let error {
                completion(.failure(error))
                return
            }

            do {
                // If we haven't fetched history in a while, our preferredInsulinDataSource is probably .reservoir, so
                // let's take advantage of the pump radio being on.
                if self.loopManager.doseStore.lastAddedPumpEvents.timeIntervalSinceNow < .minutes(-4) {
                    let clock = try session.getTime()
                    // Check if the clock should be reset
                    if let date = clock.date, abs(date.timeIntervalSinceNow) > .seconds(20) {
                        self.logger.addError("Pump clock is more than 20 seconds off. Resetting.", fromSource: "RileyLink")
                        AnalyticsManager.shared.pumpTimeDidDrift(date.timeIntervalSinceNow)
                        try session.setTime { () -> DateComponents in
                            let calendar = Calendar(identifier: .gregorian)
                            return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
                        }
                    }

                    self.fetchPumpHistory { (error) in
                        if let error = error {
                            self.logger.addError("Post-basal history fetch failed: \(error)", fromSource: "RileyLink")
                        }
                    }
                }
            } catch let error {
                self.logger.addError("Post-basal time sync failed: \(error)", fromSource: "RileyLink")
            }
        }
    }
}


extension DeviceDataManager: PumpOpsDelegate {
    func pumpOps(_ pumpOps: PumpOps, didChange state: PumpState) {
        if let sentrySupported = pumpState?.pumpModel?.hasMySentry {
            rileyLinkManager.idleListeningState = sentrySupported ? LoopSettings.idleListeningEnabledDefaults : .disabled
        }

        UserDefaults.appGroup.pumpState = state

        // Update the pump-schedule based settings
        loopManager.setScheduleTimeZone(state.timeZone)

        // Update the HKDevice to include the model change
        updateDoseStoreDeviceFromRileyLink(state: state)

        // Update the preference for basal profile start events
        if let recordsBasalProfileStartEvents = state.pumpModel?.recordsBasalProfileStartEvents {
            loopManager.doseStore.pumpRecordsBasalProfileStartEvents = recordsBasalProfileStartEvents
        }
    }
}


extension DeviceDataManager: CustomDebugStringConvertible {
    var debugDescription: String {
        return [
            Bundle.main.localizedNameAndVersion,
            "## DeviceDataManager",
            "launchDate: \(launchDate)",
            "cgm: \(String(describing: cgm))",
            "connectedPeripheralIDs: \(String(reflecting: connectedPeripheralIDs))",
            "deviceStates: \(String(reflecting: deviceStates))",
            "lastError: \(String(describing: lastError))",
            "lastTimerTick: \(String(describing: lastTimerTick))",
            "latestPumpStatus: \(String(describing: latestPumpStatus))",
            "latestPumpStatusFromMySentry: \(String(describing: latestPumpStatusFromMySentry))",
            "pumpBatteryChargeRemaining: \(String(reflecting: pumpBatteryChargeRemaining))",
            "pumpSettings: \(String(reflecting: pumpSettings))",
            "pumpState: \(String(reflecting: pumpState))",
            "preferredInsulinDataSource: \(preferredInsulinDataSource)",
            "sensorInfo: \(String(reflecting: sensorInfo))",
            cgmManager != nil ? String(reflecting: cgmManager!) : "",
            String(reflecting: rileyLinkManager),
            String(reflecting: statusExtensionManager!),
        ].joined(separator: "\n")
    }
}
