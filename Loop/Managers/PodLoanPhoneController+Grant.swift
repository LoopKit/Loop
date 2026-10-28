//
//  PodLoanPhoneController+Grant.swift
//  Loop
//
//  Lending the pod: honouring or denying a request, releasing the pod cleanly, and building
//  the therapy copy the watch doses from (shared by the live grant and the standing copy).
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications

extension PodLoanPhoneController {
    /// The watch is asking for the pod.
    func handleRequest(_ request: LoanRequest) {
        // Age first: an expired request has a sender that has moved on.
        if let sentAt = request.sentAt {
            let age = deps.now().timeIntervalSince(sentAt)
            if age > Self.requestTTL {
                PhoneLog.event("loan", String(format: "ignored a Start request sent %.0f s ago, older than %.0f s", age, Self.requestTTL))
                return
            }
        }

        if let id = request.requestID, id == lastRequestID,
           let seenAt = lastRequestAt,
           deps.now().timeIntervalSince(seenAt) < Self.requestDedupeWindow {
            return
        }
        if let id = request.requestID {
            lastRequestID = id
            lastRequestAt = deps.now()
        }

        if !persisted.watchUsesSportMode {
            updateState { $0.watchUsesSportMode = true }
        }
        watchKnownEpoch = request.knownEpoch
        // A grant is mid-flight: the phone has already paused dosing and is waiting on the pod. A second
        // Start (the same one by its second route, or a second tap) is answered by that grant.
        guard !grantInFlight else {
            return
        }
        guard state == .owner else {
            switch state {
            // A previous attempt never finished: recover to owner and grant afresh.
            case .grantOffered, .reconciling, .reclaimPending:
                forceReclaimToOwner(reason: "a new Start request came in state \(state.rawValue)")
                beginGrant()
            // A live loan is not stale state. Take it back properly and let the user ask again.
            case .loaned:
                reclaimNow()
                deny("Ending the previous Sport Mode session. Tap Start again in a few seconds.")
            case .owner:
                break
            }
            return
        }
        beginGrant()
    }

    /// Refuse, with a reason the glance can show.
    func deny(_ reason: String) {
        handbackDiag(epoch, "refused the watch's Start: \(reason)")
        sendMessage(.denied(LoanDenied(reason: reason)))
    }

