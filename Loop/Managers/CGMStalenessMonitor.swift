//
//  CGMStalenessMonitor.swift
//  Loop
//
//  Created by Pete Schwamb on 10/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopCore
import LoopAlgorithm

protocol CGMStalenessMonitorDelegate: AnyObject {
    func getLatestCGMGlucose(since: Date) async throws -> StoredGlucoseSample?
}

class CGMStalenessMonitor {
    
    private let log = DiagnosticLog(category: "CGMStalenessMonitor")
    
    private var cgmStalenessTimer: Timer?
    
    weak var delegate: CGMStalenessMonitorDelegate?

    @Published var cgmDataIsStale: Bool = true {
        didSet {
            self.log.debug("cgmDataIsStale: %{public}@", String(describing: cgmDataIsStale))
        }
    }

    private static var cgmStalenessTimerTolerance: TimeInterval = .seconds(10)
    
    public func cgmGlucoseSamplesAvailable(_ samples: [NewGlucoseSample]) {
        guard samples.count > 0 else {
            return
        }
        
        let mostRecentGlucose = samples.map { $0.date }.max()!
        let cgmDataAge = -mostRecentGlucose.timeIntervalSinceNow
        if cgmDataAge < LoopAlgorithm.inputDataRecencyInterval {
            self.cgmDataIsStale = false
            self.updateCGMStalenessTimer(expiration: mostRecentGlucose.addingTimeInterval(LoopAlgorithm.inputDataRecencyInterval))
        } else {
            self.cgmDataIsStale = true
        }
    }
    
    private func updateCGMStalenessTimer(expiration: Date) {
        self.log.debug("Updating CGM Staleness timer to fire at %{public}@", String(describing: expiration))
        cgmStalenessTimer?.invalidate()
        cgmStalenessTimer = Timer.scheduledTimer(withTimeInterval: expiration.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            self?.log.debug("cgmStalenessTimer fired")
            Task {
                await self?.checkCGMStaleness()
            }
        }
        cgmStalenessTimer?.tolerance = CGMStalenessMonitor.cgmStalenessTimerTolerance
    }
    
    func checkCGMStaleness() async {
        do {
            let sample = try await delegate?.getLatestCGMGlucose(since: Date(timeIntervalSinceNow: -LoopAlgorithm.inputDataRecencyInterval))
            self.log.debug("Fetched latest CGM Glucose for checkCGMStaleness: %{public}@", String(describing: sample))
            if let sample = sample {
                self.cgmDataIsStale = false
                self.updateCGMStalenessTimer(expiration: sample.startDate.addingTimeInterval(LoopAlgorithm.inputDataRecencyInterval + CGMStalenessMonitor.cgmStalenessTimerTolerance))
            } else {
                self.cgmDataIsStale = true
            }
        } catch {
            self.log.error("Unable to get latest CGM clucose: %{public}@ ", String(describing: error))
            // Some kind of system error; check again in 5 minutes
            self.updateCGMStalenessTimer(expiration: Date(timeIntervalSinceNow: .minutes(5)))
        }
    }
}
