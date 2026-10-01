//
//  StockLoopSession.swift
//  WatchApp Extension
//
//  App-lifecycle OWNER of the assembled loop and the loan controller, and the place where the
//  two are wired to each other and to WatchConnectivity.
//
//  ExtensionDelegate holds one lazily. It stays inert — no pod, no dosing — until a loan grant
//  arrives; the CGM is the exception and runs whenever the app has runtime.
//
//  Everything the loan controller needs from the outside world is a closure assigned here, so
//  the controller itself knows nothing about WCSession, the keepalive or the log. `init` is
//  therefore an ordering: assemble, install every closure, and only then resume a saved loan —
//  a resume that ran before the closures were in place would have nothing to send over.
//

import Foundation
import LoopCore
import OmnipodKit
import G7SensorKit
import WatchConnectivity
import os.log

final class StockLoopSession {
    let stack: StockLoopStack.Stack

    private let keepalive = WorkoutKeepalive()

    /// Whether a workout session is held for the WHOLE loan. OFF by default: a loan without one
    /// was field-proven, and the app sleeping between bursts is the normal posture. Takeover and
    /// hand-back still take their own runtime holds, which is where the runtime actually matters.
    ///
    /// The consequence to keep in mind when reading timer code: with this off, dispatch timers do
    /// not run while the app is suspended, so anything scheduled across a wrist-down stretch
    /// fires late and says so.
    static let loanWorkoutKey = "G7Lab.loan.workout"
    static var loanWorkout: Bool { UserDefaults.standard.bool(forKey: loanWorkoutKey) }

    /// The keepalive tracks a SET of named holders, so `reason` must be stable per caller: the
    /// takeover, hand-back and whole-loan holds overlap, and the session ends only when the last
    /// one lets go. Only the whole-loan holder is gated, and its release runs even when the
    /// setting is off, so flipping the setting mid-loan cannot strand a hold.
    private func setKeepalive(_ holding: Bool, reason: String) {
        if reason == "loanWorkout", !Self.loanWorkout {
            SportLog.event("keepalive", "loan workout holder \(holding ? "not held" : "release ignored") — no workout session during loans (Diagnostics ▸ Pod loan); the app sleeps between bursts")
            keepalive.release(reason)
            return
        }
        holding ? keepalive.acquire(reason) : keepalive.release(reason)
    }

