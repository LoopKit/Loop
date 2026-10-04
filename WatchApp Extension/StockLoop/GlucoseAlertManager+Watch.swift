//
//  GlucoseAlertManager+Watch.swift
//  WatchApp Extension
//
//  Lets stock `GlucoseAlertManager` compile on the wrist unchanged. Its predicted-low listener
//  waits for the phone's loop; the wrist calls `evaluatePredictedGlucose` after its own cycle.
//

import Foundation
import LoopAlgorithm

extension LoopDataManager {
    /// Read only by the listener above, which never fires here.
    nonisolated var predictedGlucose: [PredictedGlucoseValue]? { nil }
}
