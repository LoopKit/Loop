#if LUPED_PEBBLE
import Combine
import Foundation
import LoopAlgorithm
import LoopKit
import LoopKitUI

/// Settings → Devices → Pebble. The property names equal the defaults keys so the
/// transport can observe them with KVO.
extension UserDefaults {
    static let lupedPebbleEnabledKey = "lupedPebbleEnabled"
    static let lupedPebbleWatchfaceUUIDKey = "lupedPebbleWatchfaceUUID"
    static let lupedPebbleAlarmsEnabledKey = "lupedPebbleAlarmsEnabled"
    static let lupedPebbleFollowAlertMuteKey = "lupedPebbleFollowAlertMute"
    static let lupedPebbleFullScreenKey = "lupedPebbleFullScreen"
    static let lupedDefaultWatchfaceUUID = "bf32924c-4839-449e-9e56-ee190249acb2"

    /// Whether a Pebble has been added in Settings → Devices; off until then.
    @objc dynamic var lupedPebbleEnabled: Bool {
        bool(forKey: Self.lupedPebbleEnabledKey)
    }

    /// Deletes the Pebble device: stops the transport and resets its settings.
    func deleteLupedPebble() {
        set(false, forKey: Self.lupedPebbleEnabledKey)
        removeObject(forKey: Self.lupedPebbleAlarmsEnabledKey)
        removeObject(forKey: Self.lupedPebbleFollowAlertMuteKey)
        removeObject(forKey: Self.lupedPebbleFullScreenKey)
        removeObject(forKey: Self.lupedPebbleWatchfaceUUIDKey)
    }

    /// Watch vibration alarms, on unless the user turned them off. Loop's own
    /// alerts are unaffected.
    @objc dynamic var lupedPebbleAlarmsEnabled: Bool {
        object(forKey: Self.lupedPebbleAlarmsEnabledKey) as? Bool ?? true
    }

    /// Mutes watch alarms while Loop's alerts are muted; on unless the user
    /// turned it off.
    @objc dynamic var lupedPebbleFollowAlertMute: Bool {
        object(forKey: Self.lupedPebbleFollowAlertMuteKey) as? Bool ?? true
    }

    /// Full-screen glucose ring instead of ring and graph; off by default.
    @objc dynamic var lupedPebbleFullScreen: Bool {
        bool(forKey: Self.lupedPebbleFullScreenKey)
    }

    @objc dynamic var lupedPebbleWatchfaceUUID: String {
        string(forKey: Self.lupedPebbleWatchfaceUUIDKey) ?? Self.lupedDefaultWatchfaceUUID
    }

    var lupedPebbleWatchfaceUUIDValue: UUID {
        UUID(uuidString: lupedPebbleWatchfaceUUID) ?? UUID(uuidString: Self.lupedDefaultWatchfaceUUID)!
    }
}

/// AppMessage dictionary keys from the Luped watchface's `messageKeys`.
private enum LupedMessageKey {
    static let command: UInt32 = 10_000
    static let data: UInt32 = 10_001
    static let configured: UInt32 = 10_003
    static let diagnostics: UInt32 = 10_004
}

/// Luped's delivery policy for readings.
private enum LupedDelivery {
    /// Backoff for re-sending a rejected or unacknowledged reading. Loop cannot
    /// observe the watchface starting, and Luped asks for data only once.
    static let initialRetryDelay: TimeInterval = 30
    static let maximumRetryDelay: TimeInterval = 300
}

/// Bridges stored Loop glucose to the Luped watchface over a `PebbleTransport`.
///
/// The latest payload is kept so a watchface `refresh` or a new session can
/// re-send it. A rejected or unacknowledged send is retried with backoff, and
/// immediately on a glucose update, a watchface refresh, or a new session.
@MainActor
final class LupedPebbleTransport: PebbleTransportDelegate {
    static let shared = LupedPebbleTransport()

    private let transport = PebbleTransport(
        isEnabled: UserDefaults.standard.lupedPebbleEnabled,
        appUUID: UserDefaults.standard.lupedPebbleWatchfaceUUIDValue
    )

