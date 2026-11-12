//
//  SmartwatchManagerHost+RemoteActions.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopAlgorithm
import LoopCore
import LoopKit

/// Requests from the watch plugin: presets, boluses, alert mute and carbs. Each
/// gets the checks Loop applies to any request of that kind, such as its maximum
/// bolus, and only the current watch manager's requests are acted on. Whether the
/// watch may ask at all, and how fresh or frequent its requests must be, is the
/// plugin's own setting and policy. Every request and its outcome goes to the
/// device log.
extension SmartwatchManagerHost {
    /// Starts or ends a preset for a request from the watch, through the same path
    /// as remote overrides.
    func smartwatchManager(_ manager: SmartwatchManager, enactOverride action: SmartwatchPresetAction) async throws {
        let preset: TemporaryPreset?
        switch action {
        case .activate(let presetID):
            preset = settingsManager.settings.overridePresets.first { $0.id == presetID }
            logWatchRequest(manager, type: .receive, "Preset request: start \(preset.map { "\"\($0.name)\"" } ?? presetID)")
        case .cancel:
            preset = nil
            logWatchRequest(manager, type: .receive, "Preset request: end the running preset")
        }
        guard isCurrentWatch(manager) else {
            logWatchRequest(manager, type: .error, "Preset request rejected: notAllowed (the request isn't from the current watch)")
            throw SmartwatchPresetError.notAllowed
        }
        do {
            switch action {
            case .activate:
                guard let preset else {
                    logWatchRequest(manager, type: .error, "Preset request rejected: unknownPreset")
                    throw SmartwatchPresetError.unknownPreset
                }
                // Loop starts a preset by name; with another one of the same name it
                // could start that one instead of the one the watch chose.
                guard settingsManager.settings.overridePresets.filter({ $0.name == preset.name }).count == 1 else {
                    logWatchRequest(manager, type: .error, "Preset request rejected: another preset is also named \"\(preset.name)\"")
                    throw SmartwatchPresetError.failed("another preset has the same name")
                }
                try await startOverride(preset.name)
                logWatchRequest(manager, type: .delegateResponse, "Preset \"\(preset.name)\" started from the watch")
            case .cancel:
                try await cancelOverride()
                logWatchRequest(manager, type: .delegateResponse, "Preset ended from the watch")
            }
        } catch let error as SmartwatchPresetError {
            throw error
        } catch {
            logWatchRequest(manager, type: .error, "Preset request from the watch failed: \(error)")
            throw SmartwatchPresetError.failed(String(describing: error))
        }
        signal(.presets)
    }

    // MARK: - Watch bolus

    /// Delivers a bolus the plugin passed on, through the same path as remote
    /// boluses. Only for the current watch manager, at most Loop's maximum bolus,
    /// rounded to a volume the pump supports, and one at a time. Returns once the
    /// pump accepted the bolus (it may still be cancelled while it runs): a pump
    /// error, uncertain delivery included, is thrown as `.deliveryFailed`.
    func smartwatchManager(_ manager: SmartwatchManager, deliverBolus units: Double) async throws -> Double {
        logWatchRequest(manager, type: .receive, String(format: "Bolus request: %.3f U", units))
        let maximumBolus = settingsManager.loopSettings.maximumBolus
        let maximumText = maximumBolus.map { String(format: "maximum bolus %.2f U", $0) } ?? "no maximum bolus"
        guard isCurrentWatch(manager) else {
            logWatchRequest(manager, type: .error, "Bolus request rejected: notAllowed (the request isn't from the current watch)")
            throw SmartwatchBolusError.notAllowed
        }
        // Checked and set with no suspension in between, so two requests can't
        // both pass.
        guard !isDeliveringWatchBolus else {
            logWatchRequest(manager, type: .error, "Bolus request answered with inProgress: a watch bolus is still being delivered")
            throw SmartwatchBolusError.inProgress
        }
        guard units.isFinite, units > 0 else {
            logWatchRequest(manager, type: .error, "Bolus request rejected: invalidAmount")
            throw SmartwatchBolusError.invalidAmount
        }
        guard let maximumBolus else {
            logWatchRequest(manager, type: .error, "Bolus request rejected: no maximum bolus is set")
            throw SmartwatchBolusError.refusedByHost("no maximum bolus is set")
        }
        guard let pumpManager = deviceManager.pumpManager else {
            logWatchRequest(manager, type: .error, "Bolus request rejected: no pump")
            throw SmartwatchBolusError.refusedByHost("no pump")
        }
        let rounded = pumpManager.roundToSupportedBolusVolume(units: units)
        // Both the amount asked for and the one delivered, whichever way the pump rounds.
        guard units <= maximumBolus, rounded <= maximumBolus else {
            logWatchRequest(manager, type: .error, String(format: "Bolus request rejected: exceedsMaximumBolus (%.3f U, rounded %.3f U; %@)", units, rounded, maximumText))
            throw SmartwatchBolusError.exceedsMaximumBolus
        }
        guard rounded > 0 else {
            logWatchRequest(manager, type: .error, String(format: "Bolus request rejected: invalidAmount (%.3f U rounds to 0 U)", units))
            throw SmartwatchBolusError.invalidAmount
        }

        isDeliveringWatchBolus = true
        defer { isDeliveringWatchBolus = false }
        logWatchRequest(manager, type: .delegate, String(format: "Delivering watch bolus of %.3f U (%@)", rounded, maximumText))
        do {
            try await deliverBolus(rounded)
        } catch {
            logWatchRequest(manager, type: .error, "Watch bolus delivery failed: \(error)")
            signal(.loop)
            throw SmartwatchBolusError.deliveryFailed(String(describing: error))
        }
        logWatchRequest(manager, type: .delegateResponse, String(format: "Watch bolus of %.3f U delivered", rounded))
        signal(.loop)
        return rounded
    }

    /// What Loop would recommend with the carbs the user is about to add on the
    /// watch, without adding them: like the Apple Watch's recommendation for a
    /// potential carb entry, with the entry the watch's carbs become (dated now).
    /// The bolus itself is checked again when it's requested.
    func smartwatchManager(_ manager: SmartwatchManager, recommendBolusForCarbs grams: Double, absorptionTime: TimeInterval?) async throws -> Double {
        let absorptionTime = absorptionTime ?? LoopCoreConstants.defaultCarbAbsorptionTimes.medium
        // With 0 g it's the plugin's read for its bolus context, made after every
        // change: logged only when the answer changes. The watch's own questions
        // come with carbs and are always logged.
        let isContextRead = grams == 0
        if !isContextRead {
            logWatchRequest(manager, type: .receive, String(format: "Bolus recommendation request with %.0f g of carbs, %.0f min absorption", grams, absorptionTime / 60))
        }
        guard isCurrentWatch(manager) else {
            logWatchRequest(manager, type: .error, "Bolus recommendation refused: the request isn't from the current watch")
            throw SmartwatchBolusError.notAllowed
        }
        let maximumGrams = LoopConstants.maxCarbEntryQuantity.doubleValue(for: .gram)
        guard grams.isFinite, grams >= 0, grams <= maximumGrams,
              absorptionTime >= LoopConstants.minCarbAbsorptionTime, absorptionTime <= LoopConstants.maxCarbAbsorptionTime
        else {
            logWatchRequest(manager, type: .error, String(format: "Bolus recommendation refused: %.0f g over %.0f min isn't a valid carb entry (maximum %.0f g)", grams, absorptionTime / 60, maximumGrams))
            throw SmartwatchBolusError.invalidAmount
        }
        let potentialCarbEntry = grams > 0 ? NewCarbEntry(
            syncIdentifier: UUID().uuidString,
            quantity: LoopQuantity(unit: .gram, doubleValue: grams),
            startDate: Date(),
            foodType: nil,
            absorptionTime: absorptionTime
        ) : nil
        let recommendation: ManualBolusRecommendation?
        do {
            recommendation = try await loopDataManager.recommendManualBolus(carbEntryChange: potentialCarbEntry.map { .add($0) })
        } catch {
            logWatchRequest(manager, type: .error, "Bolus recommendation failed: \(error)")
            throw SmartwatchBolusError.refusedByHost(String(describing: error))
        }
        let recommended = max(0, recommendation?.amount ?? 0)
        let units = deviceManager.pumpManager?.roundToSupportedBolusVolume(units: recommended) ?? recommended
        let maximumBolus = settingsManager.loopSettings.maximumBolus
        if isContextRead, !Self.isNewContextRecommendation(units, last: &lastContextRecommendation) {
            return units
        }
        logWatchRequest(manager, type: .delegateResponse, String(format: "Bolus recommendation with %.0f g of carbs: %.2f U%@", grams, units, maximumBolus.map { String(format: " (maximum bolus %.2f U)", $0) } ?? ""))
        return units
    }

    /// Mutes Loop's alerts for a request from the watch, like Mute All Alerts in
    /// Settings: the duration is one Loop offers (the shortest that covers the
    /// request), and the mute shows on the phone with its Unmute button.
    func smartwatchManager(_ manager: SmartwatchManager, muteAlertsFor duration: TimeInterval) async throws -> Date {
        guard isCurrentWatch(manager) else {
            logWatchRequest(manager, type: .error, "Mute request from the watch refused: the request isn't from the current watch")
            throw SmartwatchAlertMuteError.notAllowed
        }
        guard duration > 0 else {
            alertMuter.unmuteAlerts()
            logWatchRequest(manager, type: .receive, "Alerts unmuted from the watch")
            return Date()
        }
        let allowed = AlertMuter.allowedDurations
        let muteDuration = allowed.first { $0 >= duration } ?? allowed[allowed.count - 1]
        alertMuter.configuration = AlertMuter.Configuration(startTime: Date(), duration: muteDuration)
        let end = alertMuter.configuration.mutingEndTime ?? Date(timeIntervalSinceNow: muteDuration)
        logWatchRequest(manager, type: .receive, String(format: "Alerts muted from the watch for %.0f min, until %@", muteDuration / 60, String(describing: end)))
        return end
    }

    /// Adds a carb entry the watch asked for, dated as given, through the same
    /// path as remote carbs (validation, notification, upload).
    func smartwatchManager(_ manager: SmartwatchManager, addCarbEntry grams: Double, absorptionTime: TimeInterval?, date: Date) async throws -> Double {
        let absorptionTime = absorptionTime ?? LoopCoreConstants.defaultCarbAbsorptionTimes.medium
        logWatchRequest(manager, type: .receive, String(format: "Carb entry request: %.0f g, %.0f min absorption, dated %@", grams, absorptionTime / 60, String(describing: date)))
        guard isCurrentWatch(manager) else {
            logWatchRequest(manager, type: .error, "Carb entry request rejected: notAllowed (the request isn't from the current watch)")
            throw SmartwatchCarbEntryError.notAllowed
        }
        guard grams.isFinite, grams > 0 else {
            logWatchRequest(manager, type: .error, "Carb entry request rejected: invalidAmount")
            throw SmartwatchCarbEntryError.invalidAmount
        }
        let maximumGrams = LoopConstants.maxCarbEntryQuantity.doubleValue(for: .gram)
        guard grams <= maximumGrams else {
            logWatchRequest(manager, type: .error, String(format: "Carb entry request rejected: exceedsMaximum (maximum %.0f g)", maximumGrams))
            throw SmartwatchCarbEntryError.exceedsMaximum
        }
        do {
            try await deliverCarbs(grams, date, absorptionTime)
        } catch {
            logWatchRequest(manager, type: .error, "Watch carb entry failed: \(error)")
            throw SmartwatchCarbEntryError.failed(String(describing: error))
        }
        logWatchRequest(manager, type: .delegateResponse, String(format: "Watch carb entry of %.0f g added", grams))
        signal(.loop)
        return grams
    }

    /// Whether the plugin's 0 g context read answered differently from last time,
    /// so it is logged; records the answer in `last` when it did.
    static func isNewContextRecommendation(_ units: Double, last: inout Double?) -> Bool {
        guard units != last else {
            return false
        }
        last = units
        return true
    }

    private func logWatchRequest(_ manager: SmartwatchManager, type: DeviceLogEntryType, _ message: String) {
        deviceManager.deviceLog.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: nil, type: type, message: message, completion: nil)
    }
}
