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

protocol CGMStalenessMonitorDelegate: AnyObject {
    func getLatestCGMGlucose(since: Date, completion: @escaping (_ result: Swift.Result<StoredGlucoseSample?, Error>) -> Void)
}

class CGMStalenessMonitor {
    
    private let log = DiagnosticLog(category: "CGMStalenessMonitor")
    
    private var cgmStalenessTimer: Timer?
    
    weak var delegate: CGMStalenessMonitorDelegate? = nil {
        didSet {
            if delegate != nil {
                checkCGMStaleness()
            }
        }
    }

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
        if cgmDataAge < LoopCoreConstants.inputDataRecencyInterval {
            self.cgmDataIsStale = false
            self.updateCGMStalenessTimer(expiration: mostRecentGlucose.addingTimeInterval(LoopCoreConstants.inputDataRecencyInterval))
        } else {
            self.cgmDataIsStale = true
        }
    }
    
    private func updateCGMStalenessTimer(expiration: Date) {
        self.log.debug("Updating CGM Staleness timer to fire at %{public}@", String(describing: expiration))
        cgmStalenessTimer?.invalidate()
        cgmStalenessTimer = Timer.scheduledTimer(withTimeInterval: expiration.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            self?.log.debug("cgmStalenessTimer fired")
            self?.checkCGMStaleness()
        }
        cgmStalenessTimer?.tolerance = CGMStalenessMonitor.cgmStalenessTimerTolerance
    }
    
    private func checkCGMStaleness() {
        delegate?.getLatestCGMGlucose(since: Date(timeIntervalSinceNow: -LoopCoreConstants.inputDataRecencyInterval)) { (result) in
            DispatchQueue.main.async {
                self.log.debug("Fetched latest CGM Glucose for checkCGMStaleness: %{public}@", String(describing: result))
                switch result {
                case .success(let sample):
                    if let sample = sample {
                        self.cgmDataIsStale = false
                        self.updateCGMStalenessTimer(expiration: sample.startDate.addingTimeInterval(LoopCoreConstants.inputDataRecencyInterval + CGMStalenessMonitor.cgmStalenessTimerTolerance))
                    } else {
                        self.cgmDataIsStale = true
                    }
                case .failure(let error):
                    self.log.error("Unable to get latest CGM clucose: %{public}@ ", String(describing: error))
                    // Some kind of system error; check again in 5 minutes
                    self.updateCGMStalenessTimer(expiration: Date(timeIntervalSinceNow: .minutes(5)))
                }
            }
        }
    }
}
