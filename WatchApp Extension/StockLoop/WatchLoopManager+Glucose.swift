//
//  WatchLoopManager+Glucose.swift
//  WatchApp Extension
//
//  Where the wrist's glucose comes from, and the CGM manager's other delegate duties.
//
//  TWO sources feed ONE store: the watch's own G7, and the phone's relayed reading filling the
//  gaps when the direct link is down. There is no separate display reading — the store the loop
//  doses from is the same store the glance draws — so every rule here is on the dosing path.
//
//  The CGM delegate runs on `deviceQueue`, not on main as it does on the phone (the queue is
//  installed in `StockLoopStack.assemble`), and the phone-relay path hops onto the same queue so
//  the two sources' guards are evaluated one at a time. The store writes themselves are async
//  and can overlap, which is why each path also carries a guard that is correct under that race.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import G7SensorKit
import WatchConnectivity
import os.log

extension WatchLoopManager: CGMManagerDelegate {
    /// Stock asserts main here; on the wrist the delegate queue is `deviceQueue`.
    func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(deviceQueue))
        return glucoseStore.latestGlucose?.startDate
    }

    /// Mirrors stock `DeviceDataManager.cgmManager(_:hasNew:)`, including the 4.2-minute gate:
    /// the G7 delivers on a 5-minute grid, so one trigger per reading, and a backfill batch of
    /// several readings still fires one cycle rather than one each.
    ///
    /// The trigger sits in the processing completion so the store write has landed before the
    /// cycle reads it — stock gets the same ordering from its `await`. Queuing the log transfer
    /// off a new reading is the watch's own addition.
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

    /// Age of the newest reading IN THE STORE, whatever its source. The phone receives it as
    /// `StatusReport.lastDirectGlucoseAge`, and those names disagree: a phone-relayed reading
    /// makes this look fresh while the watch's own G7 is silent. The value that actually answers
    /// "when did this watch last hear the sensor" is `lastGlucoseSourceStamps.direct`.
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

    /// Mirrors stock `DeviceDataManager.processCGMReadingResult`. It adds a `dropAlreadyStored`
    /// pre-filter, a source stamp and a post-write check, and it drops stock's staleness monitor
    /// and glucose alerts (the wrist has no alert presenter — see `issueAlert`). The
    /// `.unreliableData` and `.error` arms also differ from stock; each is marked at its case.
    private func processCGMReadingResult(_ manager: CGMManager, readingResult: CGMReadingResult, completion: @escaping () -> Void) {
        switch readingResult {
        case .newData(let rawValues):
            let values = rawValues

            dropAlreadyStored(values) { kept in

            let deliveredCount = values.count
            let latest = kept.max(by: { $0.date < $1.date }) ?? values.max(by: { $0.date < $1.date })
            let latestDesc: String = {
                guard let s = latest else { return "none" }
                let mgdl = Int(s.quantity.doubleValue(for: .milligramsPerDeciliter).rounded())
                return "\(mgdl) mg/dL age \(Int(self.now().timeIntervalSince(s.date)))s"
            }()
            let batchTag = deliveredCount > 1 ? " BATCH(backfill+live)" : ""

            // Stamped on ARRIVAL, counting what the manager delivered rather than what the
            // store kept. The phone's relay of the same reading usually lands first, so a stamp
            // taken from the stored row would read "phone" almost always and could never answer
            // the question it exists for: is the watch standing on its own right now?
            if deliveredCount > 0 { self.noteGlucoseSource(directG7: true) }

            SportLog.event("glucose",
                "INGEST src=direct-G7 kept=\(kept.count)/\(deliveredCount) · latest \(latestDesc)\(batchTag)")
            guard !kept.isEmpty else { completion(); return }
            Task {
                do {
                    _ = try await self.glucoseStore.addGlucoseSamples(kept)

                    // A successful write is not proof the store moved: it has stayed pinned to
                    // an older sample across readings while every call reported success, and the
                    // loop then dosed on the stale value. Say so loudly rather than trusting the
                    // return. The one-second slack absorbs sub-second rounding in the row's date.
                    if let newest = kept.map(\.date).max(),
                       (self.glucoseStore.latestGlucose?.startDate ?? .distantPast) < newest.addingTimeInterval(-1) {
                        SportLog.event("glucose", "STORE LATEST IS STALE after a write — wrote up to \(newest), store says \(self.glucoseStore.latestGlucose.map { String(describing: $0.startDate) } ?? "nil") [glucose-store]")
                    }
                } catch {
                    self.log.error("Failure adding glucose samples: %{public}@", String(describing: error))
                    SportLog.event("glucose", "STORE WRITE FAILED — \(kept.count) reading(s) NOT written: \(error) [glucose-store]")
                }

                self.dataAccessQueue.async { self.publishOwnGlucoseContextWhenIdle() }
                completion()
            }
            }
        case .unreliableData:
            // Stock cancels a running HIGH temp here (`receivedUnreliableCGMReading`). This does
            // not, and the branch is unreachable in practice: G7SensorKit never reports
            // `.unreliableData` — it withholds the reading instead. Restore the cancel before
            // wiring up any CGM that does use this case.
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

    /// The phone's reading as a BACKUP source, ingested into the same store the loop doses from.
    /// Only while a pod is held: off-loan the phone is looping for itself and the wrist has no
    /// use for a second copy.
    ///
    /// Reads `phoneRelayContext`, never `activeContext` — during a loan the active context is the
    /// watch's own, so a caller asking "what did the phone last tell us" would be handed the
    /// wrist's reading back and ingest nothing.
    ///
    /// It fills GAPS only, and three guards in this order do that. The syncId latch comes FIRST
    /// because the same sample can arrive several times within milliseconds and the freshness
    /// check below reads the store before the asynchronous add has committed; the latch is the
    /// only one of the three that is correct under that race. Then the reading must be newer than
    /// anything stored, then the cross-device dedup.
    @MainActor
    func ingestPhoneGlucoseFromContext() {
        guard pumpManager != nil else { return }

        guard let ctx = ExtensionDelegate.sharedIfAvailable()?.loopManager.phoneRelayContext,
              let sample = ctx.newGlucoseSample else { return }
        deviceQueue.async {
            if sample.syncIdentifier == self.lastPhoneFallbackSyncId { return }
            self.lastPhoneFallbackSyncId = sample.syncIdentifier

            if let latest = self.glucoseStore.latestGlucose?.startDate, latest >= sample.date { return }
            self.dropAlreadyStored([sample]) { kept in
            guard !kept.isEmpty else { return }
            Task {
                do {
                    _ = try await self.glucoseStore.addGlucoseSamples(kept)
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
    }

    /// The part of a G7 sync identifier that two devices can AGREE on.
    ///
    /// G7SensorKit builds it as `<activatedAt> <sensorID> <sensorTimestamp>`, and the leading
    /// field is each device's OWN estimate of when the sensor was activated — the phone and the
    /// watch latch different values, so the full string never matches for the same physical
    /// reading. Dropping it leaves sensor plus reading timestamp, which is identical on both.
    ///
    /// nil when there is no space to split on, which is what a sensor whose activation time has
    /// not latched yields (`"invalid"`); the caller then keeps the sample.
    private static func sensorIdentity(_ syncIdentifier: String?) -> String? {
        guard let s = syncIdentifier, let sp = s.firstIndex(of: " ") else { return nil }
        let tail = s[s.index(after: sp)...]
        return tail.isEmpty ? nil : String(tail)
    }

    /// Drop readings this store already holds under the other device's name.
    ///
    /// Without it the same physical reading is filed twice, and duplicate ROWS clear
    /// `GlucoseMath`'s `count > 2` floor — which counts rows, not distinct times — so two copies
    /// of one reading manufacture a trend out of nothing.
    ///
    /// FAILS OPEN at every step: no usable identities, an unreadable store, nothing seen in the
    /// window — keep everything. A duplicate row is a mild distortion of momentum; a dropped
    /// reading is a missed loop cycle.
    private func dropAlreadyStored(_ samples: [NewGlucoseSample],
                                   completion: @escaping ([NewGlucoseSample]) -> Void) {
        let wanted = samples.compactMap { Self.sensorIdentity($0.syncIdentifier) }
        guard !wanted.isEmpty else { completion(samples); return }

        // Six readings' worth of lookback, which bounds the store read. A backfill batch that
        // reaches further back than this can still file a duplicate of a row older than the
        // window — accepted, because the alternative is reading the whole cache on every reading.
        let since = self.now().addingTimeInterval(-.minutes(30))
        Task {
            guard let stored = try? await glucoseStore.getGlucoseSamples(start: since, end: nil) else {
                completion(samples)
                return
            }
            let seen = Set(stored.compactMap { Self.sensorIdentity($0.syncIdentifier) })
            guard !seen.isEmpty else { completion(samples); return }
            var dropped: [String] = []
            let kept = samples.filter { s in
                guard let id = Self.sensorIdentity(s.syncIdentifier), seen.contains(id) else { return true }
                dropped.append(id)
                return false
            }
            if !dropped.isEmpty {
                SportLog.event("glucose", "#83 dedup: dropped \(dropped.count) already-filed reading(s) [\(dropped.joined(separator: ", "))] — same sensor stamp, different device name tag")
            }
            completion(kept)
        }
    }

    #if targetEnvironment(simulator)

    /// Simulator only: there is no G7 in the simulator, so the paired phone's context stands in
    /// as a CGM and drives the real cycle. Note it reads `activeContext` and fabricates a sync
    /// identifier, neither of which would be safe on a device.
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

    /// Ignored: the phone owns sensor enrolment and the wrist has no CGM-management UI to
    /// return the user to. Deleting the manager here would leave the watch with no glucose
    /// source and nothing on screen able to restore one.
    func cgmManagerWantsDeletion(_ manager: CGMManager) {
        log.default("CGM manager requested deletion (ignored on watch)")
    }

    /// Also read by `StockLoopStack.assemble` at launch to rebuild the manager from the last
    /// known sensor. One key, two readers — the age escape has to be applied on both paths.
    static let cgmStateDefaultsKey = "g7.cgmManagerRawState"

    /// Persist the G7's raw state, as stock does — except that a nil `sensorID` means UNKNOWN,
    /// not FORGET, and is refused.
    ///
    /// Stock reads a disconnect during pending authentication as the end of a session and nils
    /// the identity. On the wrist that happens after every loan, and persisting the nil can leave
    /// the watch unable to re-authenticate at all, taking ZERO direct readings while the phone's
    /// relay quietly covers for it. The only way out is age: past the sensor's 10-day life plus
    /// 12 hours the clear is honoured. `StockLoopStack.assemble` applies the same escape when it
    /// restores an identity at launch, and it has to — an identity restored past its expiry is
    /// auto-connected to and never gets back here.
    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        guard manager is G7CGMManager else { return }
        let raw = manager.rawState
        let sensorID = raw["sensorID"] as? String

        if sensorID == nil,
           let stored = defaults.dictionary(forKey: Self.cgmStateDefaultsKey),
           let storedID = stored["sensorID"] as? String {
            let activated = stored["activatedAt"] as? Date
            let expired = Self.persistedSensorIsPastLife(activated, now: now())
            if !expired {
                if lastPersistedSensorID != nil {
                    SportLog.event("cgm", "G7 state: manager forgot sensor \(storedID) — KEEPING the persisted identity (#104: nil means unknown, not forget)")
                    lastPersistedSensorID = nil
                }
                return
            }
            SportLog.event("cgm", "G7 state: sensor \(storedID) is past its 10-day life — honouring the clear")
        }

        defaults.set(raw, forKey: Self.cgmStateDefaultsKey)
        if sensorID != lastPersistedSensorID {
            lastPersistedSensorID = sensorID
            SportLog.event("cgm", "G7 state persisted — sensor \(sensorID ?? "none") (survives relaunch/update)")
        }
    }

    /// A CONSTANT where stock returns a fresh UUID per manager instance. The wrist runs one G7
    /// manager for the life of the app and has to find the same stored credentials again after a
    /// relaunch; a new prefix each launch abandons whatever the previous instance wrote.
    func credentialStoragePrefix(for manager: CGMManager) -> String {
        return "com.loopkit.Loop.WatchLoopManager"
    }

    /// Logged only. Stock tracks `hasValidSensorSession` from this to drive its onboarding and
    /// status UI; the wrist has neither, and its own sensor questions are answered by the start
    /// gate and the direct-reading stamps instead.
    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        log.default("CGM status did update")
    }

    /// Device-log sink for BOTH the CGM and the pump managers, which share this delegate.
    ///
    /// The heading comes from the `manager` argument, never from the device name: a flat label
    /// files the pod's BLE errors under a CGM heading and makes a radio problem unreadable.
    ///
    /// Everything is throttled. A retry loop can push thousands of identical lines per second,
    /// each one a synchronous write, which starves main and rotates every piece of real evidence
    /// out of the log inside a second. Suppressed repeats are counted and stated on the next
    /// different line, so the storm is still visible without being recorded in full.
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        log.default("Device %{public}@: %{public}@", deviceIdentifier ?? "unknown", message)

        let source = manager is G7CGMManager ? "cgm" : "pod-ble"

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
    //
    // KNOWN GAP, not an oversight to tidy up. The wrist has no alert presenter, so every LoopKit
    // alert raised while it holds the pod — pod fault, occlusion, low reservoir — reaches os_log
    // and goes no further. And nothing is persisted, so the lookups below answer "nothing
    // stored" rather than pretending to a history this device does not keep. The wrist's own
    // dead-man alarms are pre-scheduled notifications instead (`LoopStallWatchdog`); they are a
    // different mechanism and do not cover these.

    /// Put it on the wrist. While the watch holds the pod it is the only device that can hear
    /// the pump, so a pod fault, an occlusion or an empty reservoir has nowhere else to go —
    /// the phone's alert manager is not watching a pump it does not have.
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
