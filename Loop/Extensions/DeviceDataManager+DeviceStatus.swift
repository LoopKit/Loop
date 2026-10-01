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
    var hasBluetoothIssue: Bool {
        bluetoothProvider.bluetoothState == .poweredOff || bluetoothProvider.bluetoothState == .unauthorized || bluetoothProvider.bluetoothState == .unsupported
    }
    
    var cgmStatusHighlight: DeviceStatusHighlight? {
        let bluetoothState = bluetoothProvider.bluetoothState
        if bluetoothState == .unsupported || bluetoothState == .unauthorized {
            return BluetoothState.unavailableHighlight
        } else if bluetoothState == .poweredOff {
            return BluetoothState.offHighlight
        } else if cgmManager == nil {
            return DeviceDataManager.addCGMStatusHighlight
        } else {
            return (cgmManager as? CGMManagerUI)?.cgmStatusHighlight
        }
    }
    
    var cgmStatusBadge: DeviceStatusBadge? {
        return (cgmManager as? CGMManagerUI)?.cgmStatusBadge
    }
    
    var cgmLifecycleProgress: DeviceLifecycleProgress? {
        return (cgmManager as? CGMManagerUI)?.cgmLifecycleProgress
    }

    var pumpStatusHighlight: DeviceStatusHighlight? {
        let bluetoothState = bluetoothProvider.bluetoothState
        if bluetoothState == .unsupported || bluetoothState == .unauthorized || bluetoothState == .poweredOff {
            return BluetoothState.enableHighlight
        } else if let onboardingManager = onboardingManager, !onboardingManager.isComplete, pumpManager?.isOnboarded != true {
            return DeviceDataManager.resumeOnboardingStatusHighlight
        } else if pumpManager == nil {
            return DeviceDataManager.addPumpStatusHighlight
        } else if isPodLoanReclaiming {
            // Hand-back in flight — records draining and the radio re-arming take a few seconds;
            // show movement, not a frozen "on watch", which reads as ownership ambiguity.
            //
            // The label follows the reclaim's phase, because "Reclaiming…" over a watch that is
            // not answering implies progress that is not happening. The dead branch says the
            // watch is silent from the first second, which is the whole point of deciding the
            // branch before the wait starts rather than after it.
            //
            return DeviceDataManager.podReclaimingStatusHighlight(phase: podReclaimProgress?.phase)
        } else if isPodTakeoverInProgress {
            // The grant is out but the watch has NOT confirmed it has the pod. This branch MUST
            // precede the one below: the grant releases the pod's BLE immediately, so
            // `isConnectionReleased` is already true here and would otherwise claim "Pod on
            // Watch" for a handover still in flight.
            //
            // ONE label for the whole window, by ruling (2026-08-23). A two-stage pill
            // ("Handing over…" -> "Released — waiting for Watch…") shipped in 1087 and was
            // reverted the same day: the stall it addressed was the OLD 5-6 s frozen window,
            // and once takeovers dropped to ~5 s the stage-two label was clutter narrating a
            // wait too short to read. If the window ever grows long again, fix the speed, not
            // the copy.
            return DeviceDataManager.podHandingOverStatusHighlight
        } else if (pumpManager as? PumpConnectionLendable)?.isConnectionReleased == true || isPodLoanedToWatch {
            // While the pod is loaned to the watch, keying on the persisted release flag flips
            // this tile the MOMENT of release/reclaim — instead of the stock signal-loss
            // presentation aging in ~8 min later, which reads as a fault.
            return DeviceDataManager.podOnWatchStatusHighlight
        } else {
            return (pumpManager as? PumpManagerUI)?.pumpStatusHighlight
        }
    }

    var pumpStatusBadge: DeviceStatusBadge? {
        return (pumpManager as? PumpManagerUI)?.pumpStatusBadge
    }

    var pumpLifecycleProgress: DeviceLifecycleProgress? {
        if let podLoanProgress = podLoanLifecycleProgress { return podLoanProgress }
        return (pumpManager as? PumpManagerUI)?.pumpLifecycleProgress
    }
    
    static var resumeOnboardingStatusHighlight: ResumeOnboardingStatusHighlight {
        return ResumeOnboardingStatusHighlight()
    }

    struct ResumeOnboardingStatusHighlight: DeviceStatusHighlight {
        var localizedMessage: String = NSLocalizedString("Complete Setup", comment: "Title text for button to complete setup")
        var imageName: String = "exclamationmark.circle.fill"
        var state: DeviceStatusHighlightState = .warning
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
        if let action = bluetoothProvider.bluetoothState.action {
            return action
        } else if let url = cgmManager?.appURL,
            UIApplication.shared.canOpenURL(url)
        {
            return .openAppURL(url)
        } else if let cgmManagerUI = (cgmManager as? CGMManagerUI) {
            return .presentViewController(cgmManagerUI.settingsViewController(bluetoothProvider: bluetoothProvider, displayGlucosePreference: displayGlucosePreference, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures))
        } else {
            return .setupNewCGM
        }
    }
    
    func didTapOnPumpStatus(_ view: BaseHUDView? = nil) -> HUDTapAction? {
        if let action = bluetoothProvider.bluetoothState.action {
            return action
        } else if let onboardingManager = onboardingManager, !onboardingManager.isComplete, pumpManager?.isOnboarded != true {
            onboardingManager.resume()
            return .takeNoAction
        } else if let pumpManagerHUDProvider = pumpManagerHUDProvider,
            let view = view,
            let action = pumpManagerHUDProvider.didTapOnHUDView(view, allowDebugFeatures: FeatureFlags.allowDebugFeatures)
        {
            return action
        } else if let pumpManager = pumpManager as? PumpManagerUI {
            return .presentViewController(pumpManager.settingsViewController(bluetoothProvider: bluetoothProvider, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures, allowedInsulinTypes: allowedInsulinTypes))
        } else {
            return .setupNewPump
        }
    }    
}

// MARK: - BluetoothState

fileprivate extension BluetoothState {
    struct Highlight: DeviceStatusHighlight {
        var localizedMessage: String
        var imageName: String = "bluetooth.disabled"
        var state: DeviceStatusHighlightState = .critical

        init(localizedMessage: String) {
            self.localizedMessage = localizedMessage
        }
    }

    static var offHighlight: Highlight {
        return Highlight(localizedMessage: NSLocalizedString("Bluetooth\nOff", comment: "Message to the user to that the bluetooth is off"))
    }

    static var enableHighlight: Highlight {
        return Highlight(localizedMessage: NSLocalizedString("Enable\nBluetooth", comment: "Message to the user to enable bluetooth"))
    }

    static var unavailableHighlight: Highlight {
        return Highlight(localizedMessage: NSLocalizedString("Bluetooth\nUnavailable", comment: "Message to the user that bluetooth is unavailable to the app"))
    }

    var action: HUDTapAction? {
        switch self {
        case .unauthorized:
            return .openAppURL(URL(string: UIApplication.openSettingsURLString)!)
        case .poweredOff:
            return .takeNoAction
        default:
            return nil
        }
    }
}
