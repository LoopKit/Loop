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

protocol TestingScenariosManager: AnyObject {
    var delegate: TestingScenariosManagerDelegate? { get set }
    var activeScenarioURL: URL? { get }
    var scenarioURLs: [URL] { get }
    var supportManager: SupportManager { get }
    func loadScenario(from url: URL, completion: @escaping (Error?) -> Void)
    func loadScenario(from url: URL, advancedByLoopIterations iterations: Int, completion: @escaping (Error?) -> Void)
    func loadScenario(from url: URL, rewoundByLoopIterations iterations: Int, completion: @escaping (Error?) -> Void)
    func stepActiveScenarioBackward(completion: @escaping (Error?) -> Void)
    func stepActiveScenarioForward(completion: @escaping (Error?) -> Void)
}

/// Describes the requirements necessary to implement TestingScenariosManager
protocol TestingScenariosManagerRequirements: TestingScenariosManager {
    var deviceManager: DeviceDataManager { get }
    var activeScenarioURL: URL? { get set }
    var activeScenario: TestingScenario? { get set }
    var log: DiagnosticLog { get }
    func fetchScenario(from url: URL, completion: @escaping (Result<TestingScenario, Error>) -> Void)
}

// MARK: - TestingScenarioManager requirement implementations

extension TestingScenariosManagerRequirements {
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

extension TestingScenariosManagerRequirements {
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
                        self.log.debug("@{public}%", successLogMessage)
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
        deviceManager.loopManager.getLoopState { _, state in
            var scenario = scenario
            guard let recommendedDose = state.recommendedAutomaticDose?.recommendation else {
                scenario.stepForward(by: .minutes(5))
                completion(scenario)
                return
            }
            
            if let basalAdjustment = recommendedDose.basalAdjustment {
                scenario.stepForward(unitsPerHour: basalAdjustment.unitsPerHour, duration: basalAdjustment.duration)
            }
            completion(scenario)
        }
    }

    private func loadScenario(_ scenario: TestingScenario, rewoundByLoopIterations iterations: Int, completion: @escaping (Error?) -> Void) {
        assert(iterations > 0)

        let offset = Double(iterations) * .minutes(5)
        var scenario = scenario
        scenario.stepBackward(by: offset)
        loadScenario(scenario, completion: completion)
    }

    private func loadScenario(_ scenario: TestingScenario, completion: @escaping (Error?) -> Void) {
        guard FeatureFlags.scenariosEnabled else {
            fatalError("\(#function) should be invoked only when scenarios are enabled")
        }

        func bail(with error: Error) {
            activeScenarioURL = nil
            log.error("%{public}@", String(describing: error))
            completion(error)
        }
        
        let instance = scenario.instantiate()
        
        var testingCGMManager: TestingCGMManager?
        var testingPumpManager: TestingPumpManager?
        
        if instance.hasCGMData {
            if let cgmManager = deviceManager.cgmManager as? TestingCGMManager {
                if instance.shouldReloadManager?.cgm == true {
                    testingCGMManager = reloadCGMManager(withIdentifier: cgmManager.managerIdentifier)
                } else {
                    testingCGMManager = cgmManager
                }
            } else {
                bail(with: ScenarioLoadingError.noTestingCGMManagerEnabled)
                return
            }
        }
        
        if instance.hasPumpData {
            if let pumpManager = deviceManager.pumpManager as? TestingPumpManager {
                if instance.shouldReloadManager?.pump == true {
                    testingPumpManager = reloadPumpManager(withIdentifier: pumpManager.managerIdentifier)
                } else {
                    testingPumpManager = pumpManager
                }
            } else {
                bail(with: ScenarioLoadingError.noTestingPumpManagerEnabled)
                return
            }
        }

        wipeExistingData { error in
            guard error == nil else {
                bail(with: error!)
                return
            }

            self.deviceManager.carbStore.addCarbEntries(instance.carbEntries) { result in
                switch result {
                case .success(_):
                    testingPumpManager?.reservoirFillFraction = 1.0
                    testingPumpManager?.injectPumpEvents(instance.pumpEvents)
                    testingCGMManager?.injectGlucoseSamples(instance.pastGlucoseSamples, futureSamples: instance.futureGlucoseSamples)
                    self.activeScenario = scenario
                    completion(nil)
                case .failure(let error):
                    bail(with: error)
                }
            }
        }
        
        instance.deviceActions.forEach { [testingCGMManager, testingPumpManager] action in
            if testingCGMManager?.managerIdentifier == action.managerIdentifier {
                testingCGMManager?.trigger(action: action)
            } else if testingPumpManager?.managerIdentifier == action.managerIdentifier {
                testingPumpManager?.trigger(action: action)
            }
        }
    }
    
