//
//  PodLoanPhoneController+Grant.swift
//  Loop
//
//  Part of PodLoanPhoneController (see PodLoanPhoneController.swift). Split by concern; stored
//  properties live in the core class.
//
//  Lending the pod: deciding whether a request can be honoured, letting go of the pod cleanly,
//  and assembling the copy of the phone's therapy the watch will dose from.
//
//  Two rules shape all of it. The grant DENIES rather than defaults — a watch given partial
//  therapy settings would dose on guesses. And nothing is a guess about the pod either: the
//  phone's running temp is cancelled and acknowledged by the pod before the link is released,
//  so no program crosses the boundary.
//
//  The same assembly serves the live grant and the standing copy a watch can start from without
//  the phone. A seized session must dose on exactly the same materials a granted one gets.
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
        // Age first — before the dedupe, and before any capability the request advertises is
        // recorded. A request older than the TTL has a sender that has moved on.
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
            UserDefaults.standard.set(seize, forKey: Keys.watchSupportsSeize)
        }
        // Version skew ends the exchange here, with a nack naming what the watch offered. The
        // two apps install separately, so a mismatch is an ordinary event and must be legible.
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
            // Transient states: a request arriving here means the previous attempt never
            // finished, so recover to owner and grant afresh rather than leaving the user with
            // a Start button that does nothing.
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

    /// Refuse, and say why in words the watch can put on its glance. The reason travels; a
    /// refusal the user cannot read is indistinguishable from a dead link.
    func deny(_ reason: String) {
        os_log("Loan denied: %{public}@", log: log, type: .default, reason)
        sendMessage(.denied(LoanDenied(reason: reason)))
    }

    /// Decides whether the pod can be lent right now, and if so starts letting go of it.
    ///
    /// Every refusal is DELIVERED — the watch shows the reason on its glance, because a Start
    /// button that silently does nothing is indistinguishable from a broken link.
    ///
    /// Deliberately NOT gated on whether the watch app is installed: that flag lags reality by
    /// over a minute and has refused live watches, and its refusal would have to travel over the
    /// very direction it claims is broken.
    ///
    /// The refusals come first and in order of how cheap they are to recover from: no pump, a
    /// pump that cannot be lent, a pod still returning from the last session, incomplete
    /// therapy. Only once all of them pass does anything irreversible happen — and the first
    /// irreversible step is cancelling this phone's own temp, in `continueGrant`.
    func beginGrant() {
        guard let pump = deps.pumpManager() else {
            deny("No pump is set up on the phone.")
            return
        }
        guard let lendable = pump as? PumpConnectionLendable else {
            deny("This pump can't be loaned to the watch (\(type(of: pump))).")
            return
        }

        // A deliberate grant supersedes a posture the phone adopted by inference, and the radio
        // has to come back with it — the phone cannot hand over a link it is not holding.
        if yieldingToInferredLoan {
            clearInferredLoanYield(reason: "new loan request — a granted loan supersedes the inferred one")
            reclaimPodConnection()
        }

        // Refuse while the LAST reclaim is still unverified. Readiness here means a completed
        // pod round-trip, not a link that reports itself up — that flips true within seconds of
        // a hand-back, long before the pod's return work has happened, and a takeover launched
        // inside that gap fails. The settle ceiling bounds how long this can refuse.
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

        // Force temp-basal-only in the SNAPSHOT the watch receives, never in the phone's stored
        // setting. The watch doses by temp basal and refuses every cycle under automatic bolus.
        // Changing the real setting would need a restore that can fail — a relaunch, a force
        // reclaim, a dead watch — and would strand the user on temp-basal-only for good.
        var loanSettings = settings
        let strategyOverridden = settings.automaticDosingStrategy != .tempBasalOnly
        loanSettings.automaticDosingStrategy = .tempBasalOnly
        if strategyOverridden {
            PhoneLog.event("loan", "dosing strategy overridden for the loan — phone \(settings.automaticDosingStrategy) → wrist tempBasalOnly; the phone's own setting is untouched")
        }
        // Deny on anything missing — never substitute a default. Each of these is something the
        // watch would otherwise have to invent a value for, and it would dose on that value.
        guard settings.basalRateSchedule != nil,
              settings.insulinSensitivitySchedule != nil,
              settings.carbRatioSchedule != nil,
              settings.glucoseTargetRangeSchedule != nil,
              settings.maximumBasalRatePerHour != nil,
              settings.maximumBolus != nil else {
            deny("Therapy settings are incomplete; the watch can't dose without them.")
            return
        }

        // Stop dosing and cancel the phone's running temp, then WAIT for the pod to acknowledge
        // it. Only then does the rest of the grant run, so no program crosses the boundary and
        // the phone's books hold a real finished temp. A pod that will not answer the cancel
        // cannot be lent at all — deny rather than hand over a pod in an unknown state.
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
                self.continueGrant(settings: settings, loanSettings: loanSettings, pump: pump, lendable: lendable)
            }
        }
    }

    /// The pod has answered the cancel. Everything from here is one-way: the odometer origin is
    /// captured, the link is released, and the epoch advances.
    private func continueGrant(settings: LoopSettings, loanSettings: LoopSettings,
                               pump: PumpManager, lendable: PumpConnectionLendable) {
                let handedOverAt = deps.now()

        // Capture the pod's delivery total as this loan's origin, and clear the previous loan's
        // takeover reading in the same breath. A stale one left behind would put that whole
        // loan's delivery inside this loan's unexplained window.
        if let delivered = lendable.lentDeviceInsulinDelivered {
            UserDefaults.standard.set(delivered, forKey: Keys.deliveredAtGrant)

            auditBase = AuditBase(units: delivered, asOf: handedOverAt)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.deliveredAtGrant)
            auditBase = nil
        }
        checkpointsThisLoan = 0
        worstWindowThisLoan = 0

        UserDefaults.standard.removeObject(forKey: Keys.deliveredAtTakeover)

        let releaseEpoch = epoch + 1
        handbackDiag(releaseEpoch, "GRANT — releasing pod BLE (wasReleased=\(lendable.isConnectionReleased))")
        lendable.releaseConnection()
        // Check back shortly after releasing. The pod accepts one central at a time, so a link
        // still up here predicts a refused takeover — worth saying plainly in the log, because
        // from the watch's side that failure looks like a pod problem.
        queue.asyncAfter(deadline: .now() + 3) { [weak self, weak lendable] in
            guard let self = self, let lendable = lendable else { return }

            self.handbackDiag(releaseEpoch, "GRANT +3s — pod BLE released=\(lendable.isConnectionReleased) linkUp=\(lendable.isConnectionReady)")
            if lendable.isConnectionReady {
                self.handbackDiag(releaseEpoch, "GRANT +3s — ** STILL CONNECTED after release — the watch's takeover will be refused (single-central pod) **")
            }
            PhoneLog.flush()
        }

        // New epoch, empty books: dedup state belongs to one loan, and carrying it forward would
        // silently discard the new loan's records.
        epoch += 1
        state = .grantOffered
        committedCursor = 0
        committedIDs = []
        persistCommittedIDs()

        pendingForceReclaimReason = nil
        coalescedOffers.removeAll()
        staged = [:]
        stagedTombstones = []
        persistStaged()
        loanStartedAt = handedOverAt
        UserDefaults.standard.set(handedOverAt, forKey: Keys.loanStartedAt)
        holdRenewedAt = handedOverAt
        holdLapseNoticedAt = nil

        let grantEpoch = epoch

        // The lease bounds the HANDSHAKE, not the loan: the watch must adopt this grant within
        // it or refuse it. Past that the phone has moved on, and an adoption would leave both
        // devices believing they hold the pod.
        assembleGrant(epoch: grantEpoch, referenceDate: handedOverAt,
                      expiresAt: handedOverAt.addingTimeInterval(.minutes(5)),
                      pumpRaw: pump.rawValue, loanSettingsRaw: loanSettings.rawValue,
                      settings: settings) { [weak self] grant in
            guard let self = self else { return }
            // Assembly is asynchronous. If the loan has moved on in the meantime this grant
            // describes a session that no longer exists, so it is dropped rather than sent.
            guard self.state == .grantOffered, self.epoch == grantEpoch else { return }
            guard let grant = grant else {
                self.abortGrant(reason: "snapshot encoding failed")
                return
            }
            self.sendMessage(.grant(grant))
            self.armT1(for: grantEpoch)
        }
    }

    /// Builds the whole package the watch doses from: pod state, therapy settings, and enough
    /// history for the algorithm to have a past.
    ///
    /// ONE assembly serves both the live grant and the dormant refresh. Duplicating the chain
    /// would let a seized session dose on different materials from a granted one, and the two
    /// would drift apart quietly.
    private func assembleGrant(epoch grantEpoch: Int, referenceDate: Date, expiresAt: Date,
                               pumpRaw: [String: Any], loanSettingsRaw: [String: Any],
                               settings: LoopSettings,
                               completion: @escaping (LoanGrant?) -> Void) {
        // Insulin and carbs reach back past their action durations; glucose only needs enough
        // for momentum and retrospective correction.
        let historyStart = referenceDate.addingTimeInterval(-.hours(16))

        let glucoseStart = referenceDate.addingTimeInterval(-.hours(3))
        deps.doseHistory(historyStart) { [weak self] history in
            guard let self = self else { return }
            self.deps.carbHistory(historyStart) { [weak self] carbs in
                guard let self = self else { return }
                self.deps.glucoseHistory(glucoseStart) { [weak self] glucose in
                    guard let self = self else { return }
                    self.queue.async {
                        guard let stateData = try? PropertyListSerialization.data(fromPropertyList: pumpRaw, format: .binary, options: 0),
                              let settingsData = try? PropertyListSerialization.data(fromPropertyList: loanSettingsRaw, format: .binary, options: 0) else {
                            completion(nil)
                            return
                        }

                        // Carry the phone's active override. Without it the wrist resolves every
                        // schedule unscaled — full-strength insulin during exercise, which is the
                        // over-delivery direction. Failing to encode it is NOT fatal: a loan
                        // refused mid-exercise is worse than one that doses unscaled, so the
                        // failure is stated loudly and the grant goes on.
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

                        // The settings blob above loses all four of these on this branch, so they
                        // travel separately. Missing schedules make the watch refuse loudly;
                        // a missing insulin model degrades it SILENTLY to a default curve, which
                        // is the worse failure of the two.
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

                        self.handbackDiag(grantEpoch, "[grant] supplement \(supplementData?.count ?? 0)B · seeds: \(history.count) dose, \(carbs.count) carb, \(glucose.count) glucose · podState \(stateData.count)B · settings \(settingsData.count)B")
                        let grant = LoanGrant(
                            epoch: grantEpoch,
                            expiresAt: expiresAt,
                            pumpManagerRawState: stateData,
                            podAddress: 0,
                            therapySettingsRaw: settingsData,
                            // The schedules travel as raw values with no timezone of their own,
                            // so the zone they were authored in travels beside them. Resolved in
                            // the wrong zone, every schedule item lands at the wrong hour.
                            settingsTimeZoneID: settings.basalRateSchedule?.timeZone.identifier ?? TimeZone.current.identifier,
                            doseHistory: history.compactMap(Self.loanRecord(from:)),
                            // Capability flags, not preferences. They tell the watch which
                            // message shapes this phone can decode, and a watch newer than its
                            // phone is routine — the two apps install separately.
                            supportsInterimHandback: true,
                            supportsOverrideRecords: true,

                            // Not part of the settings blob either. Left out, the watch runs
                            // standard retrospective correction while the phone runs integral:
                            // different predictions from identical inputs, with no error.
                            integralRetrospectiveCorrectionEnabled: UserDefaults.standard.integralRetrospectiveCorrectionEnabled,

                            phoneClosedLoopEnabled: settings.dosingEnabled,
                            carbHistory: carbs,
                            glucoseHistory: glucose,
                            activeOverrideRaw: overrideData,
                            therapySettingsSupplementRaw: supplementData,

                            // Loop recency is a property of the SYSTEM, not of a device, so the
                            // boundary inherits it. The watch's own next cycle then keeps or
                            // loses that freshness honestly.
                            lastLoopCompleted: self.deps.lastLoopCompleted())
                        completion(grant)
                    }
                }
            }
        }
    }

    /// Floor on unprompted refreshes. The dormant copy is whole-book and latest-only, so the
    /// cost of one is a 25 KB transfer the watch may never use.
    private static let dormantRefreshInterval: TimeInterval = .minutes(30)

    /// Floor on refreshes triggered by the book changing, which can happen repeatedly in a
    /// minute. One trailing refresh is scheduled instead, so the last change still lands.
    private static let bookRefreshFloor: TimeInterval = 30

    /// What "the settings changed" means for refresh purposes: everything the wrist would dose
    /// differently on.
    private static func settingsFingerprint(_ s: LoopSettings) -> String {
        let basal = s.basalRateSchedule.map { String(describing: $0.items) } ?? "-"
        let isf = s.insulinSensitivitySchedule.map { String(describing: $0.items) } ?? "-"
        let cr = s.carbRatioSchedule.map { String(describing: $0.items) } ?? "-"
        let targets = s.glucoseTargetRangeSchedule.map { String(describing: $0.items) } ?? "-"
        return "\(basal)|\(isf)|\(cr)|\(targets)|\(String(describing: s.maximumBolus))|\(String(describing: s.maximumBasalRatePerHour))|\(s.dosingEnabled)"
    }

    /// Minted once and kept. It is the credential a watch echoes back to prove that a session it
    /// started alone came from this phone's standing copy.
    func dormantSeizeToken() -> UUID {
        if let raw = UserDefaults.standard.string(forKey: Keys.dormantSeizeToken),
           let token = UUID(uuidString: raw) {
            return token
        }
        let token = UUID()
        UserDefaults.standard.set(token.uuidString, forKey: Keys.dormantSeizeToken)
        return token
    }

    /// Keeps the watch's standing copy current, so a session started without the phone starts on
    /// today's therapy and today's books.
    ///
    /// - Parameter bookChanged: true when insulin or carbs moved. The book matters as much as
    ///   the settings: carbs entered minutes before a phoneless start, and absent from the copy,
    ///   leave the wrist dosing against insulin it knows and food it does not.
    func considerDormantRefresh(bookChanged: Bool = false) {
        queue.async { [weak self] in self?.queue_considerDormantRefresh(bookChanged: bookChanged) }
    }

    private func queue_considerDormantRefresh(bookChanged: Bool = false) {
        // Only while this phone holds the pod, and only to a watch that said it can use this.
        guard state == .owner else { return }
        guard UserDefaults.standard.bool(forKey: Keys.watchSupportsSeize) else { return }
        guard let pump = deps.pumpManager(),
              let lendable = pump as? PumpConnectionLendable,
              !lendable.isConnectionReleased else { return }
        let settings = deps.settings()

        guard settings.maximumBolus != nil, settings.maximumBasalRatePerHour != nil,
              settings.basalRateSchedule != nil else { return }

        // The epoch rides the fingerprint. Without it a copy carrying a spent provisional epoch
        // survives a loan, and back-to-back seizes reuse an epoch the watch has already revoked
        // — which its split-brain guard then refuses, stranding the session.
        let fingerprint = Self.settingsFingerprint(settings) + "|e\(epoch)"
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

        var loanSettings = settings
        loanSettings.automaticDosingStrategy = .tempBasalOnly
        let issuedAt = deps.now()
        let token = dormantSeizeToken()
        // A provisional epoch: the loan this copy would become if the watch ever starts one.
        let provisionalEpoch = epoch + 1

        // Stamp the throttle HERE, at enqueue, not in the completion below. Assembly is async,
        // so stamping on completion lets a burst of callers all pass the same open gate and
        // queue several identical whole-book copies within a second.
        lastDormantRefreshAt = issuedAt
        lastDormantSettingsFingerprint = fingerprint
        // Issued ALREADY EXPIRED, by contract: `expiresAt` is the issue time, so this copy can
        // never be activated verbatim as a grant. The lease bounds a handshake, and a seize
        // re-stamps the credential with a fresh one when it actually starts.
        assembleGrant(epoch: provisionalEpoch, referenceDate: issuedAt, expiresAt: issuedAt,
                      pumpRaw: pump.rawValue, loanSettingsRaw: loanSettings.rawValue,
                      settings: settings) { [weak self] grant in
            guard let self = self else { return }
            guard let grant = grant else {
                // Unstamp the throttle so the next cycle tries again rather than waiting out
                // the interval on a refresh that never happened.
                self.lastDormantRefreshAt = nil
                return
            }
            // A loan may have started while this was being assembled; the watch already has
            // better materials than this copy.
            guard self.state == .owner else { return }
            self.sendMessage(.dormantGrant(DormantGrant(grant: grant, issuedAt: issuedAt, seizeToken: token)))
            PhoneLog.event("seize", "dormant grant refreshed — \(grant.doseHistory.count) dose record(s), token …\(String(token.uuidString.suffix(8))) [seize]")
        }
    }

}
