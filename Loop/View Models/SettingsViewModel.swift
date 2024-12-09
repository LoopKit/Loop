//
//  SettingsViewModel.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/25/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Combine
import LoopAlgorithm
import LoopCore
import LoopKit
import LoopKitUI
import SwiftUI

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
    let presetHistory: TemporaryScheduleOverrideHistory

    @Published private(set) var automaticDosingStatus: AutomaticDosingStatus
    
    @Published private(set) var lastLoopCompletion: Date?
    @Published private(set) var mostRecentGlucoseDataDate: Date?
    @Published private(set) var mostRecentPumpDataDate: Date?

    var closedLoopDescriptiveText: String? {
        return delegate?.closedLoopDescriptiveText
    }


    @Published var automaticDosingStrategy: AutomaticDosingStrategy {
        didSet {
            delegate?.dosingStrategyChanged(automaticDosingStrategy)
        }
    }

    @Published var closedLoopPreference: Bool {
       didSet {
           delegate?.dosingEnabledChanged(closedLoopPreference)
       }
    }

    var preMealGuardrail: Guardrail<LoopQuantity>? {
        guard let scheduleRange = therapySettings().glucoseTargetRangeSchedule?.scheduleRange() else {
            return nil
        }
        return Guardrail.correctionRangeOverride(
            for: .preMeal,
            correctionRangeScheduleRange: scheduleRange,
            suspendThreshold: therapySettings().suspendThreshold
        )
    }

    var legacyWorkoutPresetGuardrail: Guardrail<LoopQuantity>? {
        guard let scheduleRange = therapySettings().glucoseTargetRangeSchedule?.scheduleRange() else {
            return nil
        }
        return Guardrail.correctionRangeOverride(
            for: .workout,
            correctionRangeScheduleRange: scheduleRange,
            suspendThreshold: therapySettings().suspendThreshold
        )
    }


    weak var favoriteFoodInsightsDelegate: FavoriteFoodInsightsViewModelDelegate?

    var showDeleteTestData: Bool {
        availableSupports.contains(where: { $0.showsDeleteTestDataUI })
    }
    
    var loopStatusCircleFreshness: LoopCompletionFreshness {
        var age: TimeInterval
        
        if automaticDosingStatus.automaticDosingEnabled {
            let lastLoopCompletion = lastLoopCompletion ?? Date().addingTimeInterval(.minutes(16))
            age = abs(min(0, lastLoopCompletion.timeIntervalSinceNow))
        } else {
            let mostRecentGlucoseDataDate = mostRecentGlucoseDataDate ?? Date().addingTimeInterval(.minutes(16))
            let mostRecentPumpDataDate = mostRecentPumpDataDate ?? Date().addingTimeInterval(.minutes(16))
            age = max(abs(min(0, mostRecentPumpDataDate.timeIntervalSinceNow)), abs(min(0, mostRecentGlucoseDataDate.timeIntervalSinceNow)))
        }
        
        return LoopCompletionFreshness(age: age)
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
                automaticDosingStatus: AutomaticDosingStatus,
                automaticDosingStrategy: AutomaticDosingStrategy,
                lastLoopCompletion: Published<Date?>.Publisher,
                mostRecentGlucoseDataDate: Published<Date?>.Publisher,
                mostRecentPumpDataDate: Published<Date?>.Publisher,
                availableSupports: [SupportUI],
                isOnboardingComplete: Bool,
                therapySettingsViewModelDelegate: TherapySettingsViewModelDelegate?,
                presetHistory: TemporaryScheduleOverrideHistory,
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
        self.automaticDosingStatus = automaticDosingStatus
        self.automaticDosingStrategy = automaticDosingStrategy
        self.lastLoopCompletion = nil
        self.mostRecentGlucoseDataDate = nil
        self.mostRecentPumpDataDate = nil
        self.availableSupports = availableSupports
        self.isOnboardingComplete = isOnboardingComplete
        self.therapySettingsViewModelDelegate = therapySettingsViewModelDelegate
        self.presetHistory = presetHistory
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
        automaticDosingStatus.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
        lastLoopCompletion
            .assign(to: \.lastLoopCompletion, on: self)
            .store(in: &cancellables)
        mostRecentGlucoseDataDate
            .assign(to: \.mostRecentGlucoseDataDate, on: self)
            .store(in: &cancellables)
        mostRecentPumpDataDate
            .assign(to: \.mostRecentPumpDataDate, on: self)
            .store(in: &cancellables)
    }
}

// For previews only
@MainActor
extension SettingsViewModel {
    fileprivate class FakeLastLoopCompletionPublisher {
        @Published var mockLastLoopCompletion: Date? = nil
    }

    static var preview: SettingsViewModel {
        return SettingsViewModel(alertPermissionsChecker: AlertPermissionsChecker(),
                                 alertMuter: AlertMuter(),
                                 versionUpdateViewModel: VersionUpdateViewModel(supportManager: nil, guidanceColors: .default),
                                 pumpManagerSettingsViewModel: DeviceViewModel<PumpManagerDescriptor>(),
                                 cgmManagerSettingsViewModel: DeviceViewModel<CGMManagerDescriptor>(),
                                 servicesViewModel: ServicesViewModel.preview,
                                 criticalEventLogExportViewModel: CriticalEventLogExportViewModel(exporterFactory: MockCriticalEventLogExporterFactory()),
                                 therapySettings: { TherapySettings() },
                                 sensitivityOverridesEnabled: false,
                                 initialDosingEnabled: true,
                                 automaticDosingStatus: AutomaticDosingStatus(automaticDosingEnabled: true, isAutomaticDosingAllowed: true),
                                 automaticDosingStrategy: .automaticBolus,
                                 lastLoopCompletion: FakeLastLoopCompletionPublisher().$mockLastLoopCompletion,
                                 mostRecentGlucoseDataDate: FakeLastLoopCompletionPublisher().$mockLastLoopCompletion,
                                 mostRecentPumpDataDate: FakeLastLoopCompletionPublisher().$mockLastLoopCompletion,
                                 availableSupports: [],
                                 isOnboardingComplete: false,
                                 therapySettingsViewModelDelegate: nil,
                                 presetHistory: TemporaryScheduleOverrideHistory(),
                                 delegate: nil
        )
    }
}