    private let log = DiagnosticLog(category: "LupedPebbleTransport")
    /// The watch communication log shown in Settings → Devices → Pebble.
    let communicationLog = LupedCommunicationLog()
    /// Live link state and watch diagnostics for Settings → Devices → Pebble.
    let status = LupedLinkStatus()

    // AppMessage delivery state
    private var glucoseStore: GlucoseStore?
    private weak var glucoseAlertManager: GlucoseAlertManager?
    private weak var alertMuter: AlertMuter?
    /// Last logged alarm state, so the log records each change once.
    private var alarmStatus: String?
    private var unit = LoopUnit.milligramsPerDeciliter
    private var settingsObservers: Set<AnyCancellable> = []
    private var userSettingsObservers: Set<AnyCancellable> = []
    private var latestPayload: LupedPayload?
    /// Incremented on every send request; a send completing with an older
    /// value means another request arrived while it was in flight.
    private var requestGeneration = 0
    private var deliveredGeneration = 0
    private var inflightPush: (transactionID: UInt8, generation: Int, payload: LupedPayload, sentAt: Date)?
    /// A COMMAND push awaiting the watch's ACK; pushes are sent one at a time.
    private var inflightCommand: (transactionID: UInt8, command: String)?
    private var diagnosticsRequested = false
    private var diagnosticsReplyTimeout: Task<Void, Never>?
    /// Whether Luped has messaged Loop since this session opened. Alloy disables
    /// a watchface's outbox whenever a non-system session (like Loop's) opens or
    /// closes; only a watchface restart re-enables it.
    private var heardFromWatchThisSession = false
    /// Waiting for Luped to start again after Loop restarted it.
    private var awaitingWatchfaceRestart: Task<Void, Never>?
    private var pushAckTimeout: Task<Void, Never>?
    private var retryDelay: TimeInterval = 0
    /// Set after the full retry backoff got no ACK: pushes stop until the
    /// watchface makes contact, a new session opens, or the user sends.
    private var paused = false {
        didSet { status.paused = paused }
    }
    private var pushRetry: Task<Void, Never>?

    /// Writes to Loop's diagnostic log and to the in-app communication log.
    private func record(_ kind: LupedCommunicationLog.Kind, _ message: String) {
        if kind == .error {
            log.error("luped: %{public}@", message)
        } else {
            log.default("luped: %{public}@", message)
        }
        communicationLog.append(kind, message)
    }

