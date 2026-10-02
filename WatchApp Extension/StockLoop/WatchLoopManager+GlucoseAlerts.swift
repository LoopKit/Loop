//
//  WatchLoopManager+GlucoseAlerts.swift
//  WatchApp Extension
//
//  Stock `GlucoseAlertManager` on the wrist during a loan, configured from the phone's settings
//  and fed the watch's own readings and forecast. Alerts go out through `issueAlert`.
//

import Foundation
import LoopKit
import LoopAlgorithm

extension WatchLoopManager {
    /// Built for each loan from the grant; nil data (an older phone) leaves the wrist without them.
    @MainActor @discardableResult
    func configureGlucoseAlerts(from data: Data?) -> String {
        guard let settings = GlucoseAlertSettings(encoded: data) else {
            glucoseAlerts = nil
            let note = data == nil
                ? "glucose alarms UNAVAILABLE on the wrist this loan — the phone sent no glucose alert settings (older phone)"
                : "glucose alarms UNAVAILABLE on the wrist this loan — the phone's glucose alert settings could not be read"
            SportLog.event("alert", note)
            return note
        }
        let manager = GlucoseAlertManager(alertIssuer: self, userDefaults: defaults)
        manager.adopt(settings)
        glucoseAlerts = manager

        let c = manager.activeConfiguration()
        func level(_ on: Bool, _ mgdl: Double) -> String { on ? "\(Int(mgdl))" : "off" }
        var note = "glucose alarms ON the wrist (\(manager.activeProfile().name)) — urgent low \(level(c.urgentLowEnabled, c.urgentLowThresholdMgDL)) · low \(level(c.lowEnabled, c.lowThresholdMgDL)) · high \(level(c.highEnabled, c.highThresholdMgDL)) · predicted low \(level(c.predictedLowEnabled, c.predictedLowThresholdMgDL)) mg/dL"
        if !manager.effectiveLoopAlertsEnabled {
            note += " — but the phone leaves glucose alerts to the CGM's own app, so none will sound here"
        }
        SportLog.event("alert", note)
        return note
    }

    @MainActor
    func clearGlucoseAlerts() {
        glucoseAlerts = nil
    }

    /// The stock rules on the watch's own readings, as the phone runs them on its CGM's.
    @discardableResult
    func evaluateGlucoseAlerts(_ samples: [NewGlucoseSample]) -> Task<Void, Never> {
        let now = self.now()
        return Task { @MainActor in
            await self.glucoseAlerts?.evaluate(samples: samples, now: now)
        }
    }

    /// Stock evaluates predicted low after each phone cycle; the wrist after each of its own.
    @discardableResult
    func evaluatePredictedLowAlert(_ predicted: [PredictedGlucoseValue]?) -> Task<Void, Never>? {
        guard let predicted else { return nil }
        let now = self.now()
        return Task { @MainActor in
            await self.glucoseAlerts?.evaluatePredictedGlucose(predicted, now: now)
        }
    }
}
