//
//  GlucoseAlertManager+Watch.swift
//  WatchApp Extension
//
//  Lets stock `GlucoseAlertManager` compile on the watch unchanged. Its predicted-low listener
//  waits for the phone's loop; the wrist calls `evaluatePredictedGlucose` after its own cycle.
//

import Foundation
import LoopKit

/// Stock's alert text formats glucose through LoopKitUI's display preference, which the watch does not
/// have: the same formatting, in the user's unit as the phone sends it.
final class DisplayGlucosePreference {
    private let formatter: QuantityFormatter

    init(displayGlucoseUnit: LoopUnit) {
        formatter = QuantityFormatter(for: displayGlucoseUnit)
        formatter.numberFormatter.notANumberSymbol = "–"
    }

    func format(_ quantity: LoopQuantity, includeUnit: Bool = true) -> String {
        formatter.string(from: quantity, includeUnit: includeUnit) ?? formatter.numberFormatter.notANumberSymbol
    }
}

extension LoopDataManager {
    /// Read only by stock's predicted-low listener, which never fires here.
    nonisolated var predictedGlucose: [PredictedGlucoseValue]? { nil }
}