    /// Re-drive the keepalive without taking a hold, for a wake that finds holders but no live
    /// workout session — the session can be ended by the system while the holders remain.
    func ensureKeepalive() { keepalive.ensureRunning() }
    let loanController: PodLoanWatchController

    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "StockLoopSession")

    /// Fails only if the stores cannot be opened. There is no degraded mode: without them there
    /// is no book to dose from, so the app must run as the stock watch app and this page must
    /// offer nothing — never a Start that leads to a loan with nowhere to record it.
    init?() async {
        guard let assembled = await StockLoopStack.assemble() else { return nil }
        stack = assembled
        loanController = PodLoanWatchController(loopManager: stack.loopManager)

        PodLoanConnectClock.podLoanLogSink = { line in SportLog.event("pod-ble", line) }

        RuntimeStateLog.startMainStallDetector()

        loanController.isPhoneReachable = { WCSession.default.isReachable }

        // The per-cycle renewal batch is what tells the phone this watch is still alive — the
        // phone's silence warning and its live/dead discriminator both measure the age of these.
        // Anything that stops cycles landing therefore also stops the phone hearing from us.
        stack.loopManager.onCycleLanded = { [weak loanController] in loanController?.renewHold() }

        // A queued request for a dark phone is a delayed detonator: delivered at reunion it can
        // land inside the phone's freshness window and re-grant over a loan this watch is
        // already running. Only requests NOT YET TRANSFERRING are cancelled — a transfer in
        // flight is being answered right now, and cancelling it loses the answer.
        loanController.cancelQueuedLoanRequests = {
            let stale = WCSession.default.outstandingUserInfoTransfers.filter {
                LoanMessage.peekKind(transport: $0.userInfo) == "request" && !$0.isTransferring
            }
            stale.forEach { $0.cancel() }
            return stale.count
        }

        // The loan protocol's only way out of this watch. Two channels: sendMessage, which is
        // immediate but needs a reachable phone, and transferUserInfo, which is queued and will
        // be delivered whenever the link returns — possibly hours later, which is the hazard the
        // rules below exist for. Every send is logged with the channel it took, because
        // "the message never arrived" and "it arrived and a guard dropped it" are otherwise the
        // same log.
        loanController.send = { [weak loanController] dictionary in

            let session = WCSession.default

            let wedged = loanController?.urgentSendWedged ?? false
            let urgent = LoanMessage.isInteractiveHandshake(transport: dictionary)
                && session.isReachable && !wedged
            SportLog.event("wc", "send \(dictionary.keys.joined(separator: ",")) — session \(session.activationState.rawValue), reachable \(session.isReachable), path \(urgent ? "urgent" : "queued")")

            // At most one hand-back offer waits in the queue, and only OFFERS are ever superseded:
            // an offer is resent by design and the newest one describes the whole drain, while a
            // record stream or a status message is one-shot and cancelling it loses it.
            //
            // The order is exact. Capture the stale list BEFORE enqueueing, or the new transfer
            // is in the list and gets cancelled along with the old ones; cancel AFTER, or the
            // queue is momentarily empty and a phone that wakes in that instant hears nothing.
            let enqueueSuperseding = { (payload: [String: Any]) in
                let isOffer = LoanMessage.peekKind(transport: payload) == "handbackOffer"
                let stale = isOffer
                    ? session.outstandingUserInfoTransfers.filter {
                        LoanMessage.peekKind(transport: $0.userInfo) == "handbackOffer"
                      }
                    : []
                session.transferUserInfo(payload)
                let cancelled = stale.filter { !$0.isTransferring }
                guard !cancelled.isEmpty else { return }
                cancelled.forEach { $0.cancel() }
                SportLog.event("wc", "superseded \(cancelled.count) queued offer(s) with the fresh one (#120)")
            }

            // A LIVE hand-back offer is never queued. If the phone cannot be reached now, fail
            // now and keep the loan: a queued offer is accepted whenever the link returns, with
            // the phone possibly nowhere near the pod and the loan long since moved on — the
            // phone then reclaims a loan the watch is still dosing, and both devices dose.
            // Drains from a loan that has already ended still queue; they carry no such claim.
            let urgentOnly = dictionary["urgentOnly"] as? Bool == true
            guard urgent else {
                if urgentOnly {
                    SportLog.event("wc", "live hand-back offer NOT queued — urgent path unavailable (reachable \(session.isReachable), wedged \(wedged)); the resend loop retries")
                    return
                }
                enqueueSuperseding(dictionary)
                return
            }
            session.sendMessage(dictionary, replyHandler: nil, errorHandler: { error in
                loanController?.noteUrgentSendFailed()
                if urgentOnly {
                    SportLog.event("wc", "urgent send FAILED (\(error.localizedDescription)) — live hand-back offer NOT queued; the resend loop retries")
                    return
                }
                SportLog.event("wc", "urgent send FAILED (\(error.localizedDescription)) — falling back to the queued path")
                enqueueSuperseding(dictionary)
            })
        }

        stack.loopManager.podBeepsOnManualBolusProbe = { [weak self] in
            self?.loanController.podBeepsOnManualBolus ?? false
        }

        // Runtime for the whole takeover. The watch has one radio, and without a hold the pod's
        // session establishment is throttled the moment the wrist drops — the read ladder then
        // burns its attempts against wall-clock instead of against the pod. The log snapshots
        // bracket the takeover so the phone has both ends of it even if the watch goes dark.
        loanController.onTakeoverRadioHold = { [weak self] holding in
            self?.setKeepalive(holding, reason: "takeover")

            self?.sendLogSnapshot(holding ? "takeover start" : "takeover verdict")
        }

        loanController.onHandbackRuntimeHold = { [weak self] holding in
            self?.setKeepalive(holding, reason: "handback")
            SportLog.event("loan", holding
                ? "hand-back runtime hold ACQUIRED — staying reachable for the phone's ack"
                : "hand-back runtime hold released")
        }

        // Everything that is true for the duration of a loan and false outside one, armed and
        // disarmed in one place so the two halves cannot drift. Each half is the mirror of the
        // other: watchdog armed/cleared, log pulse started/stopped, heartbeat on/off, and a
        // phase notification either way so the pages repaint on the transition itself.
        loanController.onLoanActiveChanged = { [weak self] active in
            guard let self = self else { return }
            if active {
                os_log("Loan active: starting G7 transport", log: self.log, type: .default)

                self.setKeepalive(true, reason: "loanWorkout")

                LoopStallWatchdog.refresh()
                SportLog.event("deadman", "ladder ARMED — 20/40m timeSensitive + 1/2h critical rungs [deadman]")

                NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)

                self.startLogPulse()

                RuntimeStateLog.startHeartbeat()
            } else {
                os_log("Loan ended: stopping G7 transport", log: self.log, type: .default)
                self.setKeepalive(false, reason: "loanWorkout")
                LoopStallWatchdog.disarm()
                SportLog.event("deadman", "ladder CLEARED — loan ended, coverage transfers to the phone [deadman]")
                self.stopLogPulse()
                RuntimeStateLog.stopHeartbeat()

                self.sendLogSnapshot("loan end")

                // Loop mode is per session. A "closed" left standing makes the NEXT grant — one
                // that inherits an open phone — read as a closed-to-open transition and fire a
                // temp cancel at a pod that is still mid-takeover.
                self.stack.loopManager.resetClosedLoopForSessionEnd()

                NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)
            }
        }

        // LAST, and only now: a saved loan resumes into a controller whose closures are all in
        // place, so its first send, keepalive hold and phase notification go somewhere.
        loanController.resumeIfNeeded()

        let build = BuildDetails.default.codeIdentity
        SportLog.event("session", "Sport Mode ready — build \(build); tap Start to request a loan\(Self.launchForensics())")
        startLinkCensus()

        // There is deliberately NO radio arbiter between the G7 and the pod: the pod link is
        // taken per cycle and dropped, and the G7 is gated only while it has no sensor to talk
        // to. Whether the G7's scanning contends with pod BLE on the single watch radio is
        // UNMEASURED — one clean run is not a proof — so treat a takeover that fails during a
        // sensor acquisition as a candidate, not a coincidence.
        SportLog.event("policy", "link policy AUTOMATIC (#101): pod orphaned between doses, reclaim per cycle, acquisition-gated while un-adopted")
    }

    private static let previousLaunchKey = "SportMode.previousLaunchAt"

    /// Two numbers that cannot be reconstructed after the fact: how long ago this process last
    /// launched, and its resident footprint. A relaunch loop is only visible as a run of small
    /// gaps, and a process killed for memory reports nothing at all — the footprint on the
    /// PREVIOUS launch line is the only evidence of what jetsam saw.
    ///
    /// It WRITES the launch stamp as it reads it, so it must be called exactly once per launch.
    private static func launchForensics() -> String {
        let now = Date()
        let previous = UserDefaults.standard.object(forKey: previousLaunchKey) as? Date
        UserDefaults.standard.set(now, forKey: previousLaunchKey)
        let sincePrevious = previous.map { String(format: "%.0fs", now.timeIntervalSince($0)) } ?? "first"
        return " · sincePrevLaunch=\(sincePrevious) footprint=\(residentFootprint())"
    }

    private static func residentFootprint() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard ok == KERN_SUCCESS else { return "?" }
        return String(format: "%.0fMB", Double(info.phys_footprint) / 1024 / 1024)
    }

    /// Pushes the wrist's log to the phone at the moments the analysis cares about. `reason` is
    /// logged first, so the copy that arrives carries the line explaining why it was sent.
    /// File transfers are queued by WatchConnectivity and survive the phone being away.
    func sendLogSnapshot(_ reason: String) {
        guard WCSession.default.activationState == .activated, let url = LogFile.url else { return }
        SportLog.event("log", "snapshot → iPhone (\(reason))")
        WCSession.default.transferFile(url, metadata: ["kind": "g7watch.log"])
    }

    private var logPulse: DispatchSourceTimer?

    /// While a loan runs, ship the log every five minutes: the wrist may be about to go dark, and
    /// the tail that never left the watch is the part that would have explained why.
    ///
    /// The timer also re-drives the keepalive, which is how a hold survives a wake that finds
    /// holders but no live session. With no whole-loan hold the app is often suspended when this
    /// is due, so it fires late — that lateness is itself the measurement.
    private func startLogPulse() {
        stopLogPulse()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 300, repeating: 300, leeway: .seconds(20))
        timer.setEventHandler { [weak self] in
            self?.sendLogSnapshot("loan pulse")

            self?.keepalive.ensureRunning()
        }
        timer.resume()
        logPulse = timer
    }

    private func stopLogPulse() {
        logPulse?.cancel()
        logPulse = nil
    }

    /// Claims loan traffic and leaves everything else alone — false means "not mine", so the
    /// caller must go on to the stock watch app's own handling. The channel is carried through
    /// because the controller logs it: diags arriving while acks do not is a wedged immediate
    /// channel, and neither arriving is a dead inbound path.
    func handleIncomingIfLoanMessage(_ userInfo: [String: Any], channel: LoanTransportChannel) -> Bool {
        guard userInfo[LoanProtocol.userInfoKey] != nil else { return false }
        loanController.handleIncoming(userInfo: userInfo, channel: channel)
        return true
    }

    private var linkCensusTimer: DispatchSourceTimer?

    /// A minute-by-minute record of the link, taken UNCONDITIONALLY of loan state. Reachability
    /// is otherwise only ever logged as a side effect of a send, so the record goes silent in
    /// exactly the stretch where nothing was sent — and the phone runs the same census, because
    /// the two directions have disagreed.
    private func startLinkCensus() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
        t.setEventHandler {
            let s = WCSession.default
            SportLog.event("link", "phone reachable=\(s.isReachable) activation=\(s.activationState.rawValue) companionInstalled=\(s.isCompanionAppInstalled)")
        }
        t.resume()
        linkCensusTimer = t
    }

    /// Session activation is the first moment anything can be sent, so it is where the debts of a
    /// relaunch are settled: a takeover interrupted by the relaunch is failed to the phone, and a
    /// parked drain re-offers its records. Nothing else kicks either of them.
    func sessionDidActivate() {
        loanController.drainRecoveredIfNeeded()
    }
}
