//
//  DeviceDataManager+DeviceStatus.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2020-07-10.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import LoopCore

extension DeviceDataManager {
    var cgmStatusHighlight: DeviceStatusHighlight? {
        if bluetoothState == .poweredOff {
            return BluetoothStateManager.bluetoothOffHighlight
        } else if bluetoothState == .denied ||
            bluetoothState == .unauthorized
        {
            return BluetoothStateManager.bluetoothUnavailableHighlight
        } else if cgmManager == nil {
            return DeviceDataManager.addCGMStatusHighlight
        } else {
            return (cgmManager as? CGMManagerUI)?.cgmStatusHighlight
        }
    }
    
    var cgmLifecycleProgress: DeviceLifecycleProgress? {
        return (cgmManager as? CGMManagerUI)?.cgmLifecycleProgress
    }
    
    var pumpStatusHighlight: DeviceStatusHighlight? {
        if bluetoothState == .denied ||
            bluetoothState == .unauthorized ||
            bluetoothState == .poweredOff
        {
            return BluetoothStateManager.bluetoothEnableHighlight
        } else if pumpManager == nil {
            return DeviceDataManager.addPumpStatusHighlight
        } else {
            return pumpManagerStatus?.pumpStatusHighlight
        }
    }
    
    var pumpLifecycleProgress: DeviceLifecycleProgress? {
        return pumpManagerStatus?.pumpLifecycleProgress
    }
    
    static var addCGMStatusHighlight: AddDeviceStatusHighlight {
        return AddDeviceStatusHighlight(localizedMessage: NSLocalizedString("Add CGM", comment: "Title text for button to set up a CGM"),
                                        state: .critical)
    }
    
    static var addPumpStatusHighlight: AddDeviceStatusHighlight {
        return AddDeviceStatusHighlight(localizedMessage: NSLocalizedString("Add Pump", comment: "Title text for button to set up a Pump"),
                                        state: .critical)
    }
    
    struct AddDeviceStatusHighlight: DeviceStatusHighlight {
        var localizedMessage: String
        var imageName: String = "plus.circle"
        var state: DeviceStatusHighlightState
    }
    
    func didTapOnCGMStatus(_ view: BaseHUDView? = nil) -> HUDTapAction? {
        if let action = bluetoothState.action {
            return action
        } else if let url = cgmManager?.appURL,
            UIApplication.shared.canOpenURL(url)
        {
            return .openAppURL(url)
        } else if let cgmManagerUI = (cgmManager as? CGMManagerUI),
            let unit = glucoseStore.preferredUnit
        {
            return .presentViewController(cgmManagerUI.settingsViewController(for: unit, glucoseTintColor: .glucoseTintColor, guidanceColors: .default))
        } else {
            return .setupNewCGM
        }
    }
    
    func didTapOnPumpStatus(_ view: BaseHUDView? = nil) -> HUDTapAction? {
        if let action = bluetoothState.action {
            return action
        } else if let pumpManagerHUDProvider = pumpManagerHUDProvider,
            let view = view,
            let action = pumpManagerHUDProvider.didTapOnHUDView(view)
        {
            return action
        } else if let pumpManager = pumpManager {
            return .presentViewController(pumpManager.settingsViewController(insulinTintColor: .insulinTintColor, guidanceColors: .default, allowedInsulinTypes: allowedInsulinTypes))
        } else {
            return .setupNewPump
        }
    }
    
    var isGlucoseValueStale: Bool {
        guard let latestGlucoseDataDate = glucoseStore.latestGlucose?.startDate else { return true }

        return Date().timeIntervalSince(latestGlucoseDataDate) > LoopCoreConstants.inputDataRecencyInterval
    }
}

