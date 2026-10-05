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
    /// runs after the store write lands, and only when it stored a reading the store lacked.
    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(deviceQueue))
        log.default("CGMManager:%{public}@ did update with %{public}@", String(describing: type(of: manager)), String(describing: readingResult))
        processCGMReadingResult(manager, readingResult: readingResult) { storedNewGlucose in
            let now = self.now()

            if storedNewGlucose, self.claimCGMLoopTrigger(at: now) {
                self.log.default("Triggering loop from new CGM data at %{public}@", String(describing: now))
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
    /// Completes with stock's `storedNewGlucose`: whether the write stored anything.
    private func processCGMReadingResult(_ manager: CGMManager, readingResult: CGMReadingResult, completion: @escaping (_ storedNewGlucose: Bool) -> Void) {
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
            guard !values.isEmpty else { completion(false); return }
            Task {
                var storedNewGlucose = false
                do {
                    storedNewGlucose = try await !self.glucoseStore.addGlucoseSamples(values).isEmpty

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
                completion(storedNewGlucose)
            }
        case .unreliableData:
            // Stock cancels a high temp here; unreachable, as G7SensorKit never reports `.unreliableData`.
            log.default("CGM reported unreliable data")
            completion(false)
        case .noData:
            completion(false)
        case .error(let error):
            // Stock records this as the device manager's last error, for the phone's status UI.
            // There is no equivalent surface on the wrist, so it is logged and dropped.
            log.error("CGM reading error: %{public}@", String(describing: error))
            completion(false)
        }
    }

    /// Logged and dropped. Stock persists these to a `cgmEventStore` for later upload; the wrist
    /// has no such store and nothing to upload to.
    func cgmManager(_ manager: CGMManager, hasNew events: [PersistedCgmEvent]) {
        log.default("CGM event(s): %{public}d", events.count)
    }

    /// The phone's reading as a gap-filler while the wrist owns the alarms (the caller gates on the
    /// loan), including mid-takeover and mid-resume. Guards, in order: syncId latch (correct under
    /// the async-add race), newer than stored, the store's dedup. A stored reading goes to the
    /// glucose alerts too, as the watch's own readings do; it runs a cycle only once a pod is held.
    func ingestPhoneGlucose(_ sample: NewGlucoseSample) {
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
                self.evaluateGlucoseAlerts([sample])
                SportLog.event("glucose",
                    "INGEST src=phone-relay stored=1/1 · latest \(mgdl) mg/dL age \(Int(self.now().timeIntervalSince(sample.date)))s (direct-G7 gap)")
                SportLog.event("loan", "phone-BG fallback: ingested \(mgdl) mg/dL syncId=\(sample.syncIdentifier ?? "?") (direct-G7 gap) — triggering loop")
                if self.claimCGMLoopTrigger(at: self.now()) {
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

                if self.claimCGMLoopTrigger(at: self.now()) {
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
        // No CGM kit keeps local state yet.
        guard let manager = watchCGMManager(adopting: configuration, localState: nil) else {
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

    /// Device-log sink for the CGM and pump managers. While the watch holds the pod every line goes
    /// to stock's device log, as stock `DeviceDataManager` writes it (a pump's lines always: the
    /// watch has a pump only during a loan); the text log gets each line headed by manager, throttled.
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        log.default("Device %{public}@: %{public}@", deviceIdentifier ?? "unknown", message)

        if let deviceLog, manager is PumpManager || pumpManager != nil {
            deviceLog.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: deviceIdentifier, type: type, message: message, completion: completion)
        } else {
            completion?(nil)
        }

        let source = manager is CGMManager ? "cgm" : "pod-ble"

        let line = "\(type) \(deviceIdentifier ?? "—"): \(message)"
        switch deviceLogThrottle.admit(line, at: now()) {
        case .suppress:
            return
        case .write(let flushing):
            if flushing > 0 {
                SportLog.event(source, "(previous line repeated ×\(flushing) — suppressed)")
            }
        }
        SportLog.event(source, line)
    }

    // MARK: - Alerts
    // Presented on the wrist, and recorded in stock's `AlertStore` as stock's `AlertManager`
    // records them: an issue only while the watch holds the pod, so the store holds the loans'
    // alerts; an acknowledgement or retraction whenever its record is there. The lookups answer
    // from the store, as stock's do.

    /// The watch is the only device hearing the pump during a loan.
    func issueAlert(_ alert: LoopKit.Alert) {
        log.default("Alert issued: %{public}@", alert.identifier.value)
        SportLog.event("alert", "ISSUED \(alert.identifier.value) — \(alert.backgroundContent.title): \(alert.backgroundContent.body)")
        WatchAlertPresenter.present(alert)
        guard pumpManager != nil else { return }
        recordAlert { await $0.recordIssued(alert: alert) }
    }

    /// Withdraw it. A driver retracts when the condition clears, and an alarm left standing after
    /// the pod recovered costs the next one its weight.
    func retractAlert(identifier: LoopKit.Alert.Identifier) {
        log.default("Alert retracted: %{public}@", identifier.value)
        SportLog.event("alert", "RETRACTED \(identifier.value)")
        WatchAlertPresenter.retract(identifier)
        recordAlert { try? await $0.recordRetraction(of: identifier) }
    }

    /// Every alert from one manager still standing on the wrist, withdrawn.
    func retractStandingAlerts(managerIdentifier: String) async {
        let standing = (try? await lookupAllUnretracted(managerIdentifier: managerIdentifier)) ?? []
        for persisted in standing { await retractAlert(identifier: persisted.alert.identifier) }
    }

    /// The wrist's OK or dismissal, recorded as stock `AlertManager.acknowledgeAlert` records it,
    /// whatever the alert's manager made of it.
    func recordAlertAcknowledgement(_ identifier: LoopKit.Alert.Identifier) {
        recordAlert { try? await $0.recordAcknowledgement(of: identifier) }
    }

    func doesIssuedAlertExist(identifier: LoopKit.Alert.Identifier) async throws -> Bool {
        guard let alertStore = await settledAlertStore() else { return false }
        return try await !alertStore.lookupAllMatching(identifier: identifier).isEmpty
    }

    func lookupAllUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        guard let alertStore = await settledAlertStore() else { return [] }
        return try await alertStore.lookupAllUnretracted(managerIdentifier: managerIdentifier).compactMap(Self.persistedAlert)
    }

    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        guard let alertStore = await settledAlertStore() else { return [] }
        return try await alertStore.lookupAllUnacknowledgedUnretracted(managerIdentifier: managerIdentifier).compactMap(Self.persistedAlert)
    }

    func recordRetractedAlert(_ alert: LoopKit.Alert, at date: Date) {
        log.default("Retracted alert recorded: %{public}@", alert.identifier.value)
        guard pumpManager != nil else { return }
        recordAlert { try? await $0.recordRetractedAlert(alert, at: date) }
    }

    /// Runs after every record asked for before it.
    func recordAlert(_ record: @escaping (AlertStore) async -> Void) {
        guard let alertStore else { return }
        alertRecordsLock.lock()
        defer { alertRecordsLock.unlock() }
        let previous = alertRecords
        alertRecords = Task {
            await previous?.value
            await record(alertStore)
        }
    }

    /// The store, once every record asked for so far has landed.
    func settledAlertStore() async -> AlertStore? {
        alertRecordsLock.lock()
        let pending = alertRecords
        alertRecordsLock.unlock()
        await pending?.value
        return alertStore
    }

    /// Stock `AlertManager`'s mapping for the lookups.
    static func persistedAlert(_ stored: StoredAlert) throws -> PersistedAlert? {
        guard let alert = try LoopKit.Alert(from: stored, adjustedForStorageTime: false) else { return nil }
        return PersistedAlert(alert: alert, issuedDate: stored.issuedDate, retractedDate: stored.retractedDate,
                              acknowledgedDate: stored.acknowledgedDate)
    }
}

extension WatchLoopManager: DoseStoreDelegate {
    /// The store nets basal-relative doses against this, so it must be the GRANT's schedule —
    /// the same one the algorithm runs on — and not anything the wrist derived locally.
    func scheduledBasalHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        try await settingsProvider.getBasalHistory(startDate: start, endDate: end)
    }

    /// Stock uses this to trigger a remote upload. So does the wrist, while a loan carries
    /// upload services; otherwise a no-op. Pump events also travel home in the loan journal.
    func doseStoreHasUpdatedPumpEventData(_ doseStore: DoseStore) {
        LoanRemoteUploads.shared.trigger(.pumpEvent)
    }
}
