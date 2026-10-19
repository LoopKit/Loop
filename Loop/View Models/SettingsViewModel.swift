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
    var didTap: () -> Void
    var didTapAdd: (_ device: T) -> Void
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
    func generateDiagnosticReport() async -> String
    var closedLoopDescriptiveText: String? { get }
    var automaticDosingEnabled: Bool { get set }
    var automationHistory: [AutomationHistoryEntry] { get }
}

@Observable
class SettingsViewModel {
    
    let alertPermissionsChecker: AlertPermissionsChecker

    let alertMuter: AlertMuter

    let versionUpdateViewModel: VersionUpdateViewModel
    
    weak var delegate: SettingsViewModelDelegate?
    
    weak var deliveryDelegate: DeliveryDelegate?

    var generateDiagnosticReport: (() async -> String)? {
        guard let delegate else {
            return nil
        }
        return { [weak delegate] in await delegate?.generateDiagnosticReport() ?? "" }
    }

    @MainActor
    var issueReportContext: [String: IssueReportContextValue] {
        let buildDetails = BuildDetails.default
        var context: [String: IssueReportContextValue] = [
            "appVersion": .string(Bundle.main.shortVersionString),
            "buildNumber": .string(Bundle.main.version),
            "customizations": .strings(buildDetails.customizations),
            "deviceModel": .string(UIDevice.current.modelIdentifier),
            "osVersion": .string(UIDevice.current.systemVersion),
        ]
        context["branch"] = (buildDetails.workspaceGitBranch ?? buildDetails.gitBranch).map { .string($0) }
        context["workspaceRevision"] = buildDetails.workspaceGitRevision.map { .string($0) }
        context["loopRevision"] = buildDetails.gitRevision.map { .string($0) }
        context["pumpModel"] = deviceManager?.pumpManager.map { .string($0.status.device.model ?? "Unknown") }
        context["cgmModel"] = deviceManager?.cgmManager.map { .string($0.cgmManagerStatus.device?.model ?? "Unknown") }
        return context
    }
    
    var availableSupports: [SupportUI]
    let pumpManagerSettingsViewModel: PumpManagerViewModel
    let cgmManagerSettingsViewModel: CGMManagerViewModel
    let servicesViewModel: ServicesViewModel
    let criticalEventLogExportViewModel: CriticalEventLogExportViewModel
    let therapySettings: () -> TherapySettings
    var isOnboardingComplete: Bool
    let therapySettingsViewModelDelegate: TherapySettingsViewModelDelegate?
    let presetHistory: TemporaryScheduleOverrideHistory

    private(set) var automaticDosingEnabled: Bool {
        get {
            delegate?.automaticDosingEnabled ?? closedLoopPreference
        }
        set {
            delegate?.automaticDosingEnabled = newValue
        }
    }
    
    private(set) var lastLoopCompletion: Date?
    private(set) var mostRecentGlucoseDataDate: Date?
    private(set) var mostRecentPumpDataDate: Date?
    
    var closedLoopDescriptiveText: String? {
        delegate?.closedLoopDescriptiveText
    }

    var automaticDosingStrategy: AutomaticDosingStrategy {
        didSet {
            delegate?.dosingStrategyChanged(automaticDosingStrategy)
        }
    }

    var closedLoopPreference: Bool {
       didSet {
           delegate?.dosingEnabledChanged(closedLoopPreference)
       }
    }
    
    private(set) var deviceManager: DeviceDataManager?
    
    @MainActor
    var deviceIssue: Bool {
        deviceManager?.cgmManager == nil || deviceManager?.cgmManager?.isInoperable == true || deviceManager?.cgmManager?.inSignalLoss == true || deviceManager?.pumpManager == nil || deviceManager?.pumpManager?.isInoperable == true || deviceManager?.pumpManager?.inSignalLoss == true || deviceManager?.hasBluetoothIssue != false
    }

    var preMealGuardrail: Guardrail<LoopQuantity>?

    @ObservationIgnored weak var favoriteFoodInsightsDelegate: FavoriteFoodInsightsViewModelDelegate?

    @MainActor
    var showDeleteTestData: Bool {
        availableSupports.contains(where: { $0.showsDeleteTestDataUI })
    }
    
    var loopStatusCircleFreshness: LoopCompletionFreshness {
        if automaticDosingEnabled {
            let lastLoopCompletion = lastLoopCompletion ?? Date().addingTimeInterval(.minutes(16))
            let age = abs(min(0, lastLoopCompletion.timeIntervalSinceNow))
            return LoopCompletionFreshness(age: age)
        } else {
            return .fresh
        }
    }
    
