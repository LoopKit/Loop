//
//  SettingsViewModel.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/25/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Combine
import LoopCore
import LoopKit
import LoopKitUI
import SwiftUI

public class DeviceViewModel: ObservableObject {
    public init(deviceManagerUI: DeviceManagerUI? = nil,
                isSetUp: Bool = false,
                onTapped: @escaping () -> Void = { }) {
        self.deviceManagerUI = deviceManagerUI
        self.isSetUp = isSetUp
        self.onTapped = onTapped
    }
    
    let deviceManagerUI: DeviceManagerUI?

    @Published private(set) var isSetUp: Bool = false
    
    var image: UIImage? { deviceManagerUI?.smallImage }
    var name: String { deviceManagerUI?.localizedTitle ?? "" }
   
    let onTapped: () -> Void
}

public class SettingsViewModel: ObservableObject {
    
    var notificationsCriticalAlertPermissionsViewModel: NotificationsCriticalAlertPermissionsViewModel

    @Published var appNameAndVersion: String
    @Published var dosingEnabled: Bool {
        didSet {
            setDosingEnabled?(dosingEnabled)
        }
    }
    private let setDosingEnabled: ((Bool) -> Void)?
    
    var showWarning: Bool {
        notificationsCriticalAlertPermissionsViewModel.showWarning
    }

    var pumpManagerSettingsViewModel: DeviceViewModel
    var cgmManagerSettingsViewModel: DeviceViewModel
    var therapySettings: TherapySettings
    let supportedInsulinModelSettings: SupportedInsulinModelSettings
    let pumpSupportedIncrements: PumpSupportedIncrements?
    let syncPumpSchedule: PumpManager.SyncSchedule?
    let sensitivityOverridesEnabled: Bool
    let didSave: TherapySettingsViewModel.SaveCompletion?

    lazy private var cancellables = Set<AnyCancellable>()

    public init(appNameAndVersion: String,
                notificationsCriticalAlertPermissionsViewModel: NotificationsCriticalAlertPermissionsViewModel,
                pumpManagerSettingsViewModel: DeviceViewModel,
                cgmManagerSettingsViewModel: DeviceViewModel,
                therapySettings: TherapySettings,
                supportedInsulinModelSettings: SupportedInsulinModelSettings,
                pumpSupportedIncrements: PumpSupportedIncrements?,
                syncPumpSchedule: PumpManager.SyncSchedule?,
                sensitivityOverridesEnabled: Bool,
                // TODO: This is temporary until I can figure out something cleaner
                initialDosingEnabled: Bool,
                setDosingEnabled: ((Bool) -> Void)? = nil,
                didSave: TherapySettingsViewModel.SaveCompletion? = nil
                ) {
        self.notificationsCriticalAlertPermissionsViewModel = notificationsCriticalAlertPermissionsViewModel
        self.appNameAndVersion = appNameAndVersion
        self.pumpManagerSettingsViewModel = pumpManagerSettingsViewModel
        self.cgmManagerSettingsViewModel = cgmManagerSettingsViewModel
        self.setDosingEnabled = setDosingEnabled
        self.dosingEnabled = initialDosingEnabled
        self.therapySettings = therapySettings
        self.supportedInsulinModelSettings = supportedInsulinModelSettings
        self.pumpSupportedIncrements = pumpSupportedIncrements
        self.syncPumpSchedule = syncPumpSchedule
        self.sensitivityOverridesEnabled = sensitivityOverridesEnabled
        self.didSave = didSave

        // This strangeness ensures the composed ViewModels' (ObservableObjects') changes get reported to this ViewModel (ObservableObject)
        notificationsCriticalAlertPermissionsViewModel.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
        pumpManagerSettingsViewModel.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
        cgmManagerSettingsViewModel.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }
}
