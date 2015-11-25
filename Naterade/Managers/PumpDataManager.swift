//
//  PumpDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import MinimedKit
import RileyLinkKit
import WatchConnectivity
import xDripG5

class ConnectDelegate: NSObject, WCSessionDelegate {

}

class PumpDataManager {
    static let PumpStatusUpdatedNotification = "com.loudnate.Naterade.notification.PumpStatusUpdated"

    enum State {
        case NeedsConfiguration
        case Ready(manager: RileyLinkManager)
    }

    // MARK: - Observed state

    lazy var logger = DiagnosticLogger()

    var rileyLinkManager: RileyLinkManager? {
        switch state {
        case .Ready(manager: let manager):
            return manager
        case .NeedsConfiguration:
            return nil
        }
    }

    var rileyLinkManagerObserver: AnyObject? {
        willSet {
            if let observer = rileyLinkManagerObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    var rileyLinkDeviceObserver: AnyObject? {
        willSet {
            if let observer = rileyLinkDeviceObserver {
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
            packet = note.userInfo?[RileyLinkDevicePacketKey] as? MinimedPacket where packet.valid == true,
            let message = PumpMessage(rxData: packet.messageData),
            pumpID = pumpID
        {
            switch message.packetType {
            case .MySentry:
                // Reply to PumpStatus packets with an ACK
                let ack = PumpMessage(packetType: .MySentry, address: pumpID, messageType: .PumpStatusAck, messageBody: MySentryAckMessageBody(mySentryID: [0x00, 0x08, 0x88], responseMessageTypes: [message.messageType]))
                device.sendMessageData(ack.txData)

                switch message.messageBody {
                case let body as MySentryPumpStatusMessageBody:
                    updatePumpStatus(body, fromDevice: device)
                case let body as MySentryAlertMessageBody:
                    // TODO: de-dupe
                    logger?.addMessage(body, toCollection: "sentryAlert")
                case let body as MySentryAlertClearedMessageBody:
                    // TODO: de-dupe
                    logger?.addMessage(body, toCollection: "sentryAlert")
                case let body as UnknownMessageBody:
                    logger?.addMessage(body, toCollection: "sentryOther")
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

        rileyLinkManager?.connectDevice(device)
    }

    func disconnectFromRileyLink(device: RileyLinkDevice) {
        connectedPeripheralIDs.remove(device.peripheral.identifier.UUIDString)

        rileyLinkManager?.disconnectDevice(device)
    }

    // MARK: - Managed state

    private func updatePumpStatus(status: MySentryPumpStatusMessageBody, fromDevice device: RileyLinkDevice) {
        if status != latestPumpStatus {
            latestPumpStatus = status

            logger?.addMessage(status, toCollection: "sentryMessage")

            if let date = status.glucoseDate {
                switch status.glucose {
                case .Active(glucose: let value):
                    let quantityType = HKQuantityType.quantityTypeForIdentifier(HKQuantityTypeIdentifierBloodGlucose)!
                    let quantity = HKQuantity(unit: HKUnit(fromString: "mg/dL"), doubleValue: Double(value))

                    let sample = HKQuantitySample(
                        type: quantityType,
                        quantity: quantity,
                        startDate: date,
                        endDate: date,
                        device: HKDevice(rileyLinkDevice: device),
                        metadata: [
                            HKMetadataKeyWasUserEntered: false
                        ]
                    )

                    if let store = healthStore where store.authorizationStatusForType(glucoseQuantityType) == .SharingAuthorized {
                        store.saveObject(sample, withCompletion: { (success, error) -> Void in
                            if let error = error {
                                NSLog("Error saving glucose sample: %@", error)
                            }
                        })
                    }
                default:
                    break
                }
            }

            // Send data to watch
            if let session = watchSession where session.paired && session.watchAppInstalled {
                if !session.complicationEnabled {
                    do {
                        let context = ["statusData": status.txData]
                        try session.updateApplicationContext(context)
                    } catch let error as NSError {
                        NSLog("Error calling updateApplicationContext: %@", error)
                    }
                }
            }
        }
    }

    var latestPumpStatus: MySentryPumpStatusMessageBody? {
        didSet {
            NSNotificationCenter.defaultCenter().postNotificationName(self.dynamicType.PumpStatusUpdatedNotification, object: self)
        }
    }

    var state: State = .NeedsConfiguration {
        willSet {
            switch newValue {
            case .Ready(manager: let manager):
                rileyLinkManagerObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: manager, queue: nil) { [weak self = self] (note) -> Void in
                    self?.receivedRileyLinkManagerNotification(note)
                }

                rileyLinkDeviceObserver = NSNotificationCenter.defaultCenter().addObserverForName(RileyLinkDeviceDidReceivePacketNotification, object: nil, queue: nil, usingBlock: { [weak self = self] (note) -> Void in
                    self?.receivedRileyLinkPacketNotification(note)
                })

            case .NeedsConfiguration:
                rileyLinkManagerObserver = nil
                rileyLinkDeviceObserver = nil
            }
        }
    }

    var connectedPeripheralIDs: Set<String> {
        didSet {
            NSUserDefaults.standardUserDefaults().connectedPeripheralIDs = Array(connectedPeripheralIDs)
        }
    }

    var pumpID: String? {
        didSet {
            if pumpID?.characters.count != 6 {
                pumpID = nil
            }

            switch state {
            case .NeedsConfiguration where pumpID != nil:
                state = .Ready(manager: RileyLinkManager(pumpID: pumpID!, autoconnectIDs: connectedPeripheralIDs))
            case .Ready(manager: _) where pumpID == nil:
                state = .NeedsConfiguration
            case .NeedsConfiguration, .Ready:
                break
            }

            NSUserDefaults.standardUserDefaults().pumpID = pumpID
        }
    }

    var transmitterID: String? {
        didSet {
            if transmitterID?.characters.count != 6 {
                transmitterID = nil
            }

            NSUserDefaults.standardUserDefaults().transmitterID = transmitterID
        }
    }

    // MARK: - HealthKit

    lazy var glucoseQuantityType = HKSampleType.quantityTypeForIdentifier(HKQuantityTypeIdentifierBloodGlucose)!

    lazy var healthStore: HKHealthStore? = {
        if HKHealthStore.isHealthDataAvailable() {
            let store = HKHealthStore()
            let shareTypes = Set(arrayLiteral: self.glucoseQuantityType)

            store.requestAuthorizationToShareTypes(shareTypes, readTypes: nil, completion: { (completed, error) -> Void in
                if let error = error {
                    NSLog("Failed to gain HealthKit authorization: %@", error)
                }
            })

            return store
        } else {
            NSLog("Health data is not available on this device")
            return nil
        }
    }()

    // MARK: - WatchKit

    lazy var watchSessionDelegate = ConnectDelegate()

    lazy var watchSession: WCSession? = {
        if WCSession.isSupported() {
            let session = WCSession.defaultSession()
            session.delegate = self.watchSessionDelegate
            session.activateSession()

            return session
        } else {
            return nil
        }
    }()

    // MARK: - Initialization

    static let sharedManager = PumpDataManager()

    init() {
        connectedPeripheralIDs = Set(NSUserDefaults.standardUserDefaults().connectedPeripheralIDs)
    }

    deinit {
        rileyLinkManagerObserver = nil
        rileyLinkDeviceObserver = nil
    }
}