    private init() {
        transport.delegate = self
        Publishers.Merge(
            UserDefaults.standard.publisher(for: \.lupedPebbleEnabled).map { _ in () },
            UserDefaults.standard.publisher(for: \.lupedPebbleWatchfaceUUID).map { _ in () }
        )
        .dropFirst(2)
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] in self?.applySettings() }
        .store(in: &userSettingsObservers)
    }

    /// Starts the GATT service if needed and sends the latest stored CGM readings
    /// in Loop's display unit with the active glucose alert settings, re-sending
    /// them whenever the unit or those settings change.
    func publish(from glucoseStore: GlucoseStore, displayGlucosePreference: DisplayGlucosePreference, glucoseAlertManager: GlucoseAlertManager, alertMuter: AlertMuter?) async {
        transport.start()
        self.glucoseStore = glucoseStore
        self.glucoseAlertManager = glucoseAlertManager
        self.alertMuter = alertMuter
        if settingsObservers.isEmpty {
            // Loop starts in mg/dL and switches to the HealthKit unit once it has loaded.
            displayGlucosePreference.$unit
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] unit in
                    Task { await self?.publish(unit: unit) }
                }
                .store(in: &settingsObservers)
            // These publish before the new value is stored; the Task reads it afterwards.
            Publishers.Merge4(
                glucoseAlertManager.$profiles.dropFirst().map { _ in () },
                glucoseAlertManager.$activeProfileID.dropFirst().map { _ in () },
                glucoseAlertManager.$cgmProvidesOwnAlerts.dropFirst().map { _ in () },
                glucoseAlertManager.$loopAlertsOverrideForOwnAlertingCGM.dropFirst().map { _ in () }
            )
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                Task { await self.publish(unit: self.unit) }
            }
            .store(in: &settingsObservers)
            UserDefaults.standard.publisher(for: \.lupedPebbleAlarmsEnabled)
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] enabled in
                    guard let self else { return }
                    self.record(.info, "Watch alarms \(enabled ? "enabled" : "disabled")")
                    Task { await self.publish(unit: self.unit) }
                }
                .store(in: &settingsObservers)
            // Muting and its timed end republish, restoring the watch's alarms.
            alertMuter?.$configuration
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self else { return }
                    Task { await self.publish(unit: self.unit) }
                }
                .store(in: &settingsObservers)
            UserDefaults.standard.publisher(for: \.lupedPebbleFollowAlertMute)
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] follow in
                    guard let self else { return }
                    self.record(.info, "Follow Loop alert mute \(follow ? "enabled" : "disabled")")
                    Task { await self.publish(unit: self.unit) }
                }
                .store(in: &settingsObservers)
            UserDefaults.standard.publisher(for: \.lupedPebbleFullScreen)
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] fullScreen in
                    guard let self else { return }
                    self.record(.info, "Watch display: \(fullScreen ? "full-screen ring" : "ring with graph")")
                    Task { await self.publish(unit: self.unit) }
                }
                .store(in: &settingsObservers)
        }
        await publish(unit: displayGlucosePreference.unit)
    }

    private func publish(unit: LoopUnit) async {
        guard let glucoseStore else {
            return
        }
        self.unit = unit
        // Check the stored setting too: deleting the Pebble resets other settings,
        // whose observers fire before the debounced disable is applied.
        guard transport.isEnabled, UserDefaults.standard.lupedPebbleEnabled else {
            return
        }

        let samples: [StoredGlucoseSample]
        do {
            samples = try await glucoseStore.getGlucoseSamples(start: Date(timeIntervalSinceNow: -LupedPayload.historyInterval))
        } catch {
            record(.error, String(format: "Unable to read glucose: %@", String(describing: error)))
            return
        }

        let muteEnd = alertMuter.flatMap { $0.configuration.shouldMute ? $0.configuration.mutingEndTime : nil }
        let followMute = UserDefaults.standard.lupedPebbleFollowAlertMute
        let alarms = glucoseAlertManager.map { LupedAlarmSettings($0, mutedUntil: followMute ? muteEnd : nil) } ?? .disabled
        let status = LupedAlarmSettings.status(alarms, manager: glucoseAlertManager, loopMuteEnd: muteEnd)
        if status != alarmStatus {
            alarmStatus = status
            record(.info, status)
        }
        guard let payload = LupedPayload(samples: samples, unit: unit, alarms: alarms, fullScreen: UserDefaults.standard.lupedPebbleFullScreen) else {
            record(.info, String(format: "No usable CGM readings among %ld stored samples; nothing to send", samples.count))
            return
        }

        latestPayload = payload
        requestSend()
    }

    // MARK: - Settings

    /// Applies Settings → Devices → Pebble.
    private func applySettings() {
        let enabled = UserDefaults.standard.lupedPebbleEnabled
        let uuid = UserDefaults.standard.lupedPebbleWatchfaceUUIDValue
        guard enabled != transport.isEnabled || uuid != transport.appUUID else {
            return
        }
        record(.info, String(format: "Settings changed: %@ for app %@", enabled ? "enabled" : "disabled", uuid.uuidString))
        transport.reconfigure(isEnabled: enabled, appUUID: uuid)

        guard enabled else {
            // Fully off: no Bluetooth manager, no retries, no payload building.
            pushRetry?.cancel()
            pushRetry = nil
            latestPayload = nil
            record(.info, "Pebble support off: Bluetooth service removed")
            return
        }
        // Build the current reading now rather than waiting for the next one.
        Task { await publish(unit: unit) }
    }

    // MARK: - PebbleTransportDelegate

    func pebbleTransport(_ transport: PebbleTransport, log kind: PebbleLogKind, _ message: String) {
        switch kind {
        case .toWatch: record(.toWatch, message)
        case .fromWatch: record(.fromWatch, message)
        case .info: record(.info, message)
        case .error: record(.error, message)
        }
    }

    func pebbleTransportDidChangeLink(_ transport: PebbleTransport) {
        if status.link != transport.link {
            status.link = transport.link
        }
    }

    func pebbleTransportSessionDidOpen(_ transport: PebbleTransport) {
        sendIfNeeded(force: true)
    }

    func pebbleTransportSessionWillReset(_ transport: PebbleTransport) {
        if inflightPush != nil {
            record(.info, "Session reset before the watch acknowledged the pushed reading")
        }
        inflightPush = nil
        pushAckTimeout?.cancel()
        pushAckTimeout = nil
        // A new session re-sends the reading itself.
        pushRetry?.cancel()
        pushRetry = nil
        retryDelay = 0
        paused = false
        status.retryAt = nil
        inflightCommand = nil
        heardFromWatchThisSession = false
        awaitingWatchfaceRestart?.cancel()
        awaitingWatchfaceRestart = nil
    }

    func pebbleTransport(_ transport: PebbleTransport, didReceive tuples: [UInt32: AppMessageTuple], message: [UInt8]) {
        heardFromWatchThisSession = true
        if awaitingWatchfaceRestart != nil {
            awaitingWatchfaceRestart?.cancel()
            awaitingWatchfaceRestart = nil
            record(.info, "Watchface restarted; it can reply again")
        }
        let hex = PebbleTransport.hex(message.dropFirst(18))
        if let diagnostics = tuples[LupedMessageKey.diagnostics]?.string {
            record(.fromWatch, "Watch diagnostics: \(diagnostics)")
            status.diagnostics = LupedWatchDiagnostics(json: diagnostics)
            status.watchInfoNote = nil
            diagnosticsReplyTimeout?.cancel()
        }
        // Alloy sends a ready handshake (key 15025) when the watchface starts and
        // keeps its own outbox closed until the phone sends any message back;
        // only then does Luped send its `refresh` command. Answer both with the
        // latest reading.
        let command = tuples[LupedMessageKey.command]?.string
        if tuples[PebbleAppMessage.alloyReadyKey] != nil || command == "refresh" {
            record(.fromWatch, "Watchface requested refresh (\(command.map { "COMMAND \($0)" } ?? "ready handshake"), tuples \(hex))")
            sendIfNeeded(force: true)
        } else if tuples[LupedMessageKey.diagnostics] == nil {
            record(.fromWatch, "Watch message (tuples \(hex))")
        }
    }

    func pebbleTransport(_ transport: PebbleTransport, didReceiveReply acknowledged: Bool, transactionID: UInt8, message: [UInt8]) {
        let reply = acknowledged ? "ACK" : "NACK"
        if let pending = inflightCommand, pending.transactionID == transactionID {
            inflightCommand = nil
            record(.fromWatch, "\(reply) for transaction \(transactionID) (bytes \(PebbleTransport.hex(message))): COMMAND \(pending.command)")
            if !acknowledged {
                status.watchInfoNote = NSLocalizedString("The watch rejected the request; the watchface is probably not running.", comment: "Pebble watch info note: request rejected")
            } else {
                awaitDiagnosticsReply()
            }
            sendIfNeeded()
            return
        }
        guard let push = inflightPush, push.transactionID == transactionID else {
            record(.fromWatch, "\(reply) for transaction \(transactionID) (bytes \(PebbleTransport.hex(message))) matches no pending push; ignored")
            return
        }
        inflightPush = nil
        pushAckTimeout?.cancel()
        pushAckTimeout = nil
        let elapsed = Int(Date().timeIntervalSince(push.sentAt) * 1_000)
        let readingTime = DateFormatter.localizedString(from: push.payload.latestDate, dateStyle: .none, timeStyle: .medium)
        if acknowledged {
            record(.fromWatch, "\(reply) for transaction \(transactionID) after \(elapsed) ms (bytes \(PebbleTransport.hex(message))): watch stored reading from \(readingTime), \(push.payload.readingCount) history points")
            deliveredGeneration = push.generation
            pushRetry?.cancel()
            pushRetry = nil
            retryDelay = 0
            paused = false
            status.lastDelivery = .init(readingDate: push.payload.latestDate, deliveredAt: Date(), milliseconds: elapsed)
            status.lastRejectedAt = nil
            status.retryAt = nil
            sendIfNeeded()
        } else {
            // The watch rejects pushes while Luped is not the running watchface.
            record(.fromWatch, "\(reply) for transaction \(transactionID) after \(elapsed) ms (bytes \(PebbleTransport.hex(message))): watch rejected reading from \(readingTime); the watchface is probably not running")
            status.lastRejectedAt = Date()
            scheduleRetry()
        }
    }

    // MARK: - Commands

    /// The Pebble SDK's Alloy runtime disables a watchface's outbox whenever a
    /// non-system session (like Loop's) opens or closes, until the watchface
    /// restarts. The watch still acknowledges the request but cannot answer.
    private func awaitDiagnosticsReply() {
        diagnosticsReplyTimeout?.cancel()
        diagnosticsReplyTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.heardFromWatchThisSession = false
            self.record(.error, "No diagnostics reply within 5 s; the next request restarts the watchface first")
            self.status.watchInfoNote = NSLocalizedString("The watch did not reply. Tap Refresh Watch Info again to restart the watchface and retry.", comment: "Pebble watch info note: no reply")
        }
    }

    /// Pushes the current reading now, re-sending it even if already delivered.
    func sendNow() {
        record(.info, "Send Now requested")
        status.lastResult = nil
        guard transport.isSessionOpen else {
            status.lastResult = "No watch session; the reading is sent as soon as the watch connects."
            Task { await publish(unit: unit) }
            return
        }
        Task {
            // A new reading is pushed by publish itself; force a re-send only
            // when the latest reading was already delivered.
            await publish(unit: unit)
            if inflightPush == nil {
                sendIfNeeded(force: true)
            }
        }
    }

    /// Asks Luped for its diagnostics snapshot (battery and counters). If Luped
    /// has not messaged Loop since this session opened, its outbox is disabled,
    /// so Loop first restarts the watchface over the app run-state endpoint.
    func requestDiagnostics() {
        record(.info, "Watch info requested")
        status.watchInfoNote = nil
        guard transport.isSessionOpen else {
            status.watchInfoNote = NSLocalizedString("The watch is not connected.", comment: "Pebble watch info note: no session")
            return
        }
        diagnosticsRequested = true
        if !heardFromWatchThisSession, awaitingWatchfaceRestart == nil {
            restartWatchface()
        }
        sendPendingCommand()
    }

    /// Stops and relaunches the watchface. On start, Alloy's ready handshake
    /// reaches Loop and Loop's reply re-enables the watchface's outbox.
    private func restartWatchface() {
        status.watchInfoNote = NSLocalizedString("Restarting the watchface so it can reply…", comment: "Pebble watch info note: restarting the watchface")
        record(.toWatch, "App run state STOP for \(transport.appUUID.uuidString) (restart so the watchface can reply)")
        transport.sendAppRunState(run: false)
        awaitingWatchfaceRestart = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.record(.toWatch, "App run state RUN for \(self.transport.appUUID.uuidString)")
            self.transport.sendAppRunState(run: true)
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self.awaitingWatchfaceRestart = nil
            self.diagnosticsRequested = false
            self.record(.error, "The watchface did not start within 15 s")
            self.status.watchInfoNote = NSLocalizedString("The watchface did not restart. Open it on the watch, then try again.", comment: "Pebble watch info note: restart failed")
        }
    }

    private func sendPendingCommand() {
        guard diagnosticsRequested, awaitingWatchfaceRestart == nil, inflightPush == nil, inflightCommand == nil, transport.isSessionOpen else {
            return
        }
        diagnosticsRequested = false
        let transactionID = transport.makeTransactionID()
        inflightCommand = (transactionID, "diagnostics")

        record(.toWatch, "Sending transaction \(transactionID): COMMAND diagnostics")
        transport.push(transactionID: transactionID, tuples: [(LupedMessageKey.command, .cString("diagnostics"))])

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(PebbleAppMessage.ackTimeout * 1_000_000_000))
            guard let self, self.inflightCommand?.transactionID == transactionID else { return }
            self.record(.error, "No reply to transaction \(transactionID) within \(Int(PebbleAppMessage.ackTimeout)) s")
            self.inflightCommand = nil
            self.sendIfNeeded()
        }
    }

    // MARK: - Delivery

    private func requestSend() {
        requestGeneration += 1
        sendIfNeeded()
    }

    /// Pushes the latest payload unless it was already delivered; `force` re-sends
    /// it for a new session or a watchface refresh request.
    private func sendIfNeeded(force: Bool = false) {
        if force {
            requestGeneration = max(requestGeneration, deliveredGeneration + 1)
            paused = false
        } else if paused {
            return
        }
        guard inflightPush == nil, inflightCommand == nil else {
            record(.info, "Send deferred: previous message still in flight")
            return
        }
        guard deliveredGeneration < requestGeneration else {
            sendPendingCommand()
            return
        }
        guard let payload = latestPayload else {
            record(.info, "Send skipped: no payload yet")
            return
        }
        guard transport.isSessionOpen else {
            record(.info, "Send skipped: no watch session")
            return
        }

        let transactionID = transport.makeTransactionID()
        inflightPush = (transactionID, requestGeneration, payload, Date())

        record(.toWatch, "Sending transaction \(transactionID): \(payload.data)\n\(payload.fieldDescription)")
        transport.push(transactionID: transactionID, tuples: [
            (LupedMessageKey.configured, .uint8(1)),
            (LupedMessageKey.data, .cString(payload.data)),
        ])

        pushAckTimeout?.cancel()
        pushAckTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(PebbleAppMessage.ackTimeout * 1_000_000_000))
            guard !Task.isCancelled, let self, self.inflightPush?.transactionID == transactionID else { return }
            self.record(.error, "No reply to transaction \(transactionID) within \(Int(PebbleAppMessage.ackTimeout)) s")
            self.inflightPush = nil
            self.scheduleRetry()
        }
    }

    /// Re-sends the undelivered reading after a growing delay, so a watchface
    /// that starts later still receives it even if its refresh request is lost.
    private func scheduleRetry() {
        guard !paused else { return }
        guard retryDelay < LupedDelivery.maximumRetryDelay else {
            // 30 s + 1 + 2 + 4 + 5 min of rejections: stop until the watch is back.
            pushRetry?.cancel()
            pushRetry = nil
            status.retryAt = nil
            paused = true
            record(.info, "Paused sending: the watchface has not accepted a reading for about 12 minutes. Resumes when it starts, on a new watch session, or with Send Now.")
            return
        }
        retryDelay = retryDelay == 0 ? LupedDelivery.initialRetryDelay : min(retryDelay * 2, LupedDelivery.maximumRetryDelay)
        let delay = retryDelay
        status.retryAt = Date().addingTimeInterval(delay)
        record(.info, String(format: "Retrying in %.0f s", delay))
        pushRetry?.cancel()
        pushRetry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.status.retryAt = nil
            self?.sendIfNeeded()
        }
    }
}

