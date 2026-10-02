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
import os.log

extension PodLoanPhoneController {
    /// The watch is asking for the pod.
    func handleRequest(_ request: LoanRequest) {
        // Age first: an expired request has a sender that has moved on.
        if let sentAt = request.sentAt {
            let age = deps.now().timeIntervalSince(sentAt)
            if age > Self.requestTTL {
                os_log("Loan request STALE — sent %.0fs ago (TTL %.0fs); ignored as a queued-channel ghost",
                       log: log, type: .default, age, Self.requestTTL)
                PhoneLog.event("loan", String(format: "request STALE — sent %.0fs ago (TTL %.0fs) — ignored, no grant", age, Self.requestTTL))
                return
            }
        }

        if let id = request.requestID, id == lastRequestID,
           let seenAt = lastRequestAt,
           deps.now().timeIntervalSince(seenAt) < Self.requestDedupeWindow {
            os_log("Duplicate loan request %{public}@ ignored (transport redelivery, %.1fs after the first)",
                   log: log, type: .default, id, deps.now().timeIntervalSince(seenAt))
            return
        }
        if let id = request.requestID {
            lastRequestID = id
            lastRequestAt = deps.now()
        }

        if let seize = request.supportsSeize {
            updateState { $0.watchSupportsSeize = seize }
        }
        // Version skew ends here with a nack; the apps install separately.
        guard request.supportedVersions.contains(LoanProtocol.version) else {
            sendMessage(.nack(ProtocolNack(seenVersion: request.supportedVersions.max())))
            return
        }
        // A grant is mid-flight: the phone has already paused dosing and is waiting on the pod.
        guard !grantInFlight else {
            deny("A grant is already in progress.")
            return
        }
        guard state == .owner else {
            switch state {
            // A previous attempt never finished: recover to owner and grant afresh.
            case .grantOffered, .reconciling, .reclaimPending:

                os_log("Loan request while %{public}@ — recovering stale state and granting", log: log, type: .default, state.rawValue)
                forceReclaimToOwner(reason: "new request while \(state.rawValue)")
                beginGrant()
            // A live loan is not stale state. Take it back properly and let the user ask again.
            case .loaned:

                os_log("Loan request while LOANED — revoking the previous loan first", log: log, type: .default)
                reclaimNow()
                deny("Reclaiming the previous loan from the watch — try Start again in a few seconds.")
            case .owner:
                break
            }
            return
        }
        beginGrant()
    }

    /// Refuse, with a reason the glance can show.
    func deny(_ reason: String) {
        os_log("Loan denied: %{public}@", log: log, type: .default, reason)
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
            deny("This pump can't be loaned to the watch (\(type(of: pump))).")
            return
        }

        // A grant supersedes an inferred loan; the radio comes back first.
        if yieldingToInferredLoan {
            clearInferredLoanYield(reason: "new loan request — a granted loan supersedes the inferred one")
            reclaimPodConnection()
        }

        // Refuse until the last reclaim's pod round-trip has verified.
        if let started = reclaimStartedAt,
           deps.now().timeIntervalSince(started) < Self.reclaimSettleTimeout,
           reclaimVerifiedAt == nil {
            os_log("Grant deferred: pod still returning from the last reclaim (%.0fs into settle, round-trip not yet verified) — deny-and-retry",
                   log: log, type: .default, deps.now().timeIntervalSince(started))
            deny("The pod is still returning from the last session. Try Start again in a few seconds.")
            attemptReclaimVerificationNow(started: started)
            return
        }

        let settings = deps.settings()

        let loanSettings = settings
        PhoneLog.event("loan", "dosing strategy for the loan: \(settings.automaticDosingStrategy)")
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

