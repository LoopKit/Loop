//
//  TestingScenariosManager.swift
//  Loop
//
//  Created by Michael Pangburn on 4/20/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopTestingKit
import LoopKitUI

protocol TestingScenariosManagerDelegate: AnyObject {
    func testingScenariosManager(_ manager: TestingScenariosManager, didUpdateScenarioURLs scenarioURLs: [URL])
}

@MainActor
final class TestingScenariosManager: DirectoryObserver {

    unowned let deviceManager: DeviceDataManager
    unowned let supportManager: SupportManager
    unowned let pluginManager: PluginManager
    unowned let carbStore: CarbStore
    unowned let settingsManager: SettingsManager

    let log = DiagnosticLog(category: "LocalTestingScenariosManager")

    private let fileManager = FileManager.default
    private let scenariosSource: URL
    private var directoryObservationToken: DirectoryObservationToken?

    private(set) var scenarioURLs: [URL] = []
    var activeScenarioURL: URL?
    var activeScenario: TestingScenario?

    weak var delegate: TestingScenariosManagerDelegate? {
        didSet {
            delegate?.testingScenariosManager(self, didUpdateScenarioURLs: scenarioURLs)
        }
    }

    init(
        deviceManager: DeviceDataManager,
        supportManager: SupportManager,
        pluginManager: PluginManager,
        carbStore: CarbStore,
        settingsManager: SettingsManager
    ) {
        guard FeatureFlags.scenariosEnabled else {
            fatalError("\(#function) should be invoked only when scenarios are enabled")
        }

        self.deviceManager = deviceManager
        self.supportManager = supportManager
        self.pluginManager = pluginManager
        self.carbStore = carbStore
        self.settingsManager = settingsManager
        self.scenariosSource = Bundle.main.bundleURL.appendingPathComponent("Scenarios")

        log.debug("Loading testing scenarios from %{public}@", scenariosSource.path)
        if !fileManager.fileExists(atPath: scenariosSource.path) {
            do {
                try fileManager.createDirectory(at: scenariosSource, withIntermediateDirectories: false)
            } catch {
                log.error("%{public}@", String(describing: error))
            }
        }

        directoryObservationToken = observeDirectory(at: scenariosSource) { [weak self] in
            self?.reloadScenarioURLs()
        }
        reloadScenarioURLs()
    }

    func fetchScenario(from url: URL, completion: (Result<TestingScenario, Error>) -> Void) {
        let result = Result(catching: { try TestingScenario(source: url) })
        completion(result)
    }

    private func reloadScenarioURLs() {
        do {
            let scenarioURLs = try fileManager.contentsOfDirectory(at: scenariosSource, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            self.scenarioURLs = scenarioURLs
            delegate?.testingScenariosManager(self, didUpdateScenarioURLs: scenarioURLs)
            log.debug("Reloaded scenario URLs")
        } catch {
            log.error("%{public}@", String(describing: error))
        }
    }
}

extension TestingScenariosManager {
    func loadScenario(from url: URL, completion: @escaping (Error?) -> Void) {
        loadScenario(
            from: url,
            loadingVia: self.loadScenario(_:completion:),
            successLogMessage: "Loaded scenario from \(url.lastPathComponent)",
            completion: completion
        )
    }

    func loadScenario(from url: URL, advancedByLoopIterations iterations: Int, completion: @escaping (Error?) -> Void) {
        loadScenario(
            from: url,
            loadingVia: { self.loadScenario($0, advancedByLoopIterations: iterations, completion: $1) },
            successLogMessage: "Loaded scenario from \(url.lastPathComponent), advancing \(iterations) loop iterations",
            completion: completion
        )
    }

    func loadScenario(from url: URL, rewoundByLoopIterations iterations: Int, completion: @escaping (Error?) -> Void) {
        loadScenario(
            from: url,
            loadingVia: { self.loadScenario($0, rewoundByLoopIterations: iterations, completion: $1) },
            successLogMessage: "Loaded scenario from \(url.lastPathComponent), rewinding \(iterations) loop iterations",
            completion: completion
        )
    }

    func stepActiveScenarioBackward(completion: @escaping (Error?) -> Void) {
        guard let activeScenario = activeScenario else {
            completion(nil)
            return
        }

        loadScenario(activeScenario, rewoundByLoopIterations: 1) { error in
            if error == nil {
                self.log.debug("Active scenario stepped backward")
            }
            completion(error)
        }
    }