extension LupedAlarmSettings {
    /// Mirrors Loop's active glucose alert profile. Low and high alerts repeat
    /// only when their snooze is enabled; urgent low always repeats. All watch
    /// alarms are off while Loop defers glucose alerts to the CGM's own alerts,
    /// or when the user turned off watch alarms, and until a followed Loop alert
    /// mute ends.
    @MainActor
    init(_ manager: GlucoseAlertManager, mutedUntil: Date?) {
        let configuration = manager.activeConfiguration()
        var mask = 0
        if manager.effectiveLoopAlertsEnabled, UserDefaults.standard.lupedPebbleAlarmsEnabled {
            if configuration.urgentLowEnabled { mask |= Self.urgentLowBit }
            if configuration.lowEnabled { mask |= Self.lowBit }
            if configuration.highEnabled { mask |= Self.highBit }
        }
        let muted = mask != 0 && mutedUntil != nil
        self.init(
            urgentLowMgDL: configuration.urgentLowThresholdMgDL,
            lowMgDL: configuration.lowThresholdMgDL,
            highMgDL: configuration.highThresholdMgDL,
            enabledMask: muted ? 0 : mask,
            urgentLowRepeat: configuration.urgentLowRepeatInterval,
            lowRepeat: configuration.lowSnoozeEnabled ? configuration.lowRepeatInterval : Self.oncePerEpisode,
            highRepeat: configuration.highSnoozeEnabled ? configuration.highRepeatInterval : Self.oncePerEpisode,
            mutedUntil: muted ? mutedUntil : nil
        )
    }

