//
//  DexCGMManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import G4ShareSpy
import HealthKit
import LoopUI
import ShareClient
import xDripG5


class DexCGMManager: CGMManager {
    var providesBLEHeartbeat: Bool = true

    weak var delegate: CGMManagerDelegate? {
        didSet {
            shareManager?.delegate = delegate
        }
    }

    func fetchNewDataIfNeeded(with deviceManager: DeviceDataManager, _ completion: @escaping (CGMResult) -> Void) {
        guard let shareManager = shareManager else {
            completion(.noData)
            return
        }

        shareManager.fetchNewDataIfNeeded(with: deviceManager, completion)
    }

    var sensorState: SensorDisplayable? {
        return shareManager?.sensorState
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
    weak var delegate: CGMManagerDelegate?

    var providesBLEHeartbeat = false

    var sensorState: SensorDisplayable? {
        return latestBackfill
    }

    private var latestBackfill: ShareGlucose?

    func fetchNewDataIfNeeded(with deviceManager: DeviceDataManager, _ completion: @escaping (CGMResult) -> Void) {
        guard let shareClient = deviceManager.remoteDataManager.shareService.client else {
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
            let startDate = self.delegate?.startDateToFilterNewData(for: self)?.addingTimeInterval(TimeInterval(minutes: 1))
            let newGlucose = glucose.filterDateRange(startDate, nil).map {
                return (quantity: $0.quantity, date: $0.startDate, isDisplayOnly: false)
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

    init(transmitterID: String?) {
        if let transmitterID = transmitterID {
            self.transmitter = Transmitter(ID: transmitterID, passiveModeEnabled: true)
        } else {
            self.transmitter = nil
        }

        super.init()

        self.providesBLEHeartbeat = self.transmitter != nil

        self.transmitter?.delegate = self
    }

    override var sensorState: SensorDisplayable? {
        return latestReading ?? super.sensorState
    }

    private var latestReading: Glucose? {
        didSet {
            // Once we have our first reading, disable backfill
            shareManager = nil
        }
    }

    override var device: HKDevice? {
        return HKDevice(
            name: "xDripG5",
            manufacturer: "Dexcom",
            model: "G5 Mobile",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: String(xDripG5VersionNumber),
            localIdentifier: nil,
            udiDeviceIdentifier: "00386270000002"
        )
    }

    override var debugDescription: String {
        return [
            "## G5CGMManager",
            "latestReading: \(String(describing: latestReading))",
            "transmitter: \(String(describing: transmitter))",
            super.debugDescription,
            ""
        ].joined(separator: "\n")
    }

    // MARK: - TransmitterDelegate

    func transmitter(_ transmitter: Transmitter, didError error: Error) {
        delegate?.cgmManager(self, didUpdateWith: .error(error))
    }

    func transmitter(_ transmitter: Transmitter, didRead glucose: Glucose) {
        guard glucose != latestReading, let quantity = glucose.glucose else {
            delegate?.cgmManager(self, didUpdateWith: .noData)
            return
        }
        latestReading = glucose

        self.delegate?.cgmManager(self, didUpdateWith: .newData([
            (quantity: quantity, date: glucose.readDate, isDisplayOnly: glucose.isDisplayOnly)
            ]))
    }

    func transmitter(_ transmitter: Transmitter, didReadUnknownData data: Data) {
        // This can be used for protocol discovery, but isn't necessary for normal operation
    }
}


final class G4CGMManager: DexCGMManager, ReceiverDelegate {
    private let receiver = Receiver()

    override init() {
        super.init()

        receiver.delegate = self
    }

    override var sensorState: SensorDisplayable? {
        return latestReading ?? super.sensorState
    }

    private var latestReading: GlucoseG4? {
        didSet {
            // Once we have our first reading, disable backfill
            shareManager = nil
        }
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
        let includeAfter = delegate?.startDateToFilterNewData(for: self)?.addingTimeInterval(TimeInterval(minutes: 1))

        let validGlucose = glucoseHistory.filter({
            $0.isStateValid
        }).filterDateRange(includeAfter, nil).map({
            (quantity: $0.quantity, date: $0.startDate, isDisplayOnly: $0.isDisplayOnly)
        })

        self.delegate?.cgmManager(self, didUpdateWith: .newData(validGlucose))
    }

    func receiver(_ receiver: Receiver, didError error: Error) {
        delegate?.cgmManager(self, didUpdateWith: .error(error))
    }

    func receiver(_ receiver: Receiver, didLogBluetoothEvent event: String) {
        // Uncomment to debug communication
        // NSLog(["event": "\(event)", "collectedAt": NSDateFormatter.ISO8601StrictDateFormatter().stringFromDate(NSDate())])
    }
}
