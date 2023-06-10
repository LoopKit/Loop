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

public class DeviceViewModel<T>: ObservableObject {
    public typealias DeleteTestingDataFunc = () -> Void
    
    let isSetUp: () -> Bool
    let image: () -> UIImage?
    let name: () -> String
    let deleteTestingDataFunc: () -> DeleteTestingDataFunc?
    let didTap: () -> Void
    let didTapAdd: (_ device: T) -> Void
    var isTestingDevice: Bool {
        return deleteTestingDataFunc() != nil
    }

    @Published var availableDevices: [T]

    public init(image: @escaping () -> UIImage? = { nil },
                name: @escaping () -> String = { "" },
                isSetUp: @escaping () -> Bool = { false },
                availableDevices: [T] = [],
                deleteTestingDataFunc: @escaping  () -> DeleteTestingDataFunc? = { nil },
                onTapped: @escaping () -> Void = { },
                didTapAddDevice: @escaping (T) -> Void = { _ in  }
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

public typealias CGMManagerViewModel = DeviceViewModel<CGMManagerDescriptor>
public typealias PumpManagerViewModel = DeviceViewModel<PumpManagerDescriptor>

public protocol SettingsViewModelDelegate: AnyObject {
    func dosingEnabledChanged(_: Bool)
    func dosingStrategyChanged(_: AutomaticDosingStrategy)
    func didTapIssueReport()
    var closedLoopDescriptiveText: String? { get }
}

public class SettingsViewModel: ObservableObject {
    
    let alertPermissionsChecker: AlertPermissionsChecker

    let alertMuter: AlertMuter

    let versionUpdateViewModel: VersionUpdateViewModel
    
    private weak var delegate: SettingsViewModelDelegate?

    func didTapIssueReport() {
        delegate?.didTapIssueReport()
    }
    
    var availableSupports: [SupportUI]
    let pumpManagerSettingsViewModel: PumpManagerViewModel
    let cgmManagerSettingsViewModel: CGMManagerViewModel
    let servicesViewModel: ServicesViewModel
    let criticalEventLogExportViewModel: CriticalEventLogExportViewModel
    let therapySettings: () -> TherapySettings
    let sensitivityOverridesEnabled: Bool
    let isOnboardingComplete: Bool
    let therapySettingsViewModelDelegate: TherapySettingsViewModelDelegate?

    @Published var isClosedLoopAllowed: Bool

    var closedLoopDescriptiveText: String? {
        return delegate?.closedLoopDescriptiveText
    }


    @Published var automaticDosingStrategy: AutomaticDosingStrategy {
        didSet {
            delegate?.dosingStrategyChanged(automaticDosingStrategy)
        }
    }

    var closedLoopPreference: Bool {
       didSet {
           delegate?.dosingEnabledChanged(closedLoopPreference)
       }
    }

    lazy private var cancellables = Set<AnyCancellable>()

    public init(alertPermissionsChecker: AlertPermissionsChecker,
                alertMuter: AlertMuter,
                versionUpdateViewModel: VersionUpdateViewModel,
                pumpManagerSettingsViewModel: PumpManagerViewModel,
                cgmManagerSettingsViewModel: CGMManagerViewModel,
                servicesViewModel: ServicesViewModel,
                criticalEventLogExportViewModel: CriticalEventLogExportViewModel,
                therapySettings: @escaping () -> TherapySettings,
                sensitivityOverridesEnabled: Bool,
                initialDosingEnabled: Bool,
                isClosedLoopAllowed: Published<Bool>.Publisher,
                automaticDosingStrategy: AutomaticDosingStrategy,
                availableSupports: [SupportUI],
                isOnboardingComplete: Bool,
                therapySettingsViewModelDelegate: TherapySettingsViewModelDelegate?,
                delegate: SettingsViewModelDelegate?
    ) {
        self.alertPermissionsChecker = alertPermissionsChecker
        self.alertMuter = alertMuter
        self.versionUpdateViewModel = versionUpdateViewModel
        self.pumpManagerSettingsViewModel = pumpManagerSettingsViewModel
        self.cgmManagerSettingsViewModel = cgmManagerSettingsViewModel
        self.servicesViewModel = servicesViewModel
        self.criticalEventLogExportViewModel = criticalEventLogExportViewModel
        self.therapySettings = therapySettings
        self.sensitivityOverridesEnabled = sensitivityOverridesEnabled
        self.closedLoopPreference = initialDosingEnabled
        self.isClosedLoopAllowed = false
        self.automaticDosingStrategy = automaticDosingStrategy
        self.availableSupports = availableSupports
        self.isOnboardingComplete = isOnboardingComplete
        self.therapySettingsViewModelDelegate = therapySettingsViewModelDelegate
        self.delegate = delegate

        // This strangeness ensures the composed ViewModels' (ObservableObjects') changes get reported to this ViewModel (ObservableObject)
        alertPermissionsChecker.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
        alertMuter.objectWillChange.sink { [weak self] in
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

// For previews only
extension SettingsViewModel {
    fileprivate class FakeClosedLoopAllowedPublisher {
        @Published var mockIsClosedLoopAllowed: Bool = false
    }

    static var preview: SettingsViewModel {
        return SettingsViewModel(alertPermissionsChecker: AlertPermissionsChecker(),
                                 alertMuter: AlertMuter(),
                                 versionUpdateViewModel: VersionUpdateViewModel(supportManager: nil, guidanceColors: GuidanceColors()),
                                 pumpManagerSettingsViewModel: DeviceViewModel<PumpManagerDescriptor>(),
                                 cgmManagerSettingsViewModel: DeviceViewModel<CGMManagerDescriptor>(),
                                 servicesViewModel: ServicesViewModel.preview,
                                 criticalEventLogExportViewModel: CriticalEventLogExportViewModel(exporterFactory: MockCriticalEventLogExporterFactory()),
                                 therapySettings: { TherapySettings() },
                                 sensitivityOverridesEnabled: false,
                                 initialDosingEnabled: true,
                                 isClosedLoopAllowed: FakeClosedLoopAllowedPublisher().$mockIsClosedLoopAllowed,
                                 automaticDosingStrategy: .automaticBolus,
                                 availableSupports: [],
                                 isOnboardingComplete: false,
                                 therapySettingsViewModelDelegate: nil,
                                 delegate: nil)
    }
}
