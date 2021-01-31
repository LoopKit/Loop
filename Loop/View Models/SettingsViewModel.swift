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
import HealthKit

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
    func dosingStrategyChanged(_: DosingStrategy)
    func didSave(therapySetting: TherapySetting, therapySettings: TherapySettings)
    func didTapIssueReport(title: String)
}

public class SettingsViewModel: ObservableObject {
    
    let notificationsCriticalAlertPermissionsViewModel: NotificationsCriticalAlertPermissionsViewModel

    private weak var delegate: SettingsViewModelDelegate?
    
    var showWarning: Bool {
        notificationsCriticalAlertPermissionsViewModel.showWarning
    }
    
    var didSave: TherapySettingsViewModel.SaveCompletion? {
        delegate?.didSave
    }
    
    var didTapIssueReport: ((String) -> Void)? {
        delegate?.didTapIssueReport
    }
    
    var activeServices: [Service]
    let pumpManagerSettingsViewModel: DeviceViewModel
    let cgmManagerSettingsViewModel: DeviceViewModel
    let servicesViewModel: ServicesViewModel
    let criticalEventLogExportViewModel: CriticalEventLogExportViewModel
    let therapySettings: () -> TherapySettings
    let supportedInsulinModelSettings: SupportedInsulinModelSettings
    let pumpSupportedIncrements: (() -> PumpSupportedIncrements?)?
    let syncPumpSchedule: (() -> PumpManager.SyncSchedule?)?
    let sensitivityOverridesEnabled: Bool
    let preferredGlucoseUnit: HKUnit
    let supportInfoProvider: SupportInfoProvider
        
    @Published var isClosedLoopAllowed: Bool
    @Published var dosingStrategy: DosingStrategy {
        didSet {
            delegate?.dosingStrategyChanged(dosingStrategy)
        }
    }

    var closedLoopPreference: Bool {
       didSet {
           delegate?.dosingEnabledChanged(closedLoopPreference)
       }
    }

    lazy private var cancellables = Set<AnyCancellable>()

    public init(notificationsCriticalAlertPermissionsViewModel: NotificationsCriticalAlertPermissionsViewModel,
                pumpManagerSettingsViewModel: DeviceViewModel,
                cgmManagerSettingsViewModel: DeviceViewModel,
                servicesViewModel: ServicesViewModel,
                criticalEventLogExportViewModel: CriticalEventLogExportViewModel,
                therapySettings: @escaping () -> TherapySettings,
                supportedInsulinModelSettings: SupportedInsulinModelSettings,
                pumpSupportedIncrements: (() -> PumpSupportedIncrements?)?,
                syncPumpSchedule: (() -> PumpManager.SyncSchedule?)?,
                sensitivityOverridesEnabled: Bool,
                initialDosingEnabled: Bool,
                isClosedLoopAllowed: Published<Bool>.Publisher,
                preferredGlucoseUnit: HKUnit,
                supportInfoProvider: SupportInfoProvider,
                activeServices: [Service],
                dosingStrategy: DosingStrategy,
                delegate: SettingsViewModelDelegate?
    ) {
        self.notificationsCriticalAlertPermissionsViewModel = notificationsCriticalAlertPermissionsViewModel
        self.pumpManagerSettingsViewModel = pumpManagerSettingsViewModel
        self.cgmManagerSettingsViewModel = cgmManagerSettingsViewModel
        self.servicesViewModel = servicesViewModel
        self.criticalEventLogExportViewModel = criticalEventLogExportViewModel
        self.therapySettings = therapySettings
        self.supportedInsulinModelSettings = supportedInsulinModelSettings
        self.pumpSupportedIncrements = pumpSupportedIncrements
        self.syncPumpSchedule = syncPumpSchedule
        self.sensitivityOverridesEnabled = sensitivityOverridesEnabled
        self.closedLoopPreference = initialDosingEnabled
        self.isClosedLoopAllowed = false
        self.preferredGlucoseUnit = preferredGlucoseUnit
        self.supportInfoProvider = supportInfoProvider
        self.activeServices = activeServices
        self.dosingStrategy = dosingStrategy
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
        
        isClosedLoopAllowed
            .assign(to: \.isClosedLoopAllowed, on: self)
            .store(in: &cancellables)
        
    }
}
