//
//  DexCGMManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import G4ShareSpy
import HealthKit
import LoopKit
import ShareClient
import CGMBLEKit


class DexCGMManager: CGMManager {
    var providesBLEHeartbeat: Bool {
        return false
    }

    let shouldSyncToRemoteService = false

    weak var cgmManagerDelegate: CGMManagerDelegate? {
        didSet {
            shareManager?.cgmManagerDelegate = cgmManagerDelegate
        }
    }

    func fetchNewDataIfNeeded(_ completion: @escaping (CGMResult) -> Void) {
        guard let shareManager = shareManager else {
            completion(.noData)
            return
        }

        shareManager.fetchNewDataIfNeeded(completion)
    }

    var sensorState: SensorDisplayable? {
        return shareManager?.sensorState
    }

    var managedDataInterval: TimeInterval? {
        return shareManager?.managedDataInterval
    }

    fileprivate var shareManager: ShareClientManager? = ShareClientManager()

    var device: HKDevice? {
        return nil
    }

    var debugDescription: String {
        return [
            "## DexCGMManager",
            "shareManager: \(String(reflecting: shareManager))",
            ""
        ].joined(separator: "\n")
    }
}


final class ShareClientManager: CGMManager {
    weak var cgmManagerDelegate: CGMManagerDelegate?

    let providesBLEHeartbeat = false

    let shouldSyncToRemoteService = false

    var sensorState: SensorDisplayable? {
        return latestBackfill
    }

    let managedDataInterval: TimeInterval? = nil

    fileprivate var latestBackfill: ShareGlucose?

    func fetchNewDataIfNeeded(_ completion: @escaping (CGMResult) -> Void) {
        guard let shareClient = RemoteDataManager().shareService.client else {
            completion(.noData)
            return
        }

        // If our last glucose was less than 4.5 minutes ago, don't fetch.
        if let latestGlucose = latestBackfill, latestGlucose.startDate.timeIntervalSinceNow > -TimeInterval(minutes: 4.5) {
            completion(.noData)
            return
        }

        shareClient.fetchLast(6) { (error, glucose) in
            if let error = error {
                completion(.error(error))
                return
            }
            guard let glucose = glucose else {
                completion(.noData)
                return
            }

            // Ignore glucose values that are up to a minute newer than our previous value, to account for possible time shifting in Share data
            let startDate = self.cgmManagerDelegate?.startDateToFilterNewData(for: self)?.addingTimeInterval(TimeInterval(minutes: 1))
            let newGlucose = glucose.filterDateRange(startDate, nil).filter({ $0.isStateValid }).map {
                return NewGlucoseSample(date: $0.startDate, quantity: $0.quantity, isDisplayOnly: false, syncIdentifier: "\($0.startDate.timeIntervalSince1970)", device: self.device)
            }

            self.latestBackfill = glucose.first

            completion(.newData(newGlucose))
        }
    }

    var device: HKDevice? = nil

    var debugDescription: String {
        return [
            "## ShareClientManager",
            "latestBackfill: \(String(describing: latestBackfill))",
            ""
        ].joined(separator: "\n")
    }
}


final class G5CGMManager: DexCGMManager, TransmitterDelegate {
    private let transmitter: Transmitter?
    let logger = DiagnosticLogger.shared.forCategory("G5CGMManager")

    init(transmitterID: String?) {
        if let transmitterID = transmitterID {
            self.transmitter = Transmitter(id: transmitterID, passiveModeEnabled: true)
        } else {
            self.transmitter = nil
        }

        super.init()

        self.transmitter?.delegate = self
    }

    override var providesBLEHeartbeat: Bool {
        return transmitter != nil && dataIsFresh
    }

    override var sensorState: SensorDisplayable? {
        let transmitterDate = latestReading?.readDate ?? .distantPast
        let shareDate = shareManager?.latestBackfill?.startDate ?? .distantPast

        if transmitterDate > shareDate {
            return latestReading
        } else {
            return super.sensorState
        }
    }