    /// Every refusal is delivered, cheapest first. Not gated on isWatchAppInstalled, which lags.
    /// The first irreversible step is cancelling the phone's temp, in `continueGrant`.
    func beginGrant() {
        guard let pump = deps.pumpManager() else {
            deny("No pump is set up on the phone.")
            return
        }
        // Handing over needs exclusive control and the delivered total both sides audit against.
        guard let control = pump as? ExclusiveDeviceControl, pump is PumpDeliveryOdometer else {
            deny("This pump doesn't support Sport Mode.")
            return
        }
        guard deps.watchReadsCGM() else {
            deny("Sport Mode needs the watch to read the CGM. Turn on Read on Apple Watch in the CGM's settings on the iPhone.")
            return
        }

        // A grant supersedes an inferred loan; the radio comes back first.
        if yieldingToInferredLoan {
            clearInferredLoanYield(reason: "a new Start request replaces it")
            reclaimPodConnection()
        }

        // Nobody takes the pod while it is giving a bolus (transfer G): the looper tries again after it.
        if let bolus = pump.status.bolusState.underWay {
            deny(LoanControl.bolusRefusal(bolus, now: deps.now()))
            return
        }

        // Refuse until the last reclaim's pod round-trip has verified.
        if let started = reclaimStartedAt,
           deps.now().timeIntervalSince(started) < Self.reclaimSettleTimeout,
           reclaimVerifiedAt == nil {
            deny("The iPhone is still reconnecting to the pod. Try again in a few seconds.")
            attemptReclaimVerificationNow(started: started)
            return
        }

        let settings = deps.settings()

        let loanSettings = settings
        // Deny on anything missing rather than letting the watch invent it.
        guard settings.basalRateSchedule != nil,
              settings.insulinSensitivitySchedule != nil,
              settings.carbRatioSchedule != nil,
              settings.glucoseTargetRangeSchedule != nil,
              settings.maximumBasalRatePerHour != nil,
              settings.maximumBolus != nil else {
            deny("Therapy settings are incomplete; the watch can't dose without them.")
            return
        }

        // Cancel the phone's temp and wait for the pod to acknowledge it before releasing. From here the
        // phone's own loop doses nothing: a temp set between the cancel and the release went
        // unacknowledged, and the driver's recovery then dialed the lent pod.
        grantInFlight = true
        deps.cancelTempBasalForGrant { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.grantInFlight = false
                if let error = error {
                    self.log.error("could not cancel this phone's temp before lending the pod: %{public}@", String(describing: error))
                    self.deny("The iPhone couldn't reach the pod and kept it. Try again.")
                    return
                }
                self.continueGrant(settings: settings, loanSettings: loanSettings, pump: pump, control: control)
            }
        }
    }

    /// One-way once the driver lets the link go: odometer origin, link released, epoch advanced.
    private func continueGrant(settings: LoopSettings, loanSettings: LoopSettings,
                               pump: PumpManager, control: ExclusiveDeviceControl) {
                let handedOverAt = deps.now()

        // This loan's origin; the previous loan's takeover reading is cleared with it.
        let deliveredAtGrant = (pump as? PumpDeliveryOdometer)?.deliveredUnits?.units

        // Above anything the watch knows: a loan it started alone may have run past this phone's count.
        let releaseEpoch = max(epoch, watchKnownEpoch ?? 0) + 1
        handbackDiag(releaseEpoch, "lending the pod to the watch")
        control.releaseControl()
        // The pod driver keeps the pod while a command to it is unconfirmed: the Start is refused.
        guard control.isControlReleased else {
            deny(LoanControl.unconfirmedCommandRefusal)
            return
        }
        deps.pumpControlChanged(true)

        // New epoch, empty dedup state, this loan's anchors: one save, before the grant goes out.
        let previous = state
        updateState {
            $0.epoch = releaseEpoch
            $0.phase = .grantOffered
            $0.committedCursor = 0
            $0.committedIDs = []
            $0.loanStartedAt = handedOverAt
            if let deliveredAtGrant { $0.ledger.last = .init(units: deliveredAtGrant, at: handedOverAt) }
            $0.holdRenewedAt = handedOverAt
        }
        stateDidChange(from: previous)

        pendingForceReclaimReason = nil
        coalescedOffers.removeAll()
        staged = [:]
        stagedTombstones = []
        persistStaged()

        let grantEpoch = epoch

        // The lease bounds the handshake, not the loan.
        assembleGrant(epoch: grantEpoch, referenceDate: handedOverAt,
                      expiresAt: handedOverAt.addingTimeInterval(LoanControl.takeoverLease),
                      pumpConfiguration: control.exportConfiguration(), loanSettingsRaw: loanSettings.rawValue,
                      settings: settings) { [weak self] grant in
            guard let self = self else { return }
            // The loan moved on during assembly; drop the grant.
            guard self.state == .grantOffered, self.epoch == grantEpoch else { return }
            guard let grant = grant else {
                self.abortGrant(reason: "snapshot encoding failed")
                return
            }
            self.sendMessage(.grant(grant))
            self.armT1(for: grantEpoch)
        }
    }

    /// The pump's configuration, therapy settings and history for the watch. One assembly for
    /// the live grant and the dormant refresh.
    private func assembleGrant(epoch grantEpoch: Int, referenceDate: Date, expiresAt: Date,
                               pumpConfiguration: SharedDeviceConfiguration, loanSettingsRaw: [String: Any],
                               settings: LoopSettings,
                               completion: @escaping (LoanGrant?) -> Void) {
        // Past the insulin and carb durations.
        let historyStart = referenceDate.addingTimeInterval(-.hours(16))

        // The algorithm's glucose window (`fetch` reads back to the carb window), so a loan without a
        // watch G7 sees the carb absorption the phone sees.
        let glucoseStart = referenceDate.addingTimeInterval(LoopConstants.maxCarbEntryPastTime)
        // The watch keeps 24 h of overrides and settings; the algorithm looks back about 18.
        let dayStart = referenceDate.addingTimeInterval(-.hours(24))
        deps.doseHistory(historyStart) { [weak self] history in
            guard let self = self else { return }
            self.deps.carbHistory(historyStart) { [weak self] carbs in
                guard let self = self else { return }
                self.deps.glucoseHistory(glucoseStart) { [weak self] glucose in
                    guard let self = self else { return }
                    self.deps.glucoseAlertSettings { [weak self] glucoseAlertSettings in
                    guard let self = self else { return }
                    self.deps.overrideHistory(dayStart) { [weak self] overrides in
                    guard let self = self else { return }
                    self.deps.settingsHistory(dayStart, referenceDate) { [weak self] settingsHistory in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        guard let stateData = try? PropertyListSerialization.data(fromPropertyList: pumpConfiguration.rawValue, format: .binary, options: 0),
                              let settingsData = try? PropertyListSerialization.data(fromPropertyList: loanSettingsRaw, format: .binary, options: 0) else {
                            completion(nil)
                            return
                        }

                        // The active override, so the wrist scales doses. Encoding failure is logged, not fatal.
                        let activeOverride = self.deps.scheduleOverride().flatMap {
                            $0.hasFinished() ? nil : $0
                        }
                        let overrideData: Data? = activeOverride.flatMap { o in
                            try? PropertyListSerialization.data(fromPropertyList: o.rawValue, format: .binary, options: 0)
                        }
                        if let o = activeOverride, overrideData == nil {
                            self.log.error("could not encode the active preset %{public}@; the watch doses without it", Self.overrideNameForLog(o))
                        }

                        // Schedules and insulin model travel separately; the settings blob drops them.
                        var supplement: [String: Any] = [:]
                        supplement["basalRateSchedule"] = settings.basalRateSchedule?.rawValue
                        supplement["insulinSensitivitySchedule"] = settings.insulinSensitivitySchedule?.rawValue
                        supplement["carbRatioSchedule"] = settings.carbRatioSchedule?.rawValue
                        supplement["defaultRapidActingModel"] = settings.defaultRapidActingModel?.rawValue
                        let supplementData = supplement.isEmpty ? nil
                            : try? PropertyListSerialization.data(fromPropertyList: supplement, format: .binary, options: 0)

                        let overrideHistoryData = LoanGrant.overrideHistoryRaw(overrides)
                        let grant = LoanGrant(
                            epoch: grantEpoch,
                            expiresAt: expiresAt,
                            pumpConfiguration: stateData,
                            therapySettingsRaw: settingsData,
                            // The schedules' authoring time zone.
                            settingsTimeZoneID: settings.basalRateSchedule?.timeZone.identifier ?? TimeZone.current.identifier,
                            doseHistory: history.compactMap(LoanDoseRecord.init(storeDose:)),
                            // Capability flags for version skew.

                            // Not in the settings blob.
                            integralRetrospectiveCorrectionEnabled: UserDefaults.standard.integralRetrospectiveCorrectionEnabled,
                            glucoseBasedApplicationFactorEnabled: UserDefaults.standard.glucoseBasedApplicationFactorEnabled,
                            guardAndRunwayEnabled: UserDefaults.standard.guardAndRunwayEnabled,
                            volatilityBaseline: self.deps.volatilityBaseline(),

                            phoneClosedLoopEnabled: settings.dosingEnabled,
                            carbHistory: carbs,
                            glucoseHistory: glucose,
                            activeOverrideRaw: overrideData,
                            therapySettingsSupplementRaw: supplementData,

                            // Loop recency carries across the boundary.
                            lastLoopCompleted: self.deps.lastLoopCompleted(),
                            glucoseAlertSettings: glucoseAlertSettings,
                            overrideHistoryRaw: overrideHistoryData,
                            settingsHistory: settingsHistory)
                        completion(grant)
                    }
                    }
                    }
                    }
                }
            }
        }
    }

    /// Floor on unprompted refreshes (~25 KB each).
    private static let dormantRefreshInterval: TimeInterval = .minutes(30)

    /// Floor on book-triggered refreshes, with one trailing refresh.
    private static let bookRefreshFloor: TimeInterval = 30

    /// Everything in the settings the wrist would behave differently on.
    private static func settingsFingerprint(_ s: LoopSettings) -> String {
        let basal = s.basalRateSchedule.map { String(describing: $0.items) } ?? "-"
        let isf = s.insulinSensitivitySchedule.map { String(describing: $0.items) } ?? "-"
        let cr = s.carbRatioSchedule.map { String(describing: $0.items) } ?? "-"
        let targets = s.glucoseTargetRangeSchedule.map { String(describing: $0.items) } ?? "-"
        return [basal, isf, cr, targets, String(describing: s.maximumBolus), String(describing: s.maximumBasalRatePerHour),
                "\(s.dosingEnabled)", s.basalRateSchedule?.timeZone.identifier ?? "-",
                String(describing: s.suspendThreshold), String(describing: s.preMealTargetRange),
                "\(s.automaticDosingStrategy)", String(describing: s.overridePresets),
                String(describing: s.defaultRapidActingModel)].joined(separator: "|")
    }

    /// The settings plus what the copy carries from outside them.
    private func standingCopyFingerprint(_ s: LoopSettings) -> String {
        let activeOverride = deps.scheduleOverride().flatMap { $0.hasFinished() ? nil : $0 }
        return [Self.settingsFingerprint(s), String(describing: activeOverride),
                "\(UserDefaults.standard.integralRetrospectiveCorrectionEnabled)",
                "\(UserDefaults.standard.glucoseBasedApplicationFactorEnabled)",
                "\(UserDefaults.standard.guardAndRunwayEnabled)",
                String(describing: deps.pumpManager()?.status.insulinType),
                String(describing: glucoseAlertSettingsSeen)].joined(separator: "|")
    }

    /// The phone's glucose alert settings changed (or were first seen): refresh the copy now.
    func noteGlucoseAlertSettings(_ settings: GlucoseAlertSettings) {
        guard settings != glucoseAlertSettingsSeen else { return }
        glucoseAlertSettingsSeen = settings
        considerDormantRefresh()
    }

    /// Minted once; echoed back by a watch that started alone.
    func dormantSeizeToken() -> UUID {
        if let token = persisted.seizeToken { return token }
        let token = UUID()
        updateState { $0.seizeToken = token }
        return token
    }

    /// Keeps the watch's standing copy current. `bookChanged`: insulin or carbs moved.
    func considerDormantRefresh(bookChanged: Bool = false) {
        // Only while this phone holds the pod, and only to a watch that said it can use this.
        guard state == .owner else { return }
        guard persisted.watchUsesSportMode else { return }
        guard let control = deps.pumpManager() as? ExclusiveDeviceControl,
              !control.isControlReleased else { return }
        let settings = deps.settings()

        guard settings.maximumBolus != nil, settings.maximumBasalRatePerHour != nil,
              settings.basalRateSchedule != nil else { return }

        // The epoch rides the fingerprint, so a spent epoch is never reused.
        let fingerprint = standingCopyFingerprint(settings) + "|e\(epoch)"
        let periodicDue = lastDormantRefreshAt.map { deps.now().timeIntervalSince($0) >= Self.dormantRefreshInterval } ?? true
        let settingsChanged = fingerprint != lastDormantSettingsFingerprint
        guard periodicDue || settingsChanged || bookChanged else { return }
        if !periodicDue, !settingsChanged, let last = lastDormantRefreshAt {
            let wait = Self.bookRefreshFloor - deps.now().timeIntervalSince(last)
            if wait > 0 {
                guard !trailingDormantRefreshPending else { return }
                trailingDormantRefreshPending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.trailingDormantRefreshPending = false
                    self?.considerDormantRefresh(bookChanged: true)
                }
                return
            }
        }

        let loanSettings = settings
        let issuedAt = deps.now()
        let token = dormantSeizeToken()
        // A provisional epoch: the loan this copy would become if the watch ever starts one.
        let provisionalEpoch = epoch + 1

        // Stamp at enqueue, so a burst of callers queues one copy.
        lastDormantRefreshAt = issuedAt
        lastDormantSettingsFingerprint = fingerprint
        // Issued already expired: a seize re-stamps the lease when it starts.
        assembleGrant(epoch: provisionalEpoch, referenceDate: issuedAt, expiresAt: issuedAt,
                      pumpConfiguration: control.exportConfiguration(), loanSettingsRaw: loanSettings.rawValue,
                      settings: settings) { [weak self] grant in
            guard let self = self else { return }
            guard let grant = grant else {
                // Unstamp so the next cycle retries.
                self.lastDormantRefreshAt = nil
                return
            }
            // A loan started meanwhile; the watch already has newer materials.
            guard self.state == .owner else { return }
            self.sendMessage(.dormantGrant(DormantGrant(grant: grant, issuedAt: issuedAt, seizeToken: token)))
            PhoneLog.event("seize", "standing copy sent to the watch with \(grant.doseHistory.count) dose records")
        }
    }

}
