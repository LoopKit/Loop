//
//  PodLoanPhoneController+Wiring.swift
//  Loop
//
//  How the phone's loan controller is wired to the stock managers. The controller takes injected
//  closures so its state machine is testable without the app; this is the one place those
//  closures are built from the real DeviceDataManager, LoopDataManager, SettingsManager and the
//  WatchConnectivity session.
//
//  Two rules run through the whole file. Every write to therapy settings hops to MAIN — one
//  writer, one thread, or the settings screen and the algorithm disagree about what is enabled.
//  And nothing here calls back into the controller synchronously: these closures run on its
//  serial queue, and several of the managers below dispatch back onto it.
//

import HealthKit
import UIKit
import WatchConnectivity
import LoopAlgorithm
import LoopKit
import LoopCore

extension WatchDataManager {
    func makePodLoanController() -> PodLoanPhoneController {
        return PodLoanPhoneController(dependencies: .init(
            pumpManager: { [weak self] in self?.deviceManager.pumpManager },
            settings: { [weak self] in self?.settingsManager.loopSettings ?? LoopSettings() },
            setAutomaticDosingPaused: { [weak self] paused in
                guard let self = self else { return }
                if paused {
                    self.deviceManager.alertManager?.clearLoopNotRunningNotificationsForLoanGrant()
                } else {
                    // Must hop to main. This closure runs on the controller's serial queue, and
                    // rescheduling reads a gate that dispatches synchronously back onto that
                    // same queue — called inline it deadlocks.
                    DispatchQueue.main.async { [weak self] in

                        Task { await self?.deviceManager.alertManager?.rescheduleLoopNotRunningNotifications(Date()) }
                    }
                }
            },
            // The transport. Interactive moments ride `sendMessage`, which is delivered now or
            // not at all; background bookkeeping rides `transferUserInfo`, which is explicitly
            // non-urgent and may sit until the phone wakes. Size and path go to the log FILE on
            // both channels — a send that fails for size leaves nothing else to correlate
            // against.
            send: { [weak self] dictionary in
                guard let session = self?.watchSession else { return }

                let kind: String? = LoanMessage.peekKind(transport: dictionary)

                let size = (dictionary[LoanProtocol.userInfoKey] as? Data)?.count ?? 0

                // Keep at most one dormant grant queued. It is whole-book and latest-only, so an
                // unreachable watch is owed one copy, not one per refresh.
                if kind == "dormantGrant" {
                    for transfer in session.outstandingUserInfoTransfers
                    where LoanMessage.peekKind(transport: transfer.userInfo) == "dormantGrant" {
                        transfer.cancel()
                    }
                }
                guard LoanMessage.isInteractiveHandshake(transport: dictionary),
                      session.isReachable else {
                    self?.log.default("Loan send kind=%{public}@ path=queued (interactive=%{public}@ reachable=%{public}@ bytes=%{public}d)",
                                      kind ?? "?", String(describing: LoanMessage.isInteractiveHandshake(transport: dictionary)),
                                      String(describing: session.isReachable), size)
                    PhoneLog.event("wc", "send \(kind ?? "?") path=queued bytes=\(size) (interactive=\(LoanMessage.isInteractiveHandshake(transport: dictionary)) reachable=\(session.isReachable))")
                    session.transferUserInfo(dictionary)
                    return
                }

                // A grant rides BOTH channels. The urgent send can report success and still
                // never arrive when the wrist goes down moments later, and no error means no
                // fallback; the queued copy is the insurance. The watch rejects whichever
                // duplicate arrives second by epoch.
                let grantRidesBothChannels = (kind == "grant")
                self?.log.default("Loan send kind=%{public}@ path=urgent bytes=%{public}d", kind ?? "?", size)
                PhoneLog.event("wc", "send \(kind ?? "?") path=urgent\(grantRidesBothChannels ? "+queued" : "") bytes=\(size)")
                session.sendMessage(dictionary, replyHandler: nil, errorHandler: { [weak self] error in
                    guard !grantRidesBothChannels else {
                        PhoneLog.event("wc", "urgent send FAILED grant — \(error.localizedDescription) — the queued copy carries it")
                        return
                    }
                    self?.log.error("Loan urgent send FAILED kind=%{public}@ — %{public}@ — falling back to queued", kind ?? "?", String(describing: error))
                    PhoneLog.event("wc", "urgent send FAILED \(kind ?? "?") bytes=\(size) — \(error.localizedDescription) — falling back to queued")
                    session.transferUserInfo(dictionary)
                })
                if grantRidesBothChannels { session.transferUserInfo(dictionary) }
            },
            addPumpEvents: { [weak self] events, lastReconciliation, completion in
                guard let self = self else { completion(nil); return }

                // `replacePendingEvents: false`. Every loan dose is immutable by the time it
                // reaches here — the still-open one is held back — so replacing would purge the
                // phone's own in-flight temp whenever a post-reclaim write lands.
                Task {
                    do {
                        try await self.deviceManager.doseStore.addPumpEvents(events, lastReconciliation: lastReconciliation, replacePendingEvents: false)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            },
            addCarb: { [weak self] entry, syncIdentifier, completion in
                guard let self = self else { completion(nil); return }

                // The identity-accepting ingestion path. Plain `addCarbEntry` mints a fresh
                // identity on every call, so a resent record becomes a second meal.
                Task {
                    do {
                        _ = try await withCheckedThrowingContinuation { (c: CheckedContinuation<StoredCarbEntry, Error>) in
                            self.deviceManager.carbStore.addCarbEntry(entry, syncIdentifier: syncIdentifier) { c.resume(with: $0) }
                        }
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            },

            // Deletes through the same door swipe-to-delete uses, so the entry leaves every
            // store that knows about it. Identity first; failing that, start date within a
            // second and matching grams. Deleting the WRONG carb is far worse than failing to
            // delete, so a miss reports the whole candidate set rather than guessing — an
            // unreported miss resurrects the carb in the next grant.
            deleteCarb: { [weak self] gone, completion in
                guard let self = self else { completion(nil); return }
                let window = gone.startDate.addingTimeInterval(-.hours(1))
                Task {
                    guard let entries = try? await self.deviceManager.carbStore.getCarbEntries(start: window) else { completion(nil); return }
                    let match = entries.first { entry in
                        if let id = gone.syncIdentifier, let entryID = entry.syncIdentifier { return id == entryID }
                        return abs(entry.startDate.timeIntervalSince(gone.startDate)) < 1
                            && abs(entry.quantity.doubleValue(for: .gram) - gone.grams) < 0.01
                    }
                    guard let victim = match else {
                        let lineup = entries.map { e in
                            String(format: "%.0fg@%@ sync=%@", e.quantity.doubleValue(for: .gram),
                                   DateFormatter.localizedString(from: e.startDate, dateStyle: .none, timeStyle: .medium),
                                   e.syncIdentifier.map { String($0.prefix(8)) } ?? "nil")
                        }.joined(separator: " | ")
                        self.log.default("PODLOAN carb delete: no match for %.0f g @ %{public}@ · candidates: %{public}@",
                                         gone.grams, String(describing: gone.startDate), lineup)
                        completion(NSError(domain: "PodLoan.carbDelete", code: 404, userInfo: [
                            NSLocalizedDescriptionKey: "no match among \(entries.count) candidate(s): \(lineup)"]))
                        return
                    }
                    do {
                        _ = try await self.deviceManager.carbStore.deleteCarbEntry(victim)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            },

            watchAppInstalled: { WCSession.isSupported() && WCSession.default.isWatchAppInstalled },
            // The READER matters as much as the writer. Unwired it answers "the phone holds no
            // override" forever, which inverts a clear arriving from the wrist: a preset the
            // user switched off there never switches off here and outlives the loan.
            scheduleOverride: { [weak self] in
                self?.temporaryPresetsManager.scheduleOverride
            },
            applyScheduleOverride: { [weak self] override in

                self?.temporaryPresetsManager.scheduleOverride = override
            },

            // The wrist's loop mode coming home. A therapy-settings write, so it goes through
            // main like every other one — written from the controller's queue, the settings
            // screen goes on showing the mode the user left behind.
            noteWatchClosedLoop: { [weak self] closed in
                DispatchQueue.main.async {
                    self?.settingsManager.mutateLoopSettings { $0.dosingEnabled = closed }
                }
            },
            lastLoopCompleted: { [weak self] in

                self?.loopDataManager.lastLoopCompleted
            },
            noteWatchLoopCompleted: { [weak self] date in
                DispatchQueue.main.async {
                    self?.loopDataManager.seedLastLoopCompleted(fromWatch: date)
                }
            },
            doseHistory: { [weak self] start, completion in
                guard let self = self else { completion([]); return }
                Task {
                    completion((try? await self.deviceManager.doseStore.getNormalizedDoseEntries(start: start)) ?? [])
                }
            },
            // History seeds are converted into the loan's OWN wire types here, at the store
            // boundary. The wire format is ours, so it versions independently of how LoopKit's
            // own types evolve.
            carbHistory: { [weak self] start, completion in
                guard let self = self else { completion([]); return }

                self.deviceManager.carbStore.getCarbEntries(start: start) { result in
                    guard case .success(let entries) = result else { completion([]); return }
                    completion(entries.map { e in
                        LoanCarbRecord(syncIdentifier: e.syncIdentifier,
                                       provenanceIdentifier: e.provenanceIdentifier,
                                       syncVersion: e.syncVersion,
                                       startDate: e.startDate,
                                       grams: e.quantity.doubleValue(for: .gram),
                                       absorptionTime: e.absorptionTime,
                                       foodType: e.foodType,
                                       userCreatedDate: e.userCreatedDate,
                                       userUpdatedDate: e.userUpdatedDate)
                    })
                }
            },
            glucoseHistory: { [weak self] start, completion in
                guard let self = self else { completion([]); return }

                Task {
                    guard let samples = try? await self.deviceManager.glucoseStore.getGlucoseSamples(start: start, end: nil) else { completion([]); return }
                    let mgdl = LoopUnit.milligramsPerDeciliter
                    let mgdlPerMin = mgdl.unitDivided(by: .minute)
                    completion(samples.map { s in
                        LoanGlucoseRecord(syncIdentifier: s.syncIdentifier,
                                          startDate: s.startDate,
                                          valueMgdl: s.quantity.doubleValue(for: mgdl),
                                          trendRateMgdlPerMin: s.trendRate?.doubleValue(for: mgdlPerMin),
                                          isDisplayOnly: s.isDisplayOnly,
                                          wasUserEntered: s.wasUserEntered)
                    })
                }
            },
            issueNotice: { [weak self] title, body in
                self?.log.error("PodLoan notice: %{public}@ - %{public}@", title, body)
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "podloan.notice.\(UUID().uuidString)", content: content, trigger: nil))
            },
            // What makes the pump tile re-render. Posted on main, and after the controller has
            // already published its mirror — the observer reads that mirror, so publishing
            // afterwards would draw the state the phone has just left.
            ownershipDidChange: { [weak self] in

                DispatchQueue.main.async {
                    guard let deviceManager = self?.deviceManager else { return }
                    NotificationCenter.default.post(name: .PumpManagerChanged, object: deviceManager)
                }
            },
            // Defaults to true for a pump that cannot be lent at all: such a pump never enters a
            // settle, and reporting its link as down would stall one that had no reason to run.
            isConnectionReady: { [weak self] in

                (self?.deviceManager.pumpManager as? PumpConnectionLendable)?.isConnectionReady ?? true
            },
            // The cancel at the END of a loan: the watch left a temp running and had no link to
            // stop it, so the phone does it once the pod answers.
            cancelTempBasalAfterPodReturn: { [weak self] completion in

                guard let self = self else { return completion(nil) }
                Task {
                    do {
                        try await self.loopDataManager.cancelTempBasalAfterPodReturn()
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            },
            // The cancel at the START of one, and the grant waits on its completion — the pod
            // must acknowledge it before the link is released, or a program crosses the
            // boundary and the phone's books hold a temp that never finished.
            cancelTempBasalForGrant: { [weak self] completion in

                guard let self = self else { return completion(nil) }
                Task {
                    do {
                        try await self.loopDataManager.cancelTempBasalForPodLoan(reason: .podLoanGrant)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            },
            // Opening the loop turns the user's own setting OFF, deliberately — it is not the
            // loan's dosing pause. A pause would be matched by a resume at the end of the next
            // loan and would silently re-close a loop the audit opened. Turning it back on is
            // the user's act.
            openLoopForUncertainReconciliation: { [weak self] in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    self.settingsManager.mutateLoopSettings { $0.dosingEnabled = false }
                }
            },
            issueUrgentNotice: { [weak self] title, body in

                self?.log.error("PodLoan URGENT: %{public}@ - %{public}@", title, body)
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "podloan.urgent.\(UUID().uuidString)", content: content, trigger: nil))
            },
            // The manual-dose door, not the pump-event one. It is what lets the placeholder keep
            // the identifier it was given, which is the only handle the delete above has.
            bookGapDose: { [weak self] entry, completion in

                guard let self = self else { return completion(false) }
                Task {
                    do {
                        try await self.deviceManager.doseStore.addDoses([entry], from: nil)
                        completion(true)
                    } catch {
                        completion(false)
                    }
                }
            },
            // The store finds the dose by its identifier alone, so this stub exists only to
            // carry one. Its dates and value are never read.
            deleteGapDose: { [weak self] syncIdentifier, completion in
                guard let self = self else { return completion(false) }

                let stub = DoseEntry(type: .bolus, startDate: Date(), endDate: Date(),
                                     value: 0, unit: .units, decisionId: nil, syncIdentifier: syncIdentifier,
                                     manuallyEntered: true)
                self.deviceManager.doseStore.deleteDose(stub) { error in
                    completion(error == nil)
                }
            },
            // The upsert door, by store identity. It is the only way to land a rate record
            // behind the delivery store's immutable boundary, and it bypasses the store's own
            // reconciliation — the caller truncates and stamps delivered units before this.
            backfillDoses: { [weak self] doses, completion in

                guard let self = self else { completion(nil); return }
                Task {
                    do {
                        try await self.deviceManager.doseStore.syncDoseEntries(doses)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            },

            insulinHistoryRewritten: { [weak self] earliestStart in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    // Skipped, not deferred, when the device is still locked: this is a display
                    // refresh, the next cycle repaints anyway, and reaching the stores before
                    // first unlock is what traps a background launch.
                    guard UIApplication.shared.isProtectedDataAvailable else {
                        PhoneLog.event("loan", "insulinHistoryRewritten display refresh SKIPPED — protected data locked (pre-first-unlock launch); the next cycle repaints [locked-launch]")
                        return
                    }
                    self.loopDataManager.insulinHistoryRewritten(startingAt: earliestStart)

                }
            },
            // Launch-time store work waits for first unlock. A reboot mid-loan relaunches Loop
            // in the background with every store file still locked, and touching them there
            // traps seconds into the launch.
            whenProtectedDataAvailable: { work in
                DispatchQueue.main.async {
                    if UIApplication.shared.isProtectedDataAvailable {
                        work()
                    } else {
                        PhoneLog.event("loan", "launch store work DEFERRED — protected data locked (pre-first-unlock launch); resuming on unlock [locked-launch]")
                        var token: NSObjectProtocol?
                        token = NotificationCenter.default.addObserver(
                            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                            object: nil, queue: .main) { _ in
                            if let token = token { NotificationCenter.default.removeObserver(token) }
                            work()
                        }
                    }
                }
            },

            // `beginBackgroundTask` is one of the few UIKit calls that is safe off the main
            // thread, which is why the reclaim hold can run straight from the controller's queue
            // instead of hopping and losing the moments it exists to protect.
            beginReclaimBackgroundTask: { [weak self] in self?.beginReclaimBackgroundTask() },
            endReclaimBackgroundTask: { [weak self] in self?.endReclaimBackgroundTask() },
            isWatchReachable: { [weak self] in self?.watchSession?.isReachable ?? false },
            isBluetoothPoweredOff: { [weak self] in self?.deviceManager.bluetoothProvider.bluetoothState == .poweredOff },
            lastWatchContactAt: { [weak self] in self?.lockedLastWatchContact.value ?? nil },
            latestGlucoseDate: { [weak self] in self?.deviceManager.glucoseStore.latestGlucose?.startDate }
        ))
    }
}