    override var managedDataInterval: TimeInterval? {
        if let transmitter = transmitter, transmitter.passiveModeEnabled {
            return .hours(3)
        }

        return super.managedDataInterval
    }

    private var latestReading: Glucose?

    private var dataIsFresh: Bool {
        guard let latestGlucose = latestReading,
            latestGlucose.readDate > Date(timeIntervalSinceNow: .minutes(-4.5)) else {
            return false
        }

        return true
    }

    override func fetchNewDataIfNeeded(_ completion: @escaping (CGMResult) -> Void) {
        // If our last glucose was less than 4.5 minutes ago, don't fetch.
        guard !dataIsFresh else {
            completion(.noData)
            return
        }

        super.fetchNewDataIfNeeded(completion)
    }

    override var device: HKDevice? {
        return HKDevice(
            name: "CGMBLEKit",
            manufacturer: "Dexcom",
            model: "G5/G6 Mobile",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: String(CGMBLEKitVersionNumber),
            localIdentifier: nil,
            udiDeviceIdentifier: "00386270000002"
        )
    }

    override var debugDescription: String {
        return [
            "## G5CGMManager",
            "latestReading: \(String(describing: latestReading))",
            "transmitter: \(String(describing: transmitter))",
            "providesBLEHeartbeat: \(providesBLEHeartbeat)",
            super.debugDescription,
            ""
        ].joined(separator: "\n")
    }

    // MARK: - TransmitterDelegate

    func transmitter(_ transmitter: Transmitter, didError error: Error) {
        logger.error(error)
        cgmManagerDelegate?.cgmManager(self, didUpdateWith: .error(error))
    }

    func transmitter(_ transmitter: Transmitter, didRead glucose: Glucose) {
        guard glucose != latestReading else {
            cgmManagerDelegate?.cgmManager(self, didUpdateWith: .noData)
            return
        }

        latestReading = glucose

        guard glucose.state.hasReliableGlucose else {
            logger.error(String(describing: glucose.state))
            cgmManagerDelegate?.cgmManager(self, didUpdateWith: .error(CalibrationError.unreliableState(glucose.state)))
            return
        }
        
        guard let quantity = glucose.glucose else {
            cgmManagerDelegate?.cgmManager(self, didUpdateWith: .noData)
            return
        }

        cgmManagerDelegate?.cgmManager(self, didUpdateWith: .newData([
            NewGlucoseSample(
                date: glucose.readDate,
                quantity: quantity,
                isDisplayOnly: glucose.isDisplayOnly,
                syncIdentifier: glucose.syncIdentifier,
                device: device
            )
        ]))
    }

    func transmitter(_ transmitter: Transmitter, didReadBackfill glucose: [Glucose]) {
        let samples = glucose.compactMap { (glucose) -> NewGlucoseSample? in
            guard glucose != latestReading, glucose.state.hasReliableGlucose, let quantity = glucose.glucose else {
                return nil
            }

            return NewGlucoseSample(
                date: glucose.readDate,
                quantity: quantity,
                isDisplayOnly: glucose.isDisplayOnly,
                syncIdentifier: glucose.syncIdentifier,
                device: device
            )
        }

        guard samples.count > 0 else {
            return
        }

        cgmManagerDelegate?.cgmManager(self, didUpdateWith: .newData(samples))
    }

    func transmitter(_ transmitter: Transmitter, didReadUnknownData data: Data) {
        logger.error("Unknown sensor data: " + data.hexadecimalString)
        // This can be used for protocol discovery, but isn't necessary for normal operation
    }
}


final class G4CGMManager: DexCGMManager, ReceiverDelegate {
    private let receiver = Receiver()

    override init() {
        super.init()

        receiver.delegate = self
    }

    override var providesBLEHeartbeat: Bool {
        return dataIsFresh
    }

    override var sensorState: SensorDisplayable? {
        return latestReading ?? super.sensorState
    }

    override var managedDataInterval: TimeInterval? {
        return .hours(3)
    }

    private var latestReading: GlucoseG4?

    private var dataIsFresh: Bool {
        guard let latestGlucose = latestReading,
            latestGlucose.startDate > Date(timeIntervalSinceNow: .minutes(-4.5)) else {
                return false
        }

        return true
    }

