//
//  LocalTestingScenariosManager.swift
//  Loop
//
//  Created by Michael Pangburn on 4/22/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopTestingKit
import OSLog

final class LocalTestingScenariosManager: TestingScenariosManagerRequirements, DirectoryObserver {
    
    unowned let deviceManager: DeviceDataManager
    unowned let supportManager: SupportManager

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
    
    var pluginManager: PluginManager {
        deviceManager.pluginManager
    }

    init(deviceManager: DeviceDataManager, supportManager: SupportManager) {
        guard FeatureFlags.scenariosEnabled else {
            fatalError("\(#function) should be invoked only when scenarios are enabled")
        }

        self.deviceManager = deviceManager
        self.supportManager = supportManager
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
