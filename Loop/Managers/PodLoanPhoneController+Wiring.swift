//
//  PodLoanPhoneController+Wiring.swift
//  Loop
//
//  Builds the controller's injected closures from the real managers. Settings writes hop to
//  main; nothing here calls back into the controller synchronously.
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
            // A phone that has released the pump does not warn that it is not looping.
            pumpControlChanged: { [weak self] released in
                Task { @MainActor in
                    guard let alertManager = self?.deviceManager.alertManager else { return }
                    if released {
                        alertManager.removeLoopNotRunningNotificationsForReleasedPump()
                    } else {
                        await alertManager.rescheduleLoopNotRunningNotifications(Date())
                    }
                }
            },
            // Interactive messages ride sendMessage; bookkeeping rides transferUserInfo.
            send: { [weak self] dictionary in
                guard let session = self?.watchSession else { return }

                let kind: String? = LoanMessage.peekKind(transport: dictionary)

                // At most one dormant grant queued: it is latest-only.
                if kind == "dormantGrant" {
                    for transfer in session.outstandingUserInfoTransfers
                    where LoanMessage.peekKind(transport: transfer.userInfo) == "dormantGrant" {
                        transfer.cancel()
                    }
                }
                guard LoanMessage.isInteractiveHandshake(transport: dictionary),
                      session.isReachable else {
                    session.transferUserInfo(dictionary)
                    return
                }

                // A grant, a query and an answer ride both channels; the watch drops the later duplicate.
                let ridesBothChannels = LoanMessage.ridesBothChannels(transport: dictionary)
                session.sendMessage(dictionary, replyHandler: nil, errorHandler: { error in
                    guard !ridesBothChannels else { return }
                    PhoneLog.event("wc", "urgent send of \(kind ?? "a message") failed, sending it queued: \(error.localizedDescription)")
                    session.transferUserInfo(dictionary)
                })
                if ridesBothChannels { session.transferUserInfo(dictionary) }
            },
            addPumpEvents: { [weak self] events, lastReconciliation, completion in
                guard let self = self else { completion(nil); return }

                // No replacement: loan doses are immutable here, and replacing would purge the phone's own temp.
                Task {
                    do {
                        try await self.deviceManager.doseStore.addPumpEvents(events, lastReconciliation: lastReconciliation, replacePendingEvents: false)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            },
            addCarb: { [weak self] entry, completion in
                guard let self = self else { completion(nil); return }

                // Under the entry's own identity, so a resent record is not a second meal.
                Task {
                    do {
                        _ = try await self.deviceManager.carbStore.addCarbEntry(entry)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            },

            // Deletes as swipe-to-delete does: by identity, else start date and grams. A miss logs the
            // candidates instead of guessing.
            deleteCarb: { [weak self] gone, completion in
                guard let self = self else { completion(nil); return }
                let window = gone.startDate.addingTimeInterval(-.hours(1))
                Task {
                    guard let entries = try? await self.deviceManager.carbStore.getCarbEntries(start: window) else { completion(nil); return }
                    guard let victim = entries.first(where: gone.matches) else {
                        let lineup = entries.map { e in
                            String(format: "%.0fg@%@ sync=%@", e.quantity.doubleValue(for: .gram),
                                   DateFormatter.localizedString(from: e.startDate, dateStyle: .none, timeStyle: .medium),
                                   e.syncIdentifier.map { String($0.prefix(8)) } ?? "nil")
                        }.joined(separator: " | ")
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
            watchReadsCGM: { [weak self] in
                (self?.deviceManager.cgmManager as? DeviceConfigurationSharing)?.isConfigurationSharingEnabled == true
            },
            // Without the reader, a clear from the wrist could never switch the phone's override off.
            scheduleOverride: { [weak self] in self?.temporaryPresetsManager.scheduleOverride },
            applyScheduleOverride: { [weak self] override, changedAt in
                self?.temporaryPresetsManager.setScheduleOverride(override, changedAt: changedAt)
            },

            // The wrist's loop mode coming home.
            noteWatchClosedLoop: { [weak self] closed in
                self?.settingsManager.mutateLoopSettings { $0.dosingEnabled = closed }
            },
            lastLoopCompleted: { [weak self] in

                self?.loopDataManager.lastLoopCompleted
            },
            volatilityBaseline: { [weak self] in
                self?.loopDataManager.volatilityBaseline?.value
            },
            noteWatchLoopCompleted: { [weak self] date in
                self?.loopDataManager.seedLastLoopCompleted(fromWatch: date)
            },
            doseHistory: { [weak self] start, completion in
                guard let self = self else { completion([]); return }
                Task {
                    completion((try? await self.deviceManager.doseStore.getNormalizedDoseEntries(start: start)) ?? [])
                }
            },
            // History seeds become the loan's own wire types at the store boundary.
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
                                       userUpdatedDate: e.userUpdatedDate,
                                       createdByCurrentApp: e.createdByCurrentApp)
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
            overrideHistory: { [weak self] start, completion in
                Task { @MainActor in
                    completion(self?.temporaryPresetsManager.presetHistory.getOverrideHistory(startDate: start, endDate: .distantFuture) ?? [])
                }
            },
            settingsHistory: { [weak self] start, end, completion in
                Task { @MainActor in
                    guard let settings = self?.settingsManager else { return completion(nil) }
                    do {
                        completion(LoanSettingsHistory(
                            basal: try await settings.getBasalHistory(startDate: start, endDate: end),
                            sensitivity: try await settings.getInsulinSensitivityHistory(startDate: start, endDate: end),
                            carbRatio: try await settings.getCarbRatioHistory(startDate: start, endDate: end),
                            targetRange: try await settings.getTargetRangeHistory(startDate: start, endDate: end)))
                    } catch {
                        completion(nil)
                    }
                }
            },
            glucoseAlertSettings: { [weak self] completion in
                Task { @MainActor in completion(self?.deviceManager.glucoseAlertManager.sharedSettings.encoded) }
            },
            issueNotice: { [weak self] title, body in
                self?.log.default("posted notice %{public}@: %{public}@", title, body)
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "podloan.notice.\(UUID().uuidString)", content: content, trigger: nil))
            },
            // Posted once the change in hand has finished.
            ownershipDidChange: { [weak self] in
                DispatchQueue.main.async {
                    guard let deviceManager = self?.deviceManager else { return }
                    NotificationCenter.default.post(name: .PumpManagerChanged, object: deviceManager)
                }
            },
            // True for a pump that cannot be lent, which never settles.
            isConnectionReady: { [weak self] in

                (self?.deviceManager.pumpManager as? ExclusiveDeviceControl)?.isControlReady ?? true
            },
            // End of a loan: cancel the temp the watch left running.
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
            // Start of a loan: the pod must acknowledge the cancel before the link is released.
            cancelTempBasalForGrant: { [weak self] completion in

                guard let self = self else { return completion(nil) }
                Task {
                    do {
                        try await self.loopDataManager.cancelTempBasalForPodLoan(reason: .pumpControlReleased)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            },
            issueUrgentNotice: { [weak self] title, body in

                self?.log.default("posted time-sensitive notice %{public}@: %{public}@", title, body)
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "podloan.urgent.\(UUID().uuidString)", content: content, trigger: nil))
            },
            // Manual-dose path, so the placeholder keeps the identifier used to delete it.
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
            // Found by identifier alone; the other fields are unused.
            deleteGapDose: { [weak self] syncIdentifier, completion in
                guard let self = self else { return completion(false) }

                let stub = DoseEntry(type: .bolus, startDate: Date(), endDate: Date(),
                                     value: 0, unit: .units, decisionId: nil, syncIdentifier: syncIdentifier,
                                     manuallyEntered: true)
                self.deviceManager.doseStore.deleteDose(stub) { error in
                    completion(error == nil)
                }
            },
            // Identified upsert: lands rate records behind the immutable boundary. Caller pre-truncates.
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

            addDosingDecisions: { [weak self] decisions, completion in
                guard let store = self?.loopDataManager.dosingDecisionStore as? DosingDecisionStore else {
                    return completion(.success(0))
                }
                Task {
                    do {
                        completion(.success(try await PodLoanPhoneController.addNewDosingDecisions(decisions, to: store)))
                    } catch {
                        completion(.failure(error))
                    }
                }
            },

            addAlerts: { [weak self] alerts, completion in
                guard let store = self?.deviceManager.alertManager?.alertStore else { return completion(.success(0)) }
                Task {
                    do {
                        completion(.success(try await store.recordAlerts(fromAnotherDevice: alerts)))
                    } catch {
                        completion(.failure(error))
                    }
                }
            },

            addDeviceLogEntries: { [weak self] entries, completion in
                guard let deviceLog = self?.deviceManager.deviceLog else { return completion(.success(0)) }
                Task {
                    do {
                        completion(.success(try await PodLoanPhoneController.addNewDeviceLogEntries(entries, to: deviceLog)))
                    } catch {
                        completion(.failure(error))
                    }
                }
            },

            insulinHistoryRewritten: { [weak self] earliestStart in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    // Skipped while locked: a display refresh, and touching stores before first unlock traps.
                    guard UIApplication.shared.isProtectedDataAvailable else { return }
                    self.loopDataManager.insulinHistoryRewritten(startingAt: earliestStart)

                }
            },
            // Store work at launch waits for first unlock.
            whenProtectedDataAvailable: { work in
                DispatchQueue.main.async {
                    if UIApplication.shared.isProtectedDataAvailable {
                        work()
                    } else {
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

            beginReclaimBackgroundTask: { [weak self] in self?.beginReclaimBackgroundTask() },
            endReclaimBackgroundTask: { [weak self] in self?.endReclaimBackgroundTask() },
            isWatchReachable: { [weak self] in self?.watchSession?.isReachable ?? false },
            isBluetoothPoweredOff: { [weak self] in self?.deviceManager.bluetoothProvider.bluetoothState == .poweredOff },
            latestGlucoseDate: { [weak self] in self?.deviceManager.glucoseStore.latestGlucose?.startDate }
        ))
    }
}

extension TemporaryPresetsManager {
    /// The setter, with the history recording the change at `date` rather than now; the setter's
    /// own record then finds nothing left to do.
    func setScheduleOverride(_ override: TemporaryScheduleOverride?, changedAt date: Date) {
        presetHistory.recordOverride(override, at: date)
        scheduleOverride = override
    }
}