    override func fetchNewDataIfNeeded(_ completion: @escaping (CGMResult) -> Void) {
        // If our last glucose was less than 4.5 minutes ago, don't fetch.
        guard !dataIsFresh else {
            completion(.noData)
            return
        }

        super.fetchNewDataIfNeeded(completion)
    }

    override var device: HKDevice? {
        // "Dexcom G4 Platinum Transmitter (Retail) US" - see https://accessgudid.nlm.nih.gov/devices/search?query=dexcom+g4
        return HKDevice(
            name: "G4ShareSpy",
            manufacturer: "Dexcom",
            model: "G4 Share",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: String(G4ShareSpyVersionNumber),
            localIdentifier: nil,
            udiDeviceIdentifier: "40386270000048"
        )
    }

    override var debugDescription: String {
        return [
            "## G4CGMManager",
            "latestReading: \(String(describing: latestReading))",
            "receiver: \(receiver)",
            "providesBLEHeartbeat: \(providesBLEHeartbeat)",
            super.debugDescription,
            ""
        ].joined(separator: "\n")
    }

    // MARK: - ReceiverDelegate

    func receiver(_ receiver: Receiver, didReadGlucoseHistory glucoseHistory: [GlucoseG4]) {
        guard let latest = glucoseHistory.sorted(by: { $0.sequence < $1.sequence }).last, latest != latestReading else {
            return
        }
        latestReading = latest

        // In the event that some of the glucose history was already backfilled from Share, don't overwrite it.
        let includeAfter = cgmManagerDelegate?.startDateToFilterNewData(for: self)?.addingTimeInterval(TimeInterval(minutes: 1))

        let validGlucose = glucoseHistory.filter({
            $0.isStateValid
        }).filterDateRange(includeAfter, nil).map({
            NewGlucoseSample(date: $0.startDate, quantity: $0.quantity, isDisplayOnly: $0.isDisplayOnly, syncIdentifier: String(describing: $0.sequence), device: self.device)
        })

        self.cgmManagerDelegate?.cgmManager(self, didUpdateWith: .newData(validGlucose))
    }

    func receiver(_ receiver: Receiver, didError error: Error) {
        cgmManagerDelegate?.cgmManager(self, didUpdateWith: .error(error))
    }

    func receiver(_ receiver: Receiver, didLogBluetoothEvent event: String) {
        // Uncomment to debug communication
        // NSLog("\(#function): \(event)")
    }
}

enum CalibrationError: Error {
    case unreliableState(CalibrationState)
}

extension CalibrationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreliableState:
            return NSLocalizedString("Glucose data is unavailable", comment: "Error description for unreliable state")
        }
    }

    var failureReason: String? {
        switch self {
        case .unreliableState(let state):
            return state.localizedDescription
        }
    }
}

extension CalibrationState {
    public var localizedDescription: String {
        switch self {
        case .known(let state):
            switch state {
            case .needCalibration7, .needCalibration14, .needFirstInitialCalibration, .needSecondInitialCalibration, .calibrationError8, .calibrationError9, .calibrationError10, .calibrationError13:
                return NSLocalizedString("Sensor needs calibration", comment: "The description of sensor calibration state when sensor needs calibration.")
            case .ok:
                return NSLocalizedString("Sensor calibration is OK", comment: "The description of sensor calibration state when sensor calibration is ok.")
            case .stopped, .sensorFailure11, .sensorFailure12, .sessionFailure15, .sessionFailure16, .sessionFailure17:
                return NSLocalizedString("Sensor is stopped", comment: "The description of sensor calibration state when sensor sensor is stopped.")
            case .warmup, .questionMarks:
                return NSLocalizedString("Sensor is warming up", comment: "The description of sensor calibration state when sensor sensor is warming up.")
            }
        case .unknown(let rawValue):
            return String(format: NSLocalizedString("Sensor is in unknown state %1$d", comment: "The description of sensor calibration state when raw value is unknown. (1: missing data details)"), rawValue)
        }
    }
}
