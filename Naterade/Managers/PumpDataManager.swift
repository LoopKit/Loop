//
//  PumpDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import RileyLinkKit

class PumpDataManager {
    enum State {
        case NeedsConfiguration
        case Ready(manager: RileyLinkManager)
    }

    // Observed state

    var rileyLinkManager: RileyLinkManager? {
        switch state {
        case .Ready(manager: let manager):
            return manager
        case .NeedsConfiguration:
            return nil
        }
    }

    var rileyLinkObserver: AnyObject? {
        willSet {
            if let observer = rileyLinkObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    func receivedRileyLinkManagerNotification(note: NSNotification) {
        NSNotificationCenter.defaultCenter().postNotificationName(note.name, object: self, userInfo: note.userInfo)
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

    var state: State = .NeedsConfiguration {
        willSet {
            switch newValue {
            case .Ready(manager: let manager):
                rileyLinkObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: manager, queue: nil) { [weak self = self] (note) -> Void in
                    self?.receivedRileyLinkManagerNotification(note)
                }

            case .NeedsConfiguration:
                rileyLinkObserver = nil
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

    static let sharedManager = PumpDataManager()

    init() {
        connectedPeripheralIDs = Set(NSUserDefaults.standardUserDefaults().connectedPeripheralIDs)
    }

    deinit {
        rileyLinkObserver = nil  // iOS 8 only
    }
}