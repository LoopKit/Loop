//
//  BluetoothStateManager.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2020-07-03.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import LoopKit
import LoopKitUI

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
                
        var action: HUDTapAction? {
            switch self {
            case .unauthorized, .denied:
                return .openAppURL(URL(string: UIApplication.openSettingsURLString)!)
            case .poweredOff:
                return .takeNoAction
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
        var imageName: String = "bluetooth.disabled"
        var state: DeviceStatusHighlightState = .critical
        
        init(localizedMessage: String) {
            self.localizedMessage = localizedMessage
        }
    }
    
    public static var bluetoothOffHighlight: DeviceStatusHighlight {
        return BluetoothStateHighlight(localizedMessage: NSLocalizedString("Bluetooth\nOff", comment: "Message to the user to that the bluetooth is off"))
    }
    
    public static var bluetoothEnableHighlight: DeviceStatusHighlight {
        return BluetoothStateHighlight(localizedMessage: NSLocalizedString("Enable\nBluetooth", comment: "Message to the user to enable bluetooth"))
    }
    
    public static var bluetoothUnavailableHighlight: DeviceStatusHighlight {
        return BluetoothStateHighlight(localizedMessage: NSLocalizedString("Bluetooth\nUnavailable", comment: "Message to the user that bluetooth is unavailable to the app"))
    }
}
