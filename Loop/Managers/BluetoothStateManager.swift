//
//  BluetoothStateManager.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2020-07-03.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import LoopKit

public protocol BluetoothStateManagerObserver: class {
    func bluetoothStateManager(_ bluetoothStateManager: BluetoothStateManager, bluetoothStateDidUpdate bluetoothState: BluetoothStateManager.BluetoothState)
}

public class BluetoothStateManager: NSObject {

    public enum BluetoothState {
        case poweredOn
        case poweredOff
        case unauthorized
        case denied
        case other
        
        var statusHighlight: DeviceStatusHighlight? {
            switch self {
            case .poweredOff:
                return BluetoothStateManager.bluetoothStateOffHighlight
            case .unauthorized, .denied:
                return BluetoothStateManager.bluetoothStateUnauthorizedHighlight
            default:
                return nil
            }
        }
        
        var action: (() -> Void)? {
            switch self {
            case .unauthorized, .denied:
                return { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
            case .poweredOff:
                return { }
            default:
                return nil
            }
        }
    }
    
    private var bluetoothCentralManager: CBCentralManager!
    
    private var bluetoothState: BluetoothState = .other
    
    private var bluetoothStateObservers = WeakSynchronizedSet<BluetoothStateManagerObserver>()
    
    override init() {
        super.init()
        bluetoothCentralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    public func addBluetoothStateObserver(_ observer: BluetoothStateManagerObserver,
                                     queue: DispatchQueue = .main)
    {
        bluetoothStateObservers.insert(observer, queue: queue)
    }
    
    public func removeBluetoothStateObserver(_ observer: BluetoothStateManagerObserver) {
        bluetoothStateObservers.removeElement(observer)
    }
}

// MARK: CBCentralManagerDelegate implementation

extension BluetoothStateManager: CBCentralManagerDelegate {
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unauthorized:
            bluetoothState = .unauthorized
            switch central.authorization {
            case .denied:
                bluetoothState = .denied
            default:
                break
            }
        case .poweredOn:
            bluetoothState = .poweredOn
        case .poweredOff:
            bluetoothState = .poweredOff
        default:
            bluetoothState = .other
            break
        }
        bluetoothStateObservers.forEach { $0.bluetoothStateManager(self, bluetoothStateDidUpdate: self.bluetoothState) }
    }
}

// MARK: - Bluetooth Status Highlight

extension BluetoothStateManager {
    struct BluetoothStateHighlight: DeviceStatusHighlight {
        var localizedMessage: String
        //TODO need correct icon from design
        var imageSystemName: String = "wifi.slash"
        var state: DeviceStatusHighlightState = .critical
        
        init(localizedMessage: String) {
            self.localizedMessage = localizedMessage
        }
    }
    
    public static var bluetoothStateOffHighlight: DeviceStatusHighlight {
        return BluetoothStateHighlight(localizedMessage: NSLocalizedString("Enable Bluetooth", comment: "Message to the user to enable bluetooth"))
    }
    
    public static var bluetoothStateUnauthorizedHighlight: DeviceStatusHighlight {
        return BluetoothStateHighlight(localizedMessage: NSLocalizedString("Allow Bluetooth", comment: "Message to the user to allow bluetooth"))
    }
}
