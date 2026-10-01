//
//  WatchDoseEnactor.swift
//  WatchApp Extension
//
//  Copy of Loop/Managers/DoseEnactor.swift, logging via os.log. Keep in step with the original.
//

import Foundation
import LoopKit
import LoopAlgorithm
import os.log

class WatchDoseEnactor {
    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "DoseEnactor")

    /// Throws whatever the pump manager throws; the caller turns that into `.enactFailed`, which
    /// is what holds the dead-man watchdog for the cycle.
    func enact(decisionId: UUID?, bolus: Double?, tempBasal: TempBasalRecommendation?, with pumpManager: PumpManager) async throws {
        if let tempBasal {
            self.log.default("Enacting recommended basal change")
            try await pumpManager.enactTempBasal(decisionId: decisionId, unitsPerHour: tempBasal.unitsPerHour, for: tempBasal.duration)
        }
        if let bolus, bolus > 0 {
            self.log.default("Enacting recommended bolus dose")
            try await pumpManager.enactBolus(decisionId: decisionId, units: bolus, activationType: .automatic)
        }
    }
}
