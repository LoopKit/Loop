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

@MainActor
final class StockLoopSession {
    let stack: StockLoopStack.Stack

    let loanController: PodLoanWatchController

    /// Fails only if the stores cannot be opened; then there is no Sport Mode at all.
    init?() async {
        guard let assembled = await StockLoopStack.assemble() else { return nil }
        stack = assembled
        loanController = PodLoanWatchController(loopManager: stack.loopManager)

        loanController.isPhoneReachable = { WCSession.default.isReachable }
        loanController.isLinkActivated = { WCSession.default.activationState == .activated }

        // The per-cycle renewal is the phone's liveness signal.
        stack.loopManager.onCycleLanded = { [weak loanController] in
            loanController?.renewHold()
        }
        stack.loopManager.onLoopOpened = { [weak loanController] in
            loanController?.endPreMealOverride(reason: "loop opened on the watch")
        }

        // Cancel queued requests that have not started transferring: delivered at reunion they could
        // re-grant over a running loan.
        loanController.cancelQueuedLoanRequests = {
            let stale = WCSession.default.outstandingUserInfoTransfers.filter {
                LoanMessage.peekKind(transport: $0.userInfo) == "request" && !$0.isTransferring
            }
            stale.forEach { $0.cancel() }
            return stale.count
        }

        // sendMessage when reachable, transferUserInfo otherwise.
        loanController.send = { [weak self, weak loanController] dictionary in

            let session = WCSession.default
            // Sent before the link has started up, a message is lost: hold it until it has.
            guard session.activationState == .activated else {
                self?.holdUntilActivated(dictionary)
                return
            }

            let wedged = loanController?.urgentSendWedged ?? false
            let urgent = LoanMessage.isInteractiveHandshake(transport: dictionary)
                && session.isReachable && !wedged
            let ridesBothChannels = urgent && LoanMessage.ridesBothChannels(transport: dictionary)

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
                cancelled.forEach { $0.cancel() }
            }

            guard urgent else {
                enqueueSuperseding(dictionary)
                return
            }
            session.sendMessage(dictionary, replyHandler: nil, errorHandler: { _ in
                loanController?.noteUrgentSendFailed()
                // The queued copy already carries a message that rides both channels.
                guard !ridesBothChannels else { return }
                enqueueSuperseding(dictionary)
            })
            if ridesBothChannels { enqueueSuperseding(dictionary) }
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
                SportLog.event("wc", "could not write the loan history file: \(error.localizedDescription)")
                return false
            }
            session.transferFile(url, metadata: metadata)
            return true
        }

        // Everything that holds only for the length of a loan, armed and disarmed together.
        loanController.onLoanActiveChanged = { [weak self] active in
            guard let self = self else { return }
            if active {
                LoopStallWatchdog.refresh()

                NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)
            } else {
                LoopStallWatchdog.disarm()

                // Loop mode is per session.
                self.stack.loopManager.resetClosedLoopForSessionEnd()

                NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)
            }
        }

        // Last, with every closure in place.
        loanController.resumeIfNeeded()

        SportLog.event("session", "Sport Mode ready, build \(BuildDetails.default.codeIdentity)")
    }

    /// false: not loan traffic; the caller continues with stock handling. From the link's thread.
    nonisolated func handleIncomingIfLoanMessage(_ userInfo: [String: Any]) -> Bool {
        guard userInfo[LoanProtocol.userInfoKey] != nil else { return false }
        loanController.handleIncoming(userInfo: userInfo)
        return true
    }

    /// Messages sent before the link to the phone started up; sent at `sessionDidActivate`.
    private var heldUntilActivated: [[String: Any]] = []
    private let heldLock = NSLock()

    private func holdUntilActivated(_ dictionary: [String: Any]) {
        heldLock.lock()
        heldUntilActivated.append(dictionary)
        heldLock.unlock()
    }

    /// The first moment anything can be sent: what was held goes, then an interrupted takeover is
    /// failed, a parked drain re-offered, and work waiting on the link runs.
    func sessionDidActivate() {
        heldLock.lock()
        let held = heldUntilActivated
        heldUntilActivated = []
        heldLock.unlock()
        held.forEach { loanController.send?($0) }
        loanController.drainRecoveredIfNeeded()
        loanController.linkDidActivate()
    }
}