    @ObservationIgnored lazy private var cancellables = Set<AnyCancellable>()

    @MainActor
    public init(alertPermissionsChecker: AlertPermissionsChecker,
                alertMuter: AlertMuter,
                versionUpdateViewModel: VersionUpdateViewModel,
                pumpManagerSettingsViewModel: PumpManagerViewModel,
                cgmManagerSettingsViewModel: CGMManagerViewModel,
                servicesViewModel: ServicesViewModel,
                criticalEventLogExportViewModel: CriticalEventLogExportViewModel,
                therapySettings: @escaping () -> TherapySettings,
                initialDosingEnabled: Bool,
                automaticDosingStrategy: AutomaticDosingStrategy,
                lastLoopCompletion: Published<Date?>.Publisher,
                mostRecentGlucoseDataDate: Published<Date?>.Publisher,
                mostRecentPumpDataDate: Published<Date?>.Publisher,
                availableSupports: [SupportUI],
                isOnboardingComplete: Bool,
                therapySettingsViewModelDelegate: TherapySettingsViewModelDelegate?,
                presetHistory: TemporaryScheduleOverrideHistory,
                deliveryDelegate: DeliveryDelegate?,
                deviceManager: DeviceDataManager?,
    ) {
        self.alertPermissionsChecker = alertPermissionsChecker
        self.alertMuter = alertMuter
        self.versionUpdateViewModel = versionUpdateViewModel
        self.pumpManagerSettingsViewModel = pumpManagerSettingsViewModel
        self.cgmManagerSettingsViewModel = cgmManagerSettingsViewModel
        self.servicesViewModel = servicesViewModel
        self.criticalEventLogExportViewModel = criticalEventLogExportViewModel
        self.therapySettings = therapySettings
        self.closedLoopPreference = initialDosingEnabled
        self.automaticDosingStrategy = automaticDosingStrategy
        self.lastLoopCompletion = nil
        self.mostRecentGlucoseDataDate = nil
        self.mostRecentPumpDataDate = nil
        self.availableSupports = availableSupports
        self.isOnboardingComplete = isOnboardingComplete
        self.therapySettingsViewModelDelegate = therapySettingsViewModelDelegate
        self.presetHistory = presetHistory
        self.deliveryDelegate = deliveryDelegate
        self.deviceManager = deviceManager

        // This strangeness ensures the composed ViewModels' (ObservableObjects') changes get reported to this ViewModel (ObservableObject)
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

    @MainActor func deleteAllTestingData() {
        Task {
            try? await deviceManager?.deleteTestingPumpData()

            try? await deviceManager?.deleteTestingCGMData()

            try? await deviceManager?.deleteTestingCarbData()

            try? await deviceManager?.deleteTestingAlertData()
        }
    }
}

// For previews only
@MainActor
extension SettingsViewModel {
    fileprivate class FakeLastLoopCompletionPublisher {
        @Published var mockLastLoopCompletion: Date? = nil
    }
    
    fileprivate class FakeSettingsProvider: SettingsProvider {
        let settings = StoredSettings()
        var dosingEnabled: Bool { settings.dosingEnabled }
        
        func getBasalHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
            []
        }
        
        func getCarbRatioHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<Double>] {
            []
        }
        
        func getInsulinSensitivityHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<LoopQuantity>] {
            []
        }
        
        func getTargetRangeHistory(startDate: Date, endDate: Date) async throws -> [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>] {
            []
        }
        
        func getDosingLimits(at date: Date) async throws -> DosingLimits {
            DosingLimits()
        }
        
        func executeSettingsQuery(fromQueryAnchor queryAnchor: SettingsStore.QueryAnchor?, limit: Int, completion: @escaping (SettingsStore.SettingsQueryResult) -> Void) {}
        
        
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
                                 initialDosingEnabled: true,
                                 automaticDosingStrategy: .automaticBolus,
                                 lastLoopCompletion: FakeLastLoopCompletionPublisher().$mockLastLoopCompletion,
                                 mostRecentGlucoseDataDate: FakeLastLoopCompletionPublisher().$mockLastLoopCompletion,
                                 mostRecentPumpDataDate: FakeLastLoopCompletionPublisher().$mockLastLoopCompletion,
                                 availableSupports: [],
                                 isOnboardingComplete: false,
                                 therapySettingsViewModelDelegate: nil,
                                 presetHistory: TemporaryScheduleOverrideHistory(),
                                 deliveryDelegate: nil,
                                 deviceManager: nil
        )
    }
}
