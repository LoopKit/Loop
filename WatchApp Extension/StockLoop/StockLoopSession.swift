//
//  StockLoopSession.swift
//  WatchApp Extension
//
//  Owns the assembled loop and the loan controller and wires them to each other and to
//  WatchConnectivity. Every closure is installed before a saved loan resumes.
//

import Foundation
import LoopCore
import WatchConnectivity
import os.log

final class StockLoopSession {
    let stack: StockLoopStack.Stack

    /// Held only across takeover and hand-back; timers during a loan fire late.
    private let keepalive = WorkoutKeepalive()

    /// Holds are refcounted by `reason`, which must be stable per caller.
    private func setKeepalive(_ holding: Bool, reason: String) {
        holding ? keepalive.acquire(reason) : keepalive.release(reason)
    }

    /// Restart a session the system ended while holders remain.
    func ensureKeepalive() { keepalive.ensureRunning() }
    let loanController: PodLoanWatchController

    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "StockLoopSession")

    /// Fails only if the stores cannot be opened; then there is no Sport Mode at all.
    init?() async {
        guard let assembled = await StockLoopStack.assemble() else { return nil }
        stack = assembled
        loanController = PodLoanWatchController(loopManager: stack.loopManager)

        RuntimeStateLog.startMainStallDetector()

        loanController.isPhoneReachable = { WCSession.default.isReachable }

        // The per-cycle renewal is the phone's liveness signal.
        stack.loopManager.onCycleLanded = { [weak loanController] in loanController?.renewHold() }
        stack.loopManager.onLoopOpened = { [weak loanController] in loanController?.endPreMealOverride(reason: "loop opened on the wrist") }

        // Cancel queued requests that have not started transferring: delivered at reunion they could
        // re-grant over a running loan.
        loanController.cancelQueuedLoanRequests = {
            let stale = WCSession.default.outstandingUserInfoTransfers.filter {
                LoanMessage.peekKind(transport: $0.userInfo) == "request" && !$0.isTransferring
            }
            stale.forEach { $0.cancel() }
            return stale.count
        }

        // sendMessage when reachable, transferUserInfo otherwise; every send logs its channel.
        loanController.send = { [weak loanController] dictionary in

            let session = WCSession.default

            let wedged = loanController?.urgentSendWedged ?? false
            let urgent = LoanMessage.isInteractiveHandshake(transport: dictionary)
                && session.isReachable && !wedged
            SportLog.event("wc", "send \(dictionary.keys.joined(separator: ",")) — session \(session.activationState.rawValue), reachable \(session.isReachable), path \(urgent ? "urgent" : "queued")")

            // At most one queued hand-back offer. Capture the stale list before enqueueing, cancel after.
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
                SportLog.event("wc", "superseded \(cancelled.count) queued offer(s) with the fresh one")
            }

            // A live hand-back offer is never queued: accepted late, it would split the pod.
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

        // The loan's history, one queued file at close. Files whose transfer has finished are
        // removed first; the system may still be reading one that is outstanding.
        loanController.transferLoanHistory = { data, metadata in
            let session = WCSession.default
            guard session.activationState == .activated,
                  let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return false }
            let directory = caches.appendingPathComponent("LoanHistory", isDirectory: true)
            let outstanding = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
            for old in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            where !outstanding.contains(old.lastPathComponent) {
                try? FileManager.default.removeItem(at: old)
            }
            let url = directory.appendingPathComponent("history-\(UUID().uuidString).plist")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url)
            } catch {
                SportLog.event("wc", "loan history file NOT written — \(error.localizedDescription)")
                return false
            }
            session.transferFile(url, metadata: metadata)
            return true
        }

        // Runtime for the whole takeover, bracketed by log snapshots.
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

        // Everything that holds only for the length of a loan, armed and disarmed together.
        loanController.onLoanActiveChanged = { [weak self] active in
            guard let self = self else { return }
            if active {
                os_log("Loan active: starting G7 transport", log: self.log, type: .default)

                LoopStallWatchdog.refresh()
                SportLog.event("deadman", "ladder ARMED — 20/40m + 1/2h rungs, time-sensitive [deadman]")

                NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)

                self.startLogPulse()

                RuntimeStateLog.startHeartbeat()
            } else {
                os_log("Loan ended: stopping G7 transport", log: self.log, type: .default)
                LoopStallWatchdog.disarm()
                SportLog.event("deadman", "ladder CLEARED — loan ended, coverage transfers to the phone [deadman]")
                self.stopLogPulse()
                RuntimeStateLog.stopHeartbeat()

                self.sendLogSnapshot("loan end")

                // Loop mode is per session.
                self.stack.loopManager.resetClosedLoopForSessionEnd()

                NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)
            }
        }

        // Last, with every closure in place.
        loanController.resumeIfNeeded()

        let build = BuildDetails.default.codeIdentity
        SportLog.event("session", "Sport Mode ready — build \(build); tap Start to request a loan\(Self.launchForensics())")
        startLinkCensus()

        // No radio arbiter between G7 and pod; contention during acquisition is unmeasured.
        SportLog.event("policy", "link policy AUTOMATIC: pod orphaned between doses, reclaim per cycle, acquisition-gated while un-adopted")
    }

    private static let previousLaunchKey = "SportMode.previousLaunchAt"

    /// Time since the last launch and resident footprint. Writes the stamp: call once per launch.
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

    /// Queued file transfer to the phone; the reason is logged first.
    func sendLogSnapshot(_ reason: String) {
        guard WCSession.default.activationState == .activated, let url = LogFile.url else { return }
        SportLog.event("log", "snapshot → iPhone (\(reason))")
        WCSession.default.transferFile(url, metadata: ["kind": "g7watch.log"])
    }

    private var logPulse: DispatchSourceTimer?

    /// Every five minutes during a loan; also re-drives the keepalive. Its lateness is data.
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

    /// false: not loan traffic; the caller continues with stock handling.
    func handleIncomingIfLoanMessage(_ userInfo: [String: Any], channel: LoanTransportChannel) -> Bool {
        guard userInfo[LoanProtocol.userInfoKey] != nil else { return false }
        loanController.handleIncoming(userInfo: userInfo, channel: channel)
        return true
    }

    private var linkCensusTimer: DispatchSourceTimer?

    /// One line a minute on the link, regardless of loan state.
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

    /// The first moment anything can be sent: fail an interrupted takeover, re-offer a parked drain.
    func sessionDidActivate() {
        loanController.drainRecoveredIfNeeded()
    }
}
