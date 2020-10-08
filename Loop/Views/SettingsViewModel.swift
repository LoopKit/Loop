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
    public typealias DeleteTestingDataFunc = () -> Void
    
    let isSetUp: () -> Bool
    let image: () -> UIImage?
    let name: () -> String
    let deleteTestingDataFunc: () -> DeleteTestingDataFunc?
    let didTap: () -> Void
    let didTapAdd: (_ device: AvailableDevice) -> Void
    var isTestingDevice: Bool {
        return deleteTestingDataFunc() != nil
    }

    @Published var availableDevices: [AvailableDevice]

    public init(image: @escaping () -> UIImage? = { nil },
                name: @escaping () -> String = { "" },
                isSetUp: @escaping () -> Bool = { false },
                availableDevices: [AvailableDevice] = [],
                deleteTestingDataFunc: @escaping  () -> DeleteTestingDataFunc? = { nil },
                onTapped: @escaping () -> Void = { },
                didTapAddDevice: @escaping (AvailableDevice) -> Void = { _ in  }
                ) {
        self.image = image
        self.name = name
        self.availableDevices = availableDevices
        self.isSetUp = isSetUp
        self.deleteTestingDataFunc = deleteTestingDataFunc
        self.didTap = onTapped
        self.didTapAdd = didTapAddDevice
    }
}

public protocol SettingsViewModelDelegate: class {
    func dosingEnabledChanged(_: Bool)
    func didSave(therapySetting: TherapySetting, therapySettings: TherapySettings)
    func didTapIssueReport(title: String)
}

public class SettingsViewModel: ObservableObject {
    
    let notificationsCriticalAlertPermissionsViewModel: NotificationsCriticalAlertPermissionsViewModel

    private weak var delegate: SettingsViewModelDelegate?
    
    @Published var appNameAndVersion: String
    @Published var dosingEnabled: Bool {
        didSet {
            delegate?.dosingEnabledChanged(dosingEnabled)
        }
    }
    
    var showWarning: Bool {
        notificationsCriticalAlertPermissionsViewModel.showWarning
    }
    
    var didSave: TherapySettingsViewModel.SaveCompletion? {
        delegate?.didSave
    }
    
    var didTapIssueReport: ((String) -> Void)? {
        delegate?.didTapIssueReport
    }

    var pumpManagerSettingsViewModel: DeviceViewModel
    var cgmManagerSettingsViewModel: DeviceViewModel
    var servicesViewModel: ServicesViewModel
    var criticalEventLogExportViewModel: CriticalEventLogExportViewModel
    var therapySettings: TherapySettings
    let supportedInsulinModelSettings: SupportedInsulinModelSettings
    let pumpSupportedIncrements: (() -> PumpSupportedIncrements?)?
    let syncPumpSchedule: (() -> PumpManager.SyncSchedule?)?
    let sensitivityOverridesEnabled: Bool

    lazy private var cancellables = Set<AnyCancellable>()

    public init(appNameAndVersion: String,
                notificationsCriticalAlertPermissionsViewModel: NotificationsCriticalAlertPermissionsViewModel,
                pumpManagerSettingsViewModel: DeviceViewModel,
                cgmManagerSettingsViewModel: DeviceViewModel,
                servicesViewModel: ServicesViewModel,
                criticalEventLogExportViewModel: CriticalEventLogExportViewModel,
                therapySettings: TherapySettings,
                supportedInsulinModelSettings: SupportedInsulinModelSettings,
                pumpSupportedIncrements: (() -> PumpSupportedIncrements?)?,
                syncPumpSchedule: (() -> PumpManager.SyncSchedule?)?,
                sensitivityOverridesEnabled: Bool,
                initialDosingEnabled: Bool,
                delegate: SettingsViewModelDelegate?
    ) {
        self.notificationsCriticalAlertPermissionsViewModel = notificationsCriticalAlertPermissionsViewModel
        self.appNameAndVersion = appNameAndVersion
        self.pumpManagerSettingsViewModel = pumpManagerSettingsViewModel
        self.cgmManagerSettingsViewModel = cgmManagerSettingsViewModel
        self.servicesViewModel = servicesViewModel
        self.criticalEventLogExportViewModel = criticalEventLogExportViewModel
        self.therapySettings = therapySettings
        self.supportedInsulinModelSettings = supportedInsulinModelSettings
        self.pumpSupportedIncrements = pumpSupportedIncrements
        self.syncPumpSchedule = syncPumpSchedule
        self.sensitivityOverridesEnabled = sensitivityOverridesEnabled
        self.dosingEnabled = initialDosingEnabled
        self.delegate = delegate
        
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