    func stepActiveScenarioForward(completion: @escaping (Error?) -> Void) {
        guard let activeScenario = activeScenario else {
            completion(nil)
            return
        }

        loadScenario(activeScenario, advancedByLoopIterations: 1) { error in
            if error == nil {
                self.log.debug("Active scenario stepped forward")
            }
            completion(error)
        }
    }
}

// MARK: - Implementation details

private enum ScenarioLoadingError: LocalizedError {
    case noTestingCGMManagerEnabled
    case noTestingPumpManagerEnabled

    var errorDescription: String? {
        switch self {
        case .noTestingCGMManagerEnabled:
            return "Testing CGM manager must be enabled to load CGM scenarios"
        case .noTestingPumpManagerEnabled:
            return "Testing pump manager must be enabled to load pump scenarios"
        }
    }
}

extension TestingScenariosManager {
    private func loadScenario(
        from url: URL,
        loadingVia load: @escaping (
            _ scenario: TestingScenario,
            _ completion: @escaping (Error?) -> Void
            ) -> Void,
        successLogMessage: String,
        completion: @escaping (Error?) -> Void
    ) {
        fetchScenario(from: url) { result in
            switch result {
            case .success(let scenario):
                load(scenario) { error in
                    if error == nil {
                        self.activeScenarioURL = url
                        self.log.debug("%{public}@", successLogMessage)
                    }
                    completion(error)
                }
            case .failure(let error):
                completion(error)
            }
        }
    }

    private func loadScenario(_ scenario: TestingScenario, advancedByLoopIterations iterations: Int, completion: @escaping (Error?) -> Void) {
        assert(iterations >= 0)

        guard iterations > 0 else {
            loadScenario(scenario, completion: completion)
            return
        }

        stepForward(scenario) { advanced in
            self.loadScenario(advanced) { error in
                guard error == nil else {
                    completion(error!)
                    return
                }
                self.loadScenario(advanced, advancedByLoopIterations: iterations - 1, completion: completion)
            }
        }
    }

    private func stepForward(_ scenario: TestingScenario, completion: @escaping (TestingScenario) -> Void) {
        var scenario = scenario
        scenario.stepForward(by: .minutes(5))
        completion(scenario)
    }

    private func loadScenario(_ scenario: TestingScenario, rewoundByLoopIterations iterations: Int, completion: @escaping (Error?) -> Void) {
        assert(iterations > 0)

        let offset = Double(iterations) * .minutes(5)
        var scenario = scenario
        scenario.stepBackward(by: offset)
        loadScenario(scenario, completion: completion)
    }

    private func loadScenario(_ scenario: TestingScenario, completion: @escaping (Error?) -> Void) {
        func bail(with error: Error) {
            activeScenarioURL = nil
            log.error("%{public}@", String(describing: error))
            completion(error)
        }
        
        guard FeatureFlags.scenariosEnabled else {
            fatalError("\(#function) should be invoked only when scenarios are enabled")
        }

        Task { [weak self] in
            do {
                try await self?.wipeExistingData()
                let instance = scenario.instantiate()
                
                let _: Void = try await withCheckedThrowingContinuation { continuation in
                    self?.carbStore.addNewCarbEntries(entries: instance.carbEntries, completion: { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    })
                }
                
                var testingCGMManager: TestingCGMManager?
                var testingPumpManager: TestingPumpManager?
                
                if instance.hasCGMData {
                    if let cgmManager = self?.deviceManager.cgmManager as? TestingCGMManager {
                        if instance.shouldReloadManager?.cgm == true {
                            testingCGMManager = await self?.reloadCGMManager(withIdentifier: cgmManager.pluginIdentifier)
                        } else {
                            testingCGMManager = cgmManager
                        }
                    } else {
                        bail(with: ScenarioLoadingError.noTestingCGMManagerEnabled)
                        return
                    }
                }
                
                if instance.hasPumpData {
                    if let pumpManager = self?.deviceManager.pumpManager as? TestingPumpManager {
                        if instance.shouldReloadManager?.pump == true {
                            testingPumpManager = self?.reloadPumpManager(withIdentifier: pumpManager.pluginIdentifier)
                        } else {
                            testingPumpManager = pumpManager
                        }
                    } else {
                        bail(with: ScenarioLoadingError.noTestingPumpManagerEnabled)
                        return
                    }
                }
                
                testingPumpManager?.reservoirFillFraction = 1.0
                testingPumpManager?.injectPumpEvents(instance.pumpEvents)
                testingCGMManager?.injectGlucoseSamples(instance.pastGlucoseSamples, futureSamples: instance.futureGlucoseSamples)
                
                self?.activeScenario = scenario
                
                instance.deviceActions.forEach { [testingCGMManager, testingPumpManager] action in
                    testingCGMManager?.trigger(action: action)
                    testingPumpManager?.trigger(action: action)
                }
                
                completion(nil)
            } catch {
                bail(with: error)
            }
        }
    }
    