    /// Whether the watch alarms are on, off or muted, and why, for the communication log.
    @MainActor
    static func status(_ alarms: LupedAlarmSettings, manager: GlucoseAlertManager?, loopMuteEnd: Date?) -> String {
        let time = { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) }
        guard let manager else {
            return "Watch alarms off: Loop's glucose alert settings are not available"
        }
        if !UserDefaults.standard.lupedPebbleAlarmsEnabled {
            return "Watch alarms off: Watch Alarms is turned off"
        }
        if !manager.effectiveLoopAlertsEnabled {
            return "Watch alarms off: Loop leaves glucose alerts to the CGM's own alerts"
        }
        if let mutedUntil = alarms.mutedUntil {
            return "Watch alarms muted until \(time(mutedUntil)): Loop's alerts are muted"
        }
        if alarms.enabledMask == 0 {
            return "Watch alarms off: urgent low, low and high alerts are all turned off in Glucose Alert Settings"
        }
        if let loopMuteEnd {
            return "Watch alarms on: Loop's alerts are muted until \(time(loopMuteEnd)), but Follow Loop Alert Mute is turned off"
        }
        return "Watch alarms on"
    }
}

/// Link state and watch diagnostics shown in Settings → Devices → Pebble.
@MainActor
final class LupedLinkStatus: ObservableObject {
    typealias Link = PebbleLinkState