    private func reloadPumpManager(withIdentifier pumpManagerIdentifier: String) -> TestingPumpManager {
        deviceManager.pumpManager = nil
        guard let maximumBasalRate = deviceManager.loopManager.settings.maximumBasalRatePerHour,
              let maxBolus = deviceManager.loopManager.settings.maximumBolus,
              let basalSchedule = deviceManager.loopManager.settings.basalRateSchedule else
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
    
    private func reloadCGMManager(withIdentifier cgmManagerIdentifier: String) -> TestingCGMManager {
        deviceManager.cgmManager = nil
        let result = deviceManager.setupCGMManager(withIdentifier: cgmManagerIdentifier, prefersToSkipUserInteraction: true)
        switch result {
        case .success(let setupUIResult):
            switch setupUIResult {
            case .createdAndOnboarded(let cgmManager):
                return cgmManager as! TestingCGMManager
            default:
                fatalError("Failed to reload CGM manager. UI interaction required for setup")
            }
        default:
            fatalError("Failed to reload CGM manager. Setup failed")
        }
    }

    private func wipeExistingData(completion: @escaping (Error?) -> Void) {
        guard FeatureFlags.scenariosEnabled else {
            fatalError("\(#function) should be invoked only when scenarios are enabled")
        }
        
        deviceManager.deleteTestingPumpData { error in
            guard error == nil else {
                completion(error!)
                return
            }

            self.deviceManager.deleteTestingCGMData { error in
                guard error == nil else {
                    completion(error!)
                    return
                }

                self.deviceManager.carbStore.deleteAllCarbEntries() { error in
                    guard error == nil else {
                        completion(error!)
                        return
                    }
                    
                    self.deviceManager.alertManager.alertStore.purge(before: Date(), completion: completion)
                }
            }
        }
    }
}


private extension CarbStore {
    /// Errors if adding any individual entry errors.
    func addCarbEntries(_ entries: [NewCarbEntry], completion: @escaping (CarbStoreResult<[StoredCarbEntry]>) -> Void) {
        addCarbEntries(entries[...], completion: completion)
    }

    private func addCarbEntries(_ entries: ArraySlice<NewCarbEntry>, completion: @escaping (CarbStoreResult<[StoredCarbEntry]>) -> Void) {
        guard let entry = entries.first else {
            completion(.success([]))
            return
        }

        addCarbEntry(entry) { individualResult in
            switch individualResult {
            case .success(let entry):
                let remainder = entries.dropFirst()
                self.addCarbEntries(remainder) { collectiveResult in
                    switch collectiveResult {
                    case .success(let entries):
                        completion(.success([entry] + entries))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Errors if getting carb entries errors, or if deleting any individual entry errors.
    func deleteAllCarbEntries(completion: @escaping (CarbStoreError?) -> Void) {
        getCarbEntries() { result in
            switch result {
            case .success(let entries):
                self.deleteCarbEntries(entries[...], completion: completion)
            case .failure(let error):
                completion(error)
            }
        }
    }

    private func deleteCarbEntries(_ entries: ArraySlice<StoredCarbEntry>, completion: @escaping (CarbStoreError?) -> Void) {
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