    private func reloadPumpManager(withIdentifier pumpManagerIdentifier: String) -> TestingPumpManager {
        deviceManager.pumpManager = nil
        guard let maximumBasalRate = settingsManager.settings.maximumBasalRatePerHour,
              let maxBolus = settingsManager.settings.maximumBolus,
              let basalSchedule = settingsManager.settings.basalRateSchedule else
        {
            fatalError("Failed to reload pump manager. Missing initial settings")
        }
        let initialSettings = PumpManagerSetupSettings(maxBasalRateUnitsPerHour: maximumBasalRate,
                                                       maxBolusUnits: maxBolus,
                                                       basalSchedule: basalSchedule)
        let result = deviceManager.setupPumpManager(withIdentifier: pumpManagerIdentifier,
                                                    initialSettings: initialSettings,
                                                    prefersToSkipUserInteraction: true)
        switch result {
        case .success(let setupUIResult):
            switch setupUIResult {
            case .createdAndOnboarded(let pumpManager):
                return pumpManager as! TestingPumpManager
            default:
                fatalError("Failed to reload pump manager. UI interaction required for setup")
            }
        default:
            fatalError("Failed to reload pump manager. Setup failed")
        }
    }
    
    private func reloadCGMManager(withIdentifier cgmManagerIdentifier: String) async -> TestingCGMManager {
        await withCheckedContinuation { continuation in
            self.deviceManager.cgmManager?.delete() { [weak self] in
                let result = self?.deviceManager.setupCGMManager(withIdentifier: cgmManagerIdentifier, prefersToSkipUserInteraction: true)
                switch result {
                case .success(let setupUIResult):
                    switch setupUIResult {
                    case .createdAndOnboarded(let cgmManager):
                        let cgmManager = cgmManager as! TestingCGMManager
                        cgmManager.autoStartTrace = false
                        continuation.resume(returning: cgmManager)
                    default:
                        fatalError("Failed to reload CGM manager. UI interaction required for setup")
                    }
                default:
                    fatalError("Failed to reload CGM manager. Setup failed")
                }
            }
        }
    }

    private func wipeExistingData() async throws {
        guard FeatureFlags.scenariosEnabled else {
            fatalError("\(#function) should be invoked only when scenarios are enabled")
        }
        
        try await deviceManager.deleteTestingPumpData()
        
        try await deviceManager.deleteTestingCGMData()
        
        try await carbStore.deleteAllCarbEntries()
        
        await withCheckedContinuation { [weak alertStore = deviceManager.alertManager.alertStore] continuation in
            alertStore?.purge(before: Date(), completion: { _ in
                continuation.resume()
            })
        }
    }
}


private extension CarbStore {

    /// Errors if getting carb entries errors, or if deleting any individual entry errors.
    func deleteAllCarbEntries() async throws {
        try await withCheckedThrowingContinuation { continuation in
            getCarbEntries() { result in
                switch result {
                case .success(let entries):
                    self.deleteCarbEntries(entries[...], completion: { _ in
                        continuation.resume()
                    })
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deleteCarbEntries(_ entries: ArraySlice<StoredCarbEntry>, completion: @escaping (Error?) -> Void) {
        guard let entry = entries.first else {
            completion(nil)
            return
        }

        deleteCarbEntry(entry) { result in
            switch result {
            case .success(_):
                let remainder = entries.dropFirst()
                self.deleteCarbEntries(remainder, completion: completion)
            case .failure(let error):
                completion(error)
            }
        }
    }
}
