//
//  WatchLoopManager+Glucose.swift
//  WatchApp Extension
//
//  The watch's G7 and the phone's relayed reading feed the one store the loop doses from.
//  Both paths run on `deviceQueue`; each guard holds even though store writes can overlap.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchConnectivity
import os.log

extension WatchLoopManager: CGMManagerDelegate {
    /// Stock asserts main here; on the wrist the delegate queue is `deviceQueue`.
    func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(deviceQueue))
        return glucoseStore.latestGlucose?.startDate
    }

    /// Stock `DeviceDataManager.cgmManager(_:hasNew:)`, including the 4.2-minute gate; the cycle
    /// runs after the store write lands.
    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(deviceQueue))
        log.default("CGMManager:%{public}@ did update with %{public}@", String(describing: type(of: manager)), String(describing: readingResult))
        processCGMReadingResult(manager, readingResult: readingResult) {
            let now = self.now()

            if case .newData = readingResult, now.timeIntervalSince(self.lastCGMLoopTrigger) > .minutes(4.2) {
                self.log.default("Triggering loop from new CGM data at %{public}@", String(describing: now))
                self.lastCGMLoopTrigger = now

                self.checkPumpDataAndLoop()
            }

            if case .newData = readingResult {
                Self.queueLogTransferThrottled()
            }
        }
    }

    /// Newest stored reading from either source; for the watch's own radio use `lastGlucoseSourceStamps.direct`.
    var latestGlucoseAge: TimeInterval? {
        return glucoseStore.latestGlucose.map { self.now().timeIntervalSince($0.startDate) }
    }

    /// 4.5 minutes, deliberately NOT 5. Readings land every ~4.98-5.0 min, so a 5-minute gate
    /// races the cadence and skips alternate transfers, halving the log's resolution.
    private static var lastLogTransfer = Date.distantPast
    static func queueLogTransferThrottled() {
        guard Date().timeIntervalSince(lastLogTransfer) > 4.5 * 60 else { return }
        guard WCSession.default.activationState == .activated, let url = LogFile.url else { return }
        lastLogTransfer = Date()
        WCSession.default.transferFile(url, metadata: ["kind": "g7watch.log"])
    }

    /// Stock `processCGMReadingResult` plus a source stamp and a post-write check; no staleness
    /// monitor. Glucose alerts see every delivered reading, as stock's do. The phone's relay of the
    /// same reading carries the same sync identifier, so the store's own dedup drops the second.
    private func processCGMReadingResult(_ manager: CGMManager, readingResult: CGMReadingResult, completion: @escaping () -> Void) {
        switch readingResult {
        case .newData(let values):
            let deliveredCount = values.count
            let latest = values.max(by: { $0.date < $1.date })
            let latestDesc: String = {
                guard let s = latest else { return "none" }
                let mgdl = Int(s.quantity.doubleValue(for: .milligramsPerDeciliter).rounded())
                return "\(mgdl) mg/dL age \(Int(self.now().timeIntervalSince(s.date)))s"
            }()
            let batchTag = deliveredCount > 1 ? " BATCH(backfill+live)" : ""

            // Stamped on arrival, since the phone's relay of the same reading usually lands first.
            if deliveredCount > 0 { self.noteGlucoseSource(directG7: true) }
            if !values.isEmpty { self.evaluateGlucoseAlerts(values) }

            SportLog.event("glucose",
                "INGEST src=direct-G7 n=\(deliveredCount) · latest \(latestDesc)\(batchTag)")
            guard !values.isEmpty else { completion(); return }
            Task {
                do {
                    _ = try await self.glucoseStore.addGlucoseSamples(values)

                    // A successful write has left the store pinned to an older sample before; check it moved.
                    if let newest = values.map(\.date).max(),
                       (self.glucoseStore.latestGlucose?.startDate ?? .distantPast) < newest.addingTimeInterval(-1) {
                        SportLog.event("glucose", "STORE LATEST IS STALE after a write — wrote up to \(newest), store says \(self.glucoseStore.latestGlucose.map { String(describing: $0.startDate) } ?? "nil") [glucose-store]")
                    }
                } catch {
                    self.log.error("Failure adding glucose samples: %{public}@", String(describing: error))
                    SportLog.event("glucose", "STORE WRITE FAILED — \(values.count) reading(s) NOT written: \(error) [glucose-store]")
                }

                self.dataAccessQueue.async { self.publishOwnGlucoseContextWhenIdle() }
                completion()
            }
        case .unreliableData:
            // Stock cancels a high temp here; unreachable, as G7SensorKit never reports `.unreliableData`.
            log.default("CGM reported unreliable data")
            completion()
        case .noData:
            completion()
        case .error(let error):
            // Stock records this as the device manager's last error, for the phone's status UI.
            // There is no equivalent surface on the wrist, so it is logged and dropped.
            log.error("CGM reading error: %{public}@", String(describing: error))
            completion()
        }
    }

    /// Logged and dropped. Stock persists these to a `cgmEventStore` for later upload; the wrist
    /// has no such store and nothing to upload to.
    func cgmManager(_ manager: CGMManager, hasNew events: [PersistedCgmEvent]) {
        log.default("CGM event(s): %{public}d", events.count)
    }

    /// The phone's reading as a gap-filler while a pod is held, from `phoneRelayContext`. Guards,
    /// in order: syncId latch (correct under the async-add race), newer than stored, the store's dedup.
    @MainActor
    func ingestPhoneGlucoseFromContext() {
        guard pumpManager != nil else { return }

        guard let ctx = ExtensionDelegate.sharedIfAvailable()?.loopManager.phoneRelayContext,
              let sample = ctx.newGlucoseSample else { return }
        deviceQueue.async {
            if sample.syncIdentifier == self.lastPhoneFallbackSyncId { return }
            self.lastPhoneFallbackSyncId = sample.syncIdentifier

            if let latest = self.glucoseStore.latestGlucose?.startDate, latest >= sample.date { return }
            Task {
                do {
                    // Empty when the watch's own reading of this sample is already stored.
                    guard try await !self.glucoseStore.addGlucoseSamples([sample]).isEmpty else { return }
                } catch {
                    self.log.error("phone-BG fallback add failed: %{public}@", String(describing: error))
                    return
                }
                let mgdl = Int(sample.quantity.doubleValue(for: .milligramsPerDeciliter))
                // Stamped AFTER the write, unlike the direct path. The relay arrives constantly;
                // only a reading that actually filled a gap counts as the phone having delivered.
                self.noteGlucoseSource(directG7: false)
                SportLog.event("glucose",
                    "INGEST src=phone-relay stored=1/1 · latest \(mgdl) mg/dL age \(Int(self.now().timeIntervalSince(sample.date)))s (direct-G7 gap)")
                SportLog.event("loan", "phone-BG fallback: ingested \(mgdl) mg/dL syncId=\(sample.syncIdentifier ?? "?") (direct-G7 gap) — triggering loop")
                let now = self.now()
                if now.timeIntervalSince(self.lastCGMLoopTrigger) > .minutes(4.2) {
                    self.lastCGMLoopTrigger = now
                    self.checkPumpDataAndLoop()
                }
            }
        }
    }

    #if targetEnvironment(simulator)

    /// Simulator only: the phone's context stands in for a CGM.
    @MainActor
    func simIngestPhoneGlucose() {
        let ctx = ExtensionDelegate.sharedIfAvailable()?.loopManager.activeContext
        guard let quantity = ctx?.glucose, let date = ctx?.glucoseDate else { return }
        deviceQueue.async {
            if let latest = self.glucoseStore.latestGlucose?.startDate, latest >= date { return }
            let sample = NewGlucoseSample(
                date: date,
                quantity: quantity,
                condition: nil,
                trend: ctx?.glucoseTrend,
                trendRate: ctx?.glucoseTrendRate,
                isDisplayOnly: false,
                wasUserEntered: false,
                syncIdentifier: "sim-\(Int(date.timeIntervalSince1970))")
            Task {
                do {
                    _ = try await self.glucoseStore.addGlucoseSamples([sample])
                } catch {
                    self.log.error("SIM glucose add failed: %{public}@", String(describing: error))
                }

                let now = self.now()
                if now.timeIntervalSince(self.lastCGMLoopTrigger) > .minutes(4.2) {
                    self.lastCGMLoopTrigger = now
                    SportLog.event("sim", "SIM CGM \(Int(quantity.doubleValue(for: .milligramsPerDeciliter))) mg/dL (phone sim) — triggering real loop")
                    self.checkPumpDataAndLoop()
                }
            }
        }
    }
    #endif

    /// Ignored: the phone owns sensor enrolment.
    func cgmManagerWantsDeletion(_ manager: CGMManager) {
        log.default("CGM manager requested deletion (ignored on watch)")
    }

    /// Persisted as stock persists a CGM manager, with the configuration it was built from.
    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        guard (manager as AnyObject) === (cgmManager as AnyObject?) else { return }
        var raw = manager.watchRawValue
        raw[Self.builtFromKey] = cgmBuiltFrom
        cgmManagerState.wrappedValue = raw
    }

    /// The phone's CGM configuration arrived. Build from it only when it differs from the one the
    /// current manager was built from (a new sensor or code), so the watch keeps its own link.
    func adoptCGMConfiguration(_ configuration: SharedDeviceConfiguration) {
        if cgmManager != nil, let builtFrom = cgmBuiltFrom, (builtFrom as NSDictionary).isEqual(to: configuration.state) {
            return
        }
        guard let manager = watchCGMManager(adopting: configuration) else {
            SportLog.event("cgm", "phone's CGM (\(configuration.managerIdentifier)) cannot be read from the watch — no CGM here")
            return
        }
        SportLog.event("cgm", "CGM manager built from the phone's configuration (\(configuration.managerIdentifier))")
        installCGMManager(manager, builtFrom: configuration.state)
        cgmManagerDidUpdateState(manager)
    }

    /// The previous manager lets go of its device before the new one takes over.
    func installCGMManager(_ manager: CGMManager, builtFrom: [String: Any]?) {
        cgmLock.lock()
        let previous = _cgmManager
        _cgmManager = manager
        cgmBuiltFrom = builtFrom
        cgmLock.unlock()
        if let previous {
            previous.cgmManagerDelegate = nil
            previous.delete {}
        }
        manager.delegateQueue = deviceQueue
        manager.cgmManagerDelegate = self
        seedLastDirectG7At(manager.cgmManagerStatus.lastCommunicationDate)
    }

    /// Constant, so a relaunch finds the stored credentials.
    func credentialStoragePrefix(for manager: CGMManager) -> String {
        return "com.loopkit.Loop.WatchLoopManager"
    }

    /// Logged only; the wrist has no onboarding or status UI.
    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        log.default("CGM status did update")
    }

    /// Device-log sink for the CGM and pump managers, headed by manager and throttled.
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        log.default("Device %{public}@: %{public}@", deviceIdentifier ?? "unknown", message)

        let source = manager is CGMManager ? "cgm" : "pod-ble"

        let line = "\(type) \(deviceIdentifier ?? "—"): \(message)"
        switch deviceLogThrottle.admit(line, at: now()) {
        case .suppress:
            completion?(nil)
            return
        case .write(let flushing):
            if flushing > 0 {
                SportLog.event(source, "(previous line repeated ×\(flushing) — suppressed)")
            }
        }
        SportLog.event(source, line)
        completion?(nil)
    }

    // MARK: - Alerts
    // Presented on the wrist; nothing is persisted, so the lookups answer empty.

    /// The watch is the only device hearing the pump during a loan.
    func issueAlert(_ alert: LoopKit.Alert) {
        log.default("Alert issued: %{public}@", alert.identifier.value)
        SportLog.event("alert", "ISSUED \(alert.identifier.value) — \(alert.backgroundContent.title): \(alert.backgroundContent.body)")
        WatchAlertPresenter.present(alert)
    }

    /// Withdraw it. A driver retracts when the condition clears, and an alarm left standing after
    /// the pod recovered costs the next one its weight.
    func retractAlert(identifier: LoopKit.Alert.Identifier) {
        log.default("Alert retracted: %{public}@", identifier.value)
        SportLog.event("alert", "RETRACTED \(identifier.value)")
        WatchAlertPresenter.retract(identifier)
    }

    func doesIssuedAlertExist(identifier: LoopKit.Alert.Identifier) async throws -> Bool {
        false
    }

    func lookupAllUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        []
    }

    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        []
    }

    func recordRetractedAlert(_ alert: LoopKit.Alert, at date: Date) {
        log.default("Retracted alert recorded: %{public}@", alert.identifier.value)
    }
}

extension WatchLoopManager: DoseStoreDelegate {
    /// The store nets basal-relative doses against this, so it must be the GRANT's schedule —
    /// the same one the algorithm runs on — and not anything the wrist derived locally.
    func scheduledBasalHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        try await settingsProvider.getBasalHistory(startDate: start, endDate: end)
    }

    /// Deliberately empty. Stock uses this to trigger a remote upload; the wrist has no upload
    /// services, and its pump events travel home in the loan journal instead.
    func doseStoreHasUpdatedPumpEventData(_ doseStore: DoseStore) {
    }
}