    struct Delivery {
        let readingDate: Date
        let deliveredAt: Date
        let milliseconds: Int
    }

    @Published var link = Link.off
    @Published var lastDelivery: Delivery?
    @Published var lastRejectedAt: Date?
    @Published var retryAt: Date?
    /// Sending paused after the watchface stopped accepting readings.
    @Published var paused = false
    /// Feedback for Send Now or a watch request that could not complete.
    @Published var lastResult: String?
    @Published var diagnostics: LupedWatchDiagnostics?
    /// Why the last watch-info request got no answer, if it did not.
    @Published var watchInfoNote: String?
}

/// Luped's diagnostics snapshot (`DIAGNOSTICS`, format version 2).
struct LupedWatchDiagnostics {
    let receivedAt: Date
    let battery: Int?
    let countingSince: Date?
    let readingsReceived: Int?
    let refreshRequests: Int?
    let urgentLowAlarms: Int?
    let lowAlarms: Int?
    let highAlarms: Int?
    let messagesIn: Int?
    let messagesOut: Int?
    let staleTransitions: Int?
    let phoneDisconnects: Int?
    let phoneDisconnectedSeconds: Int?

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [Any],
              (values.first as? NSNumber)?.intValue == 2
        else {
            return nil
        }
        func int(_ index: Int) -> Int? {
            index < values.count ? (values[index] as? NSNumber)?.intValue : nil
        }
        receivedAt = Date()
        battery = int(2)
        countingSince = int(3).map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) }
        readingsReceived = int(13)
        refreshRequests = int(14)
        urgentLowAlarms = int(16)
        lowAlarms = int(17)
        highAlarms = int(18)
        messagesIn = int(19)
        messagesOut = int(21)
        staleTransitions = int(31)
        phoneDisconnects = int(34)
        phoneDisconnectedSeconds = int(35).map { $0 / 1_000 }
    }
}

/// The most recent watch communication events, newest last, kept in memory.
@MainActor
final class LupedCommunicationLog: ObservableObject {
    enum Kind {
        case toWatch, fromWatch, info, error
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let kind: Kind
        let message: String
    }

    static let capacity = 500

    @Published private(set) var entries: [Entry] = []

    func append(_ kind: Kind, _ message: String) {
        entries.append(Entry(date: Date(), kind: kind, message: message))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Plain text for sharing, oldest first.
    var text: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map { entry in
            let marker: String
            switch entry.kind {
            case .toWatch: marker = "→"
            case .fromWatch: marker = "←"
            case .info: marker = "·"
            case .error: marker = "!"
            }
            return "\(formatter.string(from: entry.date)) \(marker) \(entry.message)"
        }.joined(separator: "\n")
    }
}

#endif