        // Cancel the phone's temp and wait for the pod to acknowledge it before releasing.
        grantInFlight = true
        deps.setAutomaticDosingPaused(true)
        deps.cancelTempBasalForGrant { [weak self] error in
            guard let self = self else { return }
            self.queue.async {
                self.grantInFlight = false
                if let error = error {
                    self.deps.setAutomaticDosingPaused(false)

                    self.deny("The iPhone couldn't reach its pod (\(error.localizedDescription)). The phone kept the pod.")
                    return
                }
                self.continueGrant(settings: settings, loanSettings: loanSettings, pump: pump, control: control)
            }
        }
    }

    /// One-way from here: odometer origin, link released, epoch advanced.
    private func continueGrant(settings: LoopSettings, loanSettings: LoopSettings,
                               pump: PumpManager, control: ExclusiveDeviceControl) {
                let handedOverAt = deps.now()

        // This loan's origin; the previous loan's takeover reading is cleared with it.
        let deliveredAtGrant = (pump as? PumpDeliveryOdometer)?.deliveredUnits?.units

        let releaseEpoch = epoch + 1
        handbackDiag(releaseEpoch, "GRANT — releasing pod BLE (wasReleased=\(control.isControlReleased))")
        control.releaseControl()
        // A link still up here predicts a refused takeover (the pod accepts one central).
        queue.asyncAfter(deadline: .now() + 3) { [weak self, weak pump] in
            guard let self = self, let control = pump as? ExclusiveDeviceControl else { return }

            self.handbackDiag(releaseEpoch, "GRANT +3s — pod BLE released=\(control.isControlReleased) linkUp=\(control.isControlReady)")
            if control.isControlReady {
                self.handbackDiag(releaseEpoch, "GRANT +3s — ** STILL CONNECTED after release — the watch's takeover will be refused (single-central pod) **")
            }
        }

        // New epoch, empty dedup state, this loan's anchors: one save, before the grant goes out.
        let previous = state
        updateState {
            $0.epoch += 1
            $0.phase = .grantOffered
            $0.committedCursor = 0
            $0.committedIDs = []
            $0.audit = .init(loanStartedAt: handedOverAt, deliveredAtGrant: deliveredAtGrant,
                             base: deliveredAtGrant.map { AuditBase(units: $0, asOf: handedOverAt) })
            $0.audit.baseEpoch = $0.epoch
            $0.holdRenewedAt = handedOverAt
            $0.holdLapseNoticedAt = nil
            $0.watchSilenceWarningsIssued = 0
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
                      expiresAt: handedOverAt.addingTimeInterval(.minutes(5)),
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

        let glucoseStart = referenceDate.addingTimeInterval(-.hours(3))
        // The watch keeps 24 h of overrides; the algorithm looks back about 18.
        let overridesStart = referenceDate.addingTimeInterval(-.hours(24))
        deps.doseHistory(historyStart) { [weak self] history in
            guard let self = self else { return }
            self.deps.carbHistory(historyStart) { [weak self] carbs in
                guard let self = self else { return }
                self.deps.glucoseHistory(glucoseStart) { [weak self] glucose in
                    guard let self = self else { return }
                    self.deps.glucoseAlertSettings { [weak self] glucoseAlertSettings in
                    guard let self = self else { return }
                    self.deps.overrideHistory(overridesStart) { [weak self] overrides in
                    guard let self = self else { return }
                    self.queue.async {
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
                        if let o = activeOverride {
                            if overrideData == nil {
                                os_log("[override] grant: FAILED to encode active override %{public}@ — the wrist will dose UNSCALED",
                                       log: self.log, type: .error, Self.overrideNameForLog(o))
                            } else {
                                os_log("[override] grant: carrying %{public}@ · insulin needs %.0f%% · sync %{public}@",
                                       log: self.log, type: .default, Self.overrideNameForLog(o),
                                       o.settings.effectiveInsulinNeedsScaleFactor * 100,
                                       o.syncIdentifier.uuidString)
                            }
                        }

                        // Schedules and insulin model travel separately; the settings blob drops them.
                        var supplement: [String: Any] = [:]
                        supplement["basalRateSchedule"] = settings.basalRateSchedule?.rawValue
                        supplement["insulinSensitivitySchedule"] = settings.insulinSensitivitySchedule?.rawValue
                        supplement["carbRatioSchedule"] = settings.carbRatioSchedule?.rawValue
                        supplement["defaultRapidActingModel"] = settings.defaultRapidActingModel?.rawValue
                        let supplementData = supplement.isEmpty ? nil
                            : try? PropertyListSerialization.data(fromPropertyList: supplement, format: .binary, options: 0)
                        os_log("[grant] settings supplement: basal=%{public}@ isf=%{public}@ cr=%{public}@ model=%{public}@ bytes=%{public}d",
                               log: self.log, type: .default,
                               settings.basalRateSchedule == nil ? "MISSING" : "ok",
                               settings.insulinSensitivitySchedule == nil ? "MISSING" : "ok",
                               settings.carbRatioSchedule == nil ? "MISSING" : "ok",
                               settings.defaultRapidActingModel.map { String(describing: $0) } ?? "MISSING (wrist will assume rapid-acting adult)",
                               supplementData?.count ?? 0)

                        let overrideHistoryData = LoanGrant.overrideHistoryRaw(overrides)
                        self.handbackDiag(grantEpoch, "[grant] supplement \(supplementData?.count ?? 0)B · seeds: \(history.count) dose, \(carbs.count) carb, \(glucose.count) glucose, \(overrides.count) override (\(overrideHistoryData?.count ?? 0)B) · podState \(stateData.count)B · settings \(settingsData.count)B · glucose alerts \(glucoseAlertSettings.map { "\($0.count)B" } ?? "ABSENT")")
                        let grant = LoanGrant(
                            epoch: grantEpoch,
                            expiresAt: expiresAt,
                            pumpConfiguration: stateData,
                            podAddress: 0,
                            therapySettingsRaw: settingsData,
                            // The schedules' authoring time zone.
                            settingsTimeZoneID: settings.basalRateSchedule?.timeZone.identifier ?? TimeZone.current.identifier,
                            doseHistory: history.compactMap(Self.loanRecord(from:)),
                            // Capability flags for version skew.
                            supportsInterimHandback: true,
                            supportsOverrideRecords: true,

                            // Not in the settings blob.
                            integralRetrospectiveCorrectionEnabled: UserDefaults.standard.integralRetrospectiveCorrectionEnabled,

                            phoneClosedLoopEnabled: settings.dosingEnabled,
                            carbHistory: carbs,
                            glucoseHistory: glucose,
                            activeOverrideRaw: overrideData,
                            therapySettingsSupplementRaw: supplementData,

                            // Loop recency carries across the boundary.
                            lastLoopCompleted: self.deps.lastLoopCompleted(),
                            glucoseAlertSettings: glucoseAlertSettings,
                            overrideHistoryRaw: overrideHistoryData)
                        completion(grant)
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
                String(describing: deps.pumpManager()?.status.insulinType),
                String(describing: glucoseAlertSettingsSeen)].joined(separator: "|")
    }

    /// The phone's glucose alert settings changed (or were first seen): refresh the copy now.
    func noteGlucoseAlertSettings(_ settings: GlucoseAlertSettings) {
        queue.async { [weak self] in
            guard let self, settings != self.glucoseAlertSettingsSeen else { return }
            self.glucoseAlertSettingsSeen = settings
            self.queue_considerDormantRefresh()
        }
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
        queue.async { [weak self] in self?.queue_considerDormantRefresh(bookChanged: bookChanged) }
    }

    private func queue_considerDormantRefresh(bookChanged: Bool = false) {
        // Only while this phone holds the pod, and only to a watch that said it can use this.
        guard state == .owner else { return }
        guard persisted.watchSupportsSeize else { return }
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
                queue.asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.trailingDormantRefreshPending = false
                    self?.queue_considerDormantRefresh(bookChanged: true)
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
            PhoneLog.event("seize", "dormant grant refreshed — \(grant.doseHistory.count) dose record(s), token …\(String(token.uuidString.suffix(8))) [seize]")
        }
    }

}
