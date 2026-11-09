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
/// is checked against the plugin's capabilities, the user's Watch Permissions
/// and LoopKit's remote action rules, and goes to the device log.
extension SmartwatchManagerHost {
    /// Starts or ends a preset for a request from the watch, through the same path
    /// as remote overrides. Only while Allow Presets from Watch is on, and for
    /// requests confirmed in the last 30 seconds.
    func handleOverrideRequest(_ request: SmartwatchOverrideRequest, from manager: SmartwatchManager) async throws {
        let isCurrentWatch = deviceManager.smartwatchManager.map { ($0 as AnyObject) === (manager as AnyObject) } ?? false
        let preset: TemporaryPreset?
        switch request.action {
        case .activate(let presetID):
            preset = settingsManager.settings.overridePresets.first { $0.id == presetID }
            logWatchRequest(manager, type: .receive, "Preset request: start \(preset.map { "\"\($0.name)\"" } ?? presetID), confirmed at \(request.requestedAt)")
        case .cancel:
            preset = nil
            logWatchRequest(manager, type: .receive, "Preset request: end the running preset, confirmed at \(request.requestedAt)")
        }
        let refusal: String? = if !isCurrentWatch {
            "the request isn't from the current watch"
        } else if !manager.effectiveCapabilities.contains(.remoteOverride) {
            "this watch can't start presets (remoteOverride not declared or not requested)"
        } else if !UserDefaults.standard.allowWatchOverrides {
            "Allow Presets from Watch is off"
        } else {
            nil
        }
        if let refusal {
            logWatchRequest(manager, type: .error, "Preset request rejected: notAllowed (\(refusal))")
            throw SmartwatchPresetError.notAllowed
        }
        let age = Date().timeIntervalSince(request.requestedAt)
        guard manager.remoteActionLimits.requestWindow.contains(request.requestedAt, now: Date()) else {
            logWatchRequest(manager, type: .error, String(format: "Preset request rejected: expiredRequest (confirmed %.0f s ago)", age))
            throw SmartwatchPresetError.expiredRequest
        }
        do {
            switch request.action {
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
        refresh()
    }

    // MARK: - Watch bolus

    func bolusContextInputs(latestGlucoseDate: Date?) async -> SmartwatchBolusContextIssuer.Inputs {
        let recommendation = try? await loopDataManager.recommendManualBolus()
        return SmartwatchBolusContextIssuer.Inputs(
            recommendedBolus: recommendation?.amount,
            maximumBolus: settingsManager.loopSettings.maximumBolus,
            supportedBolusVolumes: deviceManager.pumpManager?.supportedBolusVolumes ?? [],
            latestGlucoseDate: latestGlucoseDate
        )
    }

    /// Delivers a bolus the plugin authenticated, if `SmartwatchBolusPolicy` allows it.
    /// Every request and its outcome goes to the device log.
    func handleBolusRequest(_ request: SmartwatchBolusRequest, from manager: SmartwatchManager) async throws -> Double {
        let isCurrentWatch = deviceManager.smartwatchManager.map { ($0 as AnyObject) === (manager as AnyObject) } ?? false
        logWatchRequest(manager, type: .receive, String(format: "%@ request: %.3f U, confirmed at %@, context %@", request.isForced ? "Forced bolus (recommendation not checked)" : "Bolus", request.units, String(describing: request.requestedAt), request.contextToken.uuidString))
        if bolusContextIssuer.isDelivering(request) {
            logWatchRequest(manager, type: .error, "Bolus request answered with inProgress: the same bolus is still being delivered")
            throw SmartwatchBolusError.inProgress
        }

        let policy = SmartwatchBolusPolicy(
            limits: manager.remoteActionLimits.bolusPolicyLimits,
            isAllowed: UserDefaults.standard.allowWatchBolus && isCurrentWatch && manager.effectiveCapabilities.contains(.remoteBolus),
            currentContext: bolusContextIssuer.current,
            latestGlucoseDate: glucoseStore.latestGlucose?.startDate,
            recentDeliveries: UserDefaults.standard.watchBolusDeliveries,
            roundToSupportedVolume: { [deviceManager] units in
                deviceManager.pumpManager?.roundToSupportedBolusVolume(units: units) ?? units
            }
        )
        let units: Double
        switch policy.evaluate(request, now: Date()) {
        case .failure(let error):
            let units = { (value: Double?) in value.map { String(format: "%.2f U", $0) } ?? "none" }
            let notAllowedReason: String = if !isCurrentWatch {
                "the request isn't from the current watch; "
            } else if !manager.effectiveCapabilities.contains(.remoteBolus) {
                "this watch can't request boluses (remoteBolus not declared or not requested); "
            } else if !UserDefaults.standard.allowWatchBolus {
                "Allow Boluses from Watch is off; "
            } else {
                ""
            }
            let glucoseAge = glucoseStore.latestGlucose.map { String(format: "newest glucose %.0f min ago; ", Date().timeIntervalSince($0.startDate) / 60) } ?? "no glucose; "
            logWatchRequest(manager, type: .error, "Bolus request rejected: \(error) (\(error == .notAllowed ? notAllowedReason : "")\(error == .noRecentGlucose ? glucoseAge : "")requested \(units(request.units)), Loop recommends \(units(bolusContextIssuer.current?.recommendedBolus ?? 0)), maximum bolus \(units(bolusContextIssuer.current?.maximumBolus)))")
            throw error
        case .success(let allowed):
            units = allowed
        }

        bolusContextIssuer.beginDelivery(of: request)
        defer { bolusContextIssuer.endDelivery() }
        logWatchRequest(manager, type: .delegate, String(format: "Delivering watch bolus of %.3f U", units))
        // Counted for the time between watch boluses from here, whether or not the
        // pump reports it delivered: a failure can be uncertain (the pump lost
        // contact mid-bolus), and a resend at once could give it twice. Only a
        // delivered bolus counts toward the daily total.
        let attemptedAt = Date()
        UserDefaults.standard.watchBolusDeliveries = Self.bolusAttempted(at: attemptedAt, in: UserDefaults.standard.watchBolusDeliveries)
        do {
            try await deliverBolus(units)
        } catch {
            logWatchRequest(manager, type: .error, "Watch bolus delivery failed: \(error)")
            refresh()
            throw SmartwatchBolusError.deliveryFailed(String(describing: error))
        }
        UserDefaults.standard.watchBolusDeliveries = Self.bolusDelivered(units, attemptedAt: attemptedAt, in: UserDefaults.standard.watchBolusDeliveries)
        logWatchRequest(manager, type: .delegateResponse, String(format: "Watch bolus of %.3f U delivered", units))
        refresh()
        return units
    }

    /// What Loop would recommend with the carbs the user is about to add on the
    /// watch, without adding them: like the Apple Watch's recommendation for a
    /// potential carb entry, with the entry the watch's carbs become (medium
    /// absorption, dated now). Only while the watch may request boluses and
    /// glucose is recent; the bolus itself is checked again after the carbs.
    func handleBolusRecommendationRequest(_ request: SmartwatchBolusRecommendationRequest, from manager: SmartwatchManager) async throws -> SmartwatchBolusRecommendation {
        let grams = request.grams
        let isCurrentWatch = deviceManager.smartwatchManager.map { ($0 as AnyObject) === (manager as AnyObject) } ?? false
        logWatchRequest(manager, type: .receive, String(format: "Bolus recommendation request with %.0f g of %@ carbs", grams, (request.absorption ?? .medium).rawValue))
        let refusal: String? = if !isCurrentWatch {
            "the request isn't from the current watch"
        } else if !manager.effectiveCapabilities.contains(.remoteBolus) {
            "this watch can't request boluses (remoteBolus not declared or not requested)"
        } else if !UserDefaults.standard.allowWatchBolus {
            "Allow Boluses from Watch is off"
        } else {
            nil
        }
        if let refusal {
            logWatchRequest(manager, type: .error, "Bolus recommendation refused: \(refusal)")
            throw SmartwatchBolusError.notAllowed
        }
        let maximumGlucoseAge = manager.remoteActionLimits.bolusPolicyLimits.maximumGlucoseAge
        guard let latestGlucoseDate = glucoseStore.latestGlucose?.startDate, Date().timeIntervalSince(latestGlucoseDate) <= maximumGlucoseAge else {
            logWatchRequest(manager, type: .error, "Bolus recommendation refused: no glucose in the last \(Int(maximumGlucoseAge / 60)) minutes")
            throw SmartwatchBolusError.noRecentGlucose
        }
        let maximumGrams = LoopConstants.maxCarbEntryQuantity.doubleValue(for: .gram)
        guard grams.isFinite, grams >= 0, grams <= maximumGrams else {
            logWatchRequest(manager, type: .error, String(format: "Bolus recommendation refused: %.0f g isn't a valid carb entry (maximum %.0f g)", grams, maximumGrams))
            throw SmartwatchBolusError.invalidAmount
        }
        let absorptionTime = Self.absorptionTime(request.absorption)
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
        // Rounded as the bolus check rounds the recommendation it caps at.
        let recommended = max(0, recommendation?.amount ?? 0)
        let units = deviceManager.pumpManager?.roundToSupportedBolusVolume(units: recommended) ?? recommended
        let maximumBolus = settingsManager.loopSettings.maximumBolus
        logWatchRequest(manager, type: .delegateResponse, String(format: "Bolus recommendation with %.0f g of carbs: %.2f U%@", grams, units, maximumBolus.map { String(format: " (maximum bolus %.2f U)", $0) } ?? ""))
        return SmartwatchBolusRecommendation(units: units, grams: grams, maximumBolus: maximumBolus, issuedAt: Date())
    }

    /// Mutes Loop's alerts for a request from the watch, like Mute All Alerts in
    /// Settings: the duration is one Loop offers (the shortest that covers the
    /// request), and the mute shows on the phone with its Unmute button. Only
    /// while Allow Mute from Watch is on.
    func handleAlertMuteRequest(_ request: SmartwatchAlertMuteRequest, from manager: SmartwatchManager) throws -> Date {
        let duration = request.duration
        let isCurrentWatch = deviceManager.smartwatchManager.map { ($0 as AnyObject) === (manager as AnyObject) } ?? false
        guard isCurrentWatch, manager.effectiveCapabilities.contains(.remoteMute) else {
            logWatchRequest(manager, type: .error, "Mute request from the watch refused: this watch can't mute alerts (remoteMute not declared or not requested)")
            throw SmartwatchAlertMuteError.notAllowed
        }
        guard UserDefaults.standard.allowWatchMute else {
            logWatchRequest(manager, type: .error, "Mute request from the watch refused: Allow Mute from Watch is off")
            throw SmartwatchAlertMuteError.notAllowed
        }
        guard manager.remoteActionLimits.requestWindow.contains(request.requestedAt, now: Date()) else {
            logWatchRequest(manager, type: .error, String(format: "Mute request from the watch refused: expiredRequest (confirmed %.0f s ago)", Date().timeIntervalSince(request.requestedAt)))
            throw SmartwatchAlertMuteError.expiredRequest
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

    /// Adds a carb entry the watch asked for, if LoopKit's `SmartwatchCarbEntryPolicy`
    /// allows it, through the same path as remote carbs (notification, upload).
    func handleCarbEntryRequest(_ request: SmartwatchCarbEntryRequest, from manager: SmartwatchManager) async throws -> Double {
        let grams = request.grams
        let isCurrentWatch = deviceManager.smartwatchManager.map { ($0 as AnyObject) === (manager as AnyObject) } ?? false
        logWatchRequest(manager, type: .receive, String(format: "Carb entry request: %.0f g, %@ absorption, confirmed at %@", grams, (request.absorption ?? .medium).rawValue, String(describing: request.requestedAt)))
        let refusal: String? = if !isCurrentWatch {
            "the request isn't from the current watch"
        } else if !manager.effectiveCapabilities.contains(.remoteCarbs) {
            "this watch can't add carbs (remoteCarbs not declared or not requested)"
        } else if !UserDefaults.standard.allowWatchCarbs {
            "Allow Carbs from Watch is off"
        } else {
            nil
        }
        let previousEntry = UserDefaults.standard.lastWatchCarbEntry
        let policy = SmartwatchCarbEntryPolicy(
            limits: manager.remoteActionLimits.carbEntryPolicyLimits,
            isAllowed: refusal == nil,
            maximumGrams: LoopConstants.maxCarbEntryQuantity.doubleValue(for: .gram),
            lastEntry: previousEntry
        )
        if case .failure(let error) = policy.evaluate(request, now: Date()) {
            logWatchRequest(manager, type: .error, "Carb entry request rejected: \(error)\(refusal.map { " (\($0))" } ?? "")")
            throw error
        }
        // Take the slot before storing, so a resend that arrives meanwhile is
        // rate limited instead of adding the carbs a second time.
        UserDefaults.standard.lastWatchCarbEntry = Date()
        do {
            try await deliverCarbs(grams, request.requestedAt, Self.absorptionTime(request.absorption))
        } catch {
            UserDefaults.standard.lastWatchCarbEntry = previousEntry
            logWatchRequest(manager, type: .error, "Watch carb entry failed: \(error)")
            throw SmartwatchCarbEntryError.failed(String(describing: error))
        }
        logWatchRequest(manager, type: .delegateResponse, String(format: "Watch carb entry of %.0f g added", grams))
        refresh()
        return grams
    }

    /// Loop's absorption time for the watch's choice: fast, medium or slow as
    /// in carb entry; medium when the watch didn't say (older watches).
    /// The watch boluses `SmartwatchBolusPolicy` counts, with an attempt at `date`:
    /// 0 U, so it counts for the time between boluses but not the daily total.
    static func bolusAttempted(at date: Date, in deliveries: [SmartwatchBolusPolicy.Delivery]) -> [SmartwatchBolusPolicy.Delivery] {
        deliveries + [SmartwatchBolusPolicy.Delivery(date: date, units: 0)]
    }

    /// The attempt at `attemptedAt` delivered `units`: they count toward the daily total too.
    static func bolusDelivered(_ units: Double, attemptedAt: Date, in deliveries: [SmartwatchBolusPolicy.Delivery]) -> [SmartwatchBolusPolicy.Delivery] {
        deliveries.filter { $0 != SmartwatchBolusPolicy.Delivery(date: attemptedAt, units: 0) }
            + [SmartwatchBolusPolicy.Delivery(date: attemptedAt, units: units)]
    }

    static func absorptionTime(_ absorption: SmartwatchCarbAbsorption?) -> TimeInterval {
        switch absorption {
        case .fast: LoopCoreConstants.defaultCarbAbsorptionTimes.fast
        case .slow: LoopCoreConstants.defaultCarbAbsorptionTimes.slow
        case .medium, nil: LoopCoreConstants.defaultCarbAbsorptionTimes.medium
        }
    }

    private func logWatchRequest(_ manager: SmartwatchManager, type: DeviceLogEntryType, _ message: String) {
        deviceManager.deviceLog.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: nil, type: type, message: message, completion: nil)
    }
}
