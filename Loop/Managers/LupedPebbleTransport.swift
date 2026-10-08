#if LUPED_PEBBLE
import Combine
import CoreBluetooth
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
    static let lupedPebbleFullScreenKey = "lupedPebbleFullScreen"
    static let lupedDefaultWatchfaceUUID = "bf32924c-4839-449e-9e56-ee190249acb2"

    /// Enabled unless the user turned it off.
    @objc dynamic var lupedPebbleEnabled: Bool {
        object(forKey: Self.lupedPebbleEnabledKey) as? Bool ?? true
    }

    /// Watch vibration alarms, on unless the user turned them off. Loop's own
    /// alerts are unaffected.
    @objc dynamic var lupedPebbleAlarmsEnabled: Bool {
        object(forKey: Self.lupedPebbleAlarmsEnabledKey) as? Bool ?? true
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
}

/// PebbleOS "Pebble Protocol over GATT" (PPoGATT) constants.
///
/// The phone hosts the PPoGATT service and the watch is the GATT client.
/// PebbleOS discovers every PPoGATT service the phone publishes, reads its meta
/// characteristic, and opens a separate app session for a non-system app UUID.
private enum PPoGATT {
    static let service = CBUUID(string: "10000000-328E-0FBB-C642-1AA6699BDADA")
    static let data = CBUUID(string: "10000001-328E-0FBB-C642-1AA6699BDADA")
    static let meta = CBUUID(string: "10000002-328E-0FBB-C642-1AA6699BDADA")

    // Packet header: sequence number in the upper five bits, type in the lower three.
    static let typeData: UInt8 = 0
    static let typeAck: UInt8 = 1
    static let typeResetRequest: UInt8 = 2
    static let typeResetComplete: UInt8 = 3

    /// Version 0 uses a fixed four-packet window in both directions and needs no
    /// window negotiation; it is ample for one small message per CGM reading.
    static let version: UInt8 = 0
    static let windowSize = 4
    static let sequenceModulus: UInt8 = 32
    static let ackTimeout: TimeInterval = 5
    static let maxRetransmissions = 2
}

/// Pebble Protocol endpoint and AppMessage wire constants used by this transport.
private enum AppMessage {
    static let endpoint: UInt16 = 0x30
    static let push: UInt8 = 0x01
    static let ack: UInt8 = 0xFF
    static let nack: UInt8 = 0x7F

    static let tupleCString: UInt8 = 1
    static let tupleUnsigned: UInt8 = 2

    static let ackTimeout: TimeInterval = 10

    /// Backoff for re-sending a rejected or unacknowledged reading. Loop cannot
    /// observe the watchface starting, and Luped asks for data only once.
    static let initialRetryDelay: TimeInterval = 30
    static let maximumRetryDelay: TimeInterval = 300
}

/// The phone-version exchange PebbleOS starts on every new session.
///
/// Without the 8 KiB AppMessage capability, PebbleOS limits a JS-free
/// watchface's inbox to 144 bytes per message. The watch caches the
/// capability per app UUID and applies it when the watchface next starts.
private enum PhoneVersion {
    static let endpoint: UInt16 = 0x11
    static let request: UInt8 = 0x00

    static let response: Data = {
        var response = Data([0x01]) // Response command
        response.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // Deprecated protocol version
        response.append(contentsOf: [0, 0, 0, 0]) // Deprecated session capabilities
        response.append(contentsOf: [0, 0, 0, 1]) // Platform flags: iOS
        response.append(contentsOf: [2, 4, 4, 2]) // Response version 2, app version 4.4.2
        response.append(contentsOf: [0x20, 0, 0, 0, 0, 0, 0, 0]) // Little-endian: 8 KiB AppMessage support
        return response
    }()
}

/// Bridges stored Loop glucose to the Luped Pebble AppMessage protocol.
///
/// Loop publishes its own PPoGATT service through CoreBluetooth rather than
/// using the legacy PebbleKit iOS SDK, whose watch discovery does not recognize
/// Core Devices watches (Pebble Time 2, Pebble Round 2, Pebble 2 Duo). The
/// watch must be paired with and connected to the Pebble app; it then discovers
/// this service and opens a session for the Luped app UUID.
///
/// The latest payload is kept so a watchface `refresh` or a new session can
/// re-send it. A rejected or unacknowledged send is retried with backoff, and
/// immediately on a glucose update, a watchface refresh, or a new session.
@MainActor
final class LupedPebbleTransport: NSObject, @preconcurrency CBPeripheralManagerDelegate {
    static let shared = LupedPebbleTransport()

    private var isEnabled = UserDefaults.standard.lupedPebbleEnabled
    private var appUUID = UserDefaults.standard.lupedPebbleWatchfaceUUIDValue

    private let log = DiagnosticLog(category: "LupedPebbleTransport")
    /// The watch communication log shown in Settings → Devices → Pebble.
    let communicationLog = LupedCommunicationLog()
    private var peripheralManager: CBPeripheralManager?
    private var dataCharacteristic: CBMutableCharacteristic?
    private var isServicePublished = false

    private enum SessionState {
        case closed
        /// A reset handshake is in progress. After a self-initiated reset, the
        /// watch's Reset Complete must be answered with ours.
        case resetting(selfInitiated: Bool)
        case open
    }

    // PPoGATT session state
    private var watch: CBCentral?
    private var sessionState = SessionState.closed
    private var nextInboundSequence: UInt8 = 0
    private var lastSentAck: UInt8?
    private var nextOutboundSequence: UInt8 = 0
    private var inflightPackets: [(sequence: UInt8, packet: Data)] = []
    private var outboundChunks: [Data] = []
    private var pendingNotifications: [Data] = []
    private var retransmissions = 0
    private var packetAckTimeout: Task<Void, Never>?
    private var inboundFrames = Data()

    // AppMessage delivery state
    private var glucoseStore: GlucoseStore?
    private weak var glucoseAlertManager: GlucoseAlertManager?
    private var unit = LoopUnit.milligramsPerDeciliter
    private var settingsObservers: Set<AnyCancellable> = []
    private var userSettingsObservers: Set<AnyCancellable> = []
    private var latestPayload: LupedPayload?
    /// Incremented on every send request; a send completing with an older
    /// value means another request arrived while it was in flight.
    private var requestGeneration = 0
    private var deliveredGeneration = 0
    private var inflightPush: (transactionID: UInt8, generation: Int, payload: LupedPayload, sentAt: Date)?
    private var nextTransactionID: UInt8 = 0
    private var pushAckTimeout: Task<Void, Never>?
    private var retryDelay: TimeInterval = 0
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

    private static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private override init() {
        super.init()
        Publishers.Merge(
            UserDefaults.standard.publisher(for: \.lupedPebbleEnabled).map { _ in () },
            UserDefaults.standard.publisher(for: \.lupedPebbleWatchfaceUUID).map { _ in () }
        )
        .dropFirst(2)
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] in self?.applySettings() }
        .store(in: &userSettingsObservers)
    }

    private func start() {
        guard isEnabled, peripheralManager == nil else {
            return
        }

        record(.info, String(format: "Starting PPoGATT service for app %@", appUUID.uuidString))
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    /// Starts the GATT service if needed and sends the latest stored CGM readings
    /// in Loop's display unit with the active glucose alert settings, re-sending
    /// them whenever the unit or those settings change.
    func publish(from glucoseStore: GlucoseStore, displayGlucosePreference: DisplayGlucosePreference, glucoseAlertManager: GlucoseAlertManager) async {
        start()
        self.glucoseStore = glucoseStore
        self.glucoseAlertManager = glucoseAlertManager
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
        guard isEnabled else {
            return
        }

        let samples: [StoredGlucoseSample]
        do {
            samples = try await glucoseStore.getGlucoseSamples(start: Date(timeIntervalSinceNow: -LupedPayload.historyInterval))
        } catch {
            record(.error, String(format: "Unable to read glucose: %@", String(describing: error)))
            return
        }

        let alarms = glucoseAlertManager.map(LupedAlarmSettings.init) ?? .disabled
        guard let payload = LupedPayload(samples: samples, unit: unit, alarms: alarms, fullScreen: UserDefaults.standard.lupedPebbleFullScreen) else {
            record(.info, String(format: "No usable CGM readings among %ld stored samples; nothing to send", samples.count))
            return
        }

        latestPayload = payload
        requestSend()
    }

    // MARK: - GATT service

    /// Applies Settings → Devices → Pebble. Removing the service ends the watch's
    /// session; publishing it under a new UUID makes the watch open a new one.
    private func applySettings() {
        let enabled = UserDefaults.standard.lupedPebbleEnabled
        let uuid = UserDefaults.standard.lupedPebbleWatchfaceUUIDValue
        guard enabled != isEnabled || uuid != appUUID else {
            return
        }
        record(.info, String(format: "Settings changed: %@ for app %@", enabled ? "enabled" : "disabled", uuid.uuidString))
        isEnabled = enabled
        appUUID = uuid

        closeSession(reason: "settings changed")
        watch = nil
        peripheralManager?.removeAllServices()
        isServicePublished = false
        dataCharacteristic = nil

        guard enabled else {
            // Fully off: no Bluetooth manager, no retries, no payload building.
            pushRetry?.cancel()
            pushRetry = nil
            peripheralManager?.delegate = nil
            peripheralManager = nil
            latestPayload = nil
            record(.info, "Pebble support off: Bluetooth service removed")
            return
        }
        if let peripheralManager {
            if peripheralManager.state == .poweredOn {
                publishService(on: peripheralManager)
            }
        } else {
            start()
        }
        // Build the current reading now rather than waiting for the next one.
        Task { await publish(unit: unit) }
    }

    private func publishService(on manager: CBPeripheralManager) {
        guard isEnabled, !isServicePublished else {
            return
        }

        var meta = Data([PPoGATT.version, PPoGATT.version])
        meta.append(appUUID.bytes)
        meta.append(0) // Session type inferred from the app UUID: an app session.

        let metaCharacteristic = CBMutableCharacteristic(
            type: PPoGATT.meta,
            properties: .read,
            value: meta,
            permissions: .readable
        )
        let dataCharacteristic = CBMutableCharacteristic(
            type: PPoGATT.data,
            properties: [.writeWithoutResponse, .notify],
            value: nil,
            permissions: .writeable
        )
        let service = CBMutableService(type: PPoGATT.service, primary: true)
        service.characteristics = [metaCharacteristic, dataCharacteristic]

        self.dataCharacteristic = dataCharacteristic
        isServicePublished = true
        manager.add(service)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        record(.info, String(format: "Bluetooth peripheral state %ld", peripheral.state.rawValue))
        switch peripheral.state {
        case .poweredOn:
            publishService(on: peripheral)
        case .poweredOff, .resetting, .unauthorized, .unsupported:
            // iOS drops published services in these states; publish again on power-on.
            isServicePublished = false
            dataCharacteristic = nil
            closeSession(reason: "Bluetooth unavailable")
            watch = nil
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            record(.error, String(format: "Unable to publish PPoGATT service: %@", String(describing: error)))
            isServicePublished = false
            dataCharacteristic = nil
            return
        }
        record(.info, "Published PPoGATT service; waiting for the watch to discover it")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == PPoGATT.data else {
            return
        }
        record(.fromWatch, String(format: "Watch %@ subscribed (max notification %ld bytes); awaiting reset request", central.identifier.uuidString, central.maximumUpdateValueLength))
        closeSession(reason: "watch subscribed again")
        watch = central
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic.uuid == PPoGATT.data, central.identifier == watch?.identifier else {
            return
        }
        record(.fromWatch, String(format: "Watch %@ unsubscribed or disconnected", central.identifier.uuidString))
        closeSession(reason: "watch unsubscribed")
        watch = nil
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == PPoGATT.data else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                continue
            }
            if watch == nil {
                watch = request.central
            }
            if let value = request.value, !value.isEmpty {
                handlePacket([UInt8](value))
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        flushNotifications()
    }

    // MARK: - PPoGATT

    private func handlePacket(_ packet: [UInt8]) {
        let type = packet[0] & 0b111
        let sequence = packet[0] >> 3

        switch type {
        case PPoGATT.typeResetRequest:
            record(.fromWatch, "Watch requested PPoGATT reset")
            resetSessionState()
            sessionState = .resetting(selfInitiated: false)
            sendPacket(type: PPoGATT.typeResetComplete, sequence: 0)
        case PPoGATT.typeResetComplete:
            guard case .resetting(let selfInitiated) = sessionState else {
                record(.info, "Ignoring unexpected PPoGATT reset complete")
                return
            }
            if selfInitiated {
                sendPacket(type: PPoGATT.typeResetComplete, sequence: 0)
            }
            sessionState = .open
            record(.info, "PPoGATT session open")
            sendIfNeeded(force: true)
        case PPoGATT.typeAck:
            guard case .open = sessionState else { return }
            handleAck(sequence)
        case PPoGATT.typeData:
            guard case .open = sessionState else { return }
            if sequence == nextInboundSequence {
                nextInboundSequence = (sequence + 1) % PPoGATT.sequenceModulus
                lastSentAck = sequence
                sendPacket(type: PPoGATT.typeAck, sequence: sequence)
                inboundFrames.append(contentsOf: packet.dropFirst())
                processInboundFrames()
            } else if let lastSentAck {
                // Repeat the last ACK so the watch retransmits from the gap.
                sendPacket(type: PPoGATT.typeAck, sequence: lastSentAck)
            }
        default:
            record(.error, String(format: "Ignoring PPoGATT packet type %d", type))
        }
    }

    private func handleAck(_ sequence: UInt8) {
        // An ACK covers every in-flight packet up to and including its sequence number.
        guard let index = inflightPackets.firstIndex(where: { $0.sequence == sequence }) else {
            return
        }
        inflightPackets.removeFirst(index + 1)
        retransmissions = 0
        if inflightPackets.isEmpty {
            packetAckTimeout?.cancel()
            packetAckTimeout = nil
        } else {
            schedulePacketAckTimeout()
        }
        pumpOutbound()
    }

    /// Splits a Pebble Protocol frame into PPoGATT data packets.
    private func sendFrame(endpoint: UInt16, payload: Data) {
        guard let watch else { return }

        var frame = Data()
        frame.appendBigEndian(UInt16(payload.count))
        frame.appendBigEndian(endpoint)
        frame.append(payload)

        let chunkSize = max(watch.maximumUpdateValueLength - 1, 19)
        var offset = frame.startIndex
        while offset < frame.endIndex {
            let end = min(offset + chunkSize, frame.endIndex)
            outboundChunks.append(frame.subdata(in: offset..<end))
            offset = end
        }
        pumpOutbound()
    }

    private func pumpOutbound() {
        while inflightPackets.count < PPoGATT.windowSize, !outboundChunks.isEmpty {
            let sequence = nextOutboundSequence
            nextOutboundSequence = (sequence + 1) % PPoGATT.sequenceModulus
            var packet = Data([sequence << 3 | PPoGATT.typeData])
            packet.append(outboundChunks.removeFirst())
            inflightPackets.append((sequence, packet))
            enqueueNotification(packet)
            schedulePacketAckTimeout()
        }
    }

    private func schedulePacketAckTimeout() {
        packetAckTimeout?.cancel()
        packetAckTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(PPoGATT.ackTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.handlePacketAckTimeout()
        }
    }

    private func handlePacketAckTimeout() {
        guard !inflightPackets.isEmpty else { return }
        retransmissions += 1
        guard retransmissions <= PPoGATT.maxRetransmissions else {
            record(.error, "Watch stopped acknowledging data; resetting PPoGATT session")
            resetSessionState()
            sessionState = .resetting(selfInitiated: true)
            sendPacket(type: PPoGATT.typeResetRequest, sequence: 0, payload: [PPoGATT.version])
            return
        }
        record(.toWatch, String(format: "Retransmitting %ld unacknowledged packet(s)", inflightPackets.count))
        inflightPackets.forEach { enqueueNotification($0.packet) }
        schedulePacketAckTimeout()
    }

    private func sendPacket(type: UInt8, sequence: UInt8, payload: [UInt8] = []) {
        enqueueNotification(Data([sequence << 3 | type] + payload))
    }

    private func enqueueNotification(_ packet: Data) {
        pendingNotifications.append(packet)
        flushNotifications()
    }

    /// Sends queued notifications until CoreBluetooth's transmit queue is full;
    /// `peripheralManagerIsReady(toUpdateSubscribers:)` resumes the flush.
    private func flushNotifications() {
        guard let peripheralManager, let dataCharacteristic, let watch else {
            pendingNotifications.removeAll()
            return
        }
        while let packet = pendingNotifications.first {
            guard peripheralManager.updateValue(packet, for: dataCharacteristic, onSubscribedCentrals: [watch]) else {
                return
            }
            pendingNotifications.removeFirst()
        }
    }

    private func resetSessionState() {
        if inflightPush != nil {
            record(.info, "Session reset before the watch acknowledged the pushed reading")
        }
        nextInboundSequence = 0
        lastSentAck = nil
        nextOutboundSequence = 0
        inflightPackets.removeAll()
        outboundChunks.removeAll()
        pendingNotifications.removeAll()
        retransmissions = 0
        packetAckTimeout?.cancel()
        packetAckTimeout = nil
        inboundFrames.removeAll()
        inflightPush = nil
        pushAckTimeout?.cancel()
        pushAckTimeout = nil
        // A new session re-sends the reading itself.
        pushRetry?.cancel()
        pushRetry = nil
        retryDelay = 0
    }

    private func closeSession(reason: String) {
        if case .closed = sessionState {
            return
        }
        record(.info, String(format: "PPoGATT session closed: %@", reason))
        resetSessionState()
        sessionState = .closed
    }

    // MARK: - Pebble Protocol

    /// Dispatches complete `[length][endpoint][payload]` frames (big-endian header).
    private func processInboundFrames() {
        while inboundFrames.count >= 4 {
            let header = [UInt8](inboundFrames.prefix(4))
            let length = Int(header[0]) << 8 | Int(header[1])
            let endpoint = UInt16(header[2]) << 8 | UInt16(header[3])
            guard inboundFrames.count >= 4 + length else {
                return
            }
            let payload = [UInt8](inboundFrames.dropFirst(4).prefix(length))
            inboundFrames = Data(inboundFrames.dropFirst(4 + length))

            if endpoint == AppMessage.endpoint, payload.count >= 2 {
                handleAppMessage(payload)
            } else if endpoint == PhoneVersion.endpoint, payload.first == PhoneVersion.request {
                record(.fromWatch, "Phone-version request (bytes \(Self.hex(payload)))")
                record(.toWatch, "Phone-version reply with 8 KiB AppMessage support (bytes \(Self.hex(PhoneVersion.response)))")
                sendFrame(endpoint: PhoneVersion.endpoint, payload: PhoneVersion.response)
            } else {
                record(.fromWatch, String(format: "Ignoring watch message on endpoint 0x%04x (%ld bytes)", Int(endpoint), length))
            }
        }
    }

    private func handleAppMessage(_ message: [UInt8]) {
        let command = message[0]
        let transactionID = message[1]

        switch command {
        case AppMessage.push:
            sendFrame(endpoint: AppMessage.endpoint, payload: Data([AppMessage.ack, transactionID]))
            record(.toWatch, "ACK for watch transaction \(transactionID)")
            guard message.count >= 18, Data(message[2..<18]) == appUUID.bytes else {
                return
            }
            // Alloy sends a ready handshake (key 15025) when the watchface starts and
            // keeps its own outbox closed until the phone sends any message back;
            // only then does Luped send its `refresh` command. Answer both, and any
            // other Luped message, with the latest reading.
            let tuples = message.dropFirst(18).map { String(format: "%02x", $0) }.joined()
            record(.fromWatch, String(format: "Watchface requested refresh (COMMAND %@, tuples %@)", commandValue(in: message) ?? "absent", tuples))
            sendIfNeeded(force: true)
        case AppMessage.ack, AppMessage.nack:
            let reply = command == AppMessage.ack ? "ACK" : "NACK"
            guard let push = inflightPush, push.transactionID == transactionID else {
                record(.fromWatch, "\(reply) for transaction \(transactionID) (bytes \(Self.hex(message))) matches no pending push; ignored")
                return
            }
            inflightPush = nil
            pushAckTimeout?.cancel()
            pushAckTimeout = nil
            let elapsed = Int(Date().timeIntervalSince(push.sentAt) * 1_000)
            let readingTime = DateFormatter.localizedString(from: push.payload.latestDate, dateStyle: .none, timeStyle: .medium)
            if command == AppMessage.ack {
                record(.fromWatch, "\(reply) for transaction \(transactionID) after \(elapsed) ms (bytes \(Self.hex(message))): watch stored reading from \(readingTime), \(push.payload.readingCount) history points")
                deliveredGeneration = push.generation
                pushRetry?.cancel()
                pushRetry = nil
                retryDelay = 0
                sendIfNeeded()
            } else {
                // The watch rejects pushes while Luped is not the running watchface.
                record(.fromWatch, "\(reply) for transaction \(transactionID) after \(elapsed) ms (bytes \(Self.hex(message))): watch rejected reading from \(readingTime); the watchface is probably not running")
                scheduleRetry()
            }
        default:
            break
        }
    }

    /// The string value of the `COMMAND` tuple in an AppMessage push for this app.
    private func commandValue(in message: [UInt8]) -> String? {
        // [command][transaction][app UUID x16][tuple count][tuples...]
        guard message.count >= 19, Data(message[2..<18]) == appUUID.bytes else {
            return nil
        }
        var offset = 19
        for _ in 0..<Int(message[18]) {
            // Tuple: [key u32 LE][type u8][length u16 LE][value]
            guard offset + 7 <= message.count else { return nil }
            let key = UInt32(message[offset]) | UInt32(message[offset + 1]) << 8 | UInt32(message[offset + 2]) << 16 | UInt32(message[offset + 3]) << 24
            let type = message[offset + 4]
            let length = Int(message[offset + 5]) | Int(message[offset + 6]) << 8
            let valueStart = offset + 7
            guard valueStart + length <= message.count else { return nil }
            if key == LupedMessageKey.command, type == AppMessage.tupleCString {
                let value = message[valueStart..<valueStart + length].prefix { $0 != 0 }
                return String(decoding: value, as: UTF8.self)
            }
            offset = valueStart + length
        }
        return nil
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
        }
        guard inflightPush == nil else {
            record(.info, "Send deferred: previous send still in flight")
            return
        }
        guard deliveredGeneration < requestGeneration else {
            return
        }
        guard let payload = latestPayload else {
            record(.info, "Send skipped: no payload yet")
            return
        }
        guard case .open = sessionState else {
            record(.info, "Send skipped: no watch session")
            return
        }

        let transactionID = nextTransactionID
        nextTransactionID &+= 1
        inflightPush = (transactionID, requestGeneration, payload, Date())

        var message = Data([AppMessage.push, transactionID])
        message.append(appUUID.bytes)
        message.append(2)
        message.appendTuple(key: LupedMessageKey.configured, type: AppMessage.tupleUnsigned, value: Data([1]))
        message.appendTuple(key: LupedMessageKey.data, type: AppMessage.tupleCString, value: Data(payload.data.utf8) + [0])

        record(.toWatch, "Sending transaction \(transactionID): \(payload.data)\n\(payload.fieldDescription)")
        sendFrame(endpoint: AppMessage.endpoint, payload: message)

        pushAckTimeout?.cancel()
        pushAckTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AppMessage.ackTimeout * 1_000_000_000))
            guard !Task.isCancelled, let self, self.inflightPush?.transactionID == transactionID else { return }
            self.record(.error, "No reply to transaction \(transactionID) within \(Int(AppMessage.ackTimeout)) s")
            self.inflightPush = nil
            self.scheduleRetry()
        }
    }

    /// Re-sends the undelivered reading after a growing delay, so a watchface
    /// that starts later still receives it even if its refresh request is lost.
    private func scheduleRetry() {
        retryDelay = retryDelay == 0 ? AppMessage.initialRetryDelay : min(retryDelay * 2, AppMessage.maximumRetryDelay)
        let delay = retryDelay
        record(.info, String(format: "Retrying in %.0f s", delay))
        pushRetry?.cancel()
        pushRetry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.sendIfNeeded()
        }
    }
}

extension LupedAlarmSettings {
    /// Mirrors Loop's active glucose alert profile. Low and high alerts repeat
    /// only when their snooze is enabled; urgent low always repeats. All watch
    /// alarms are off while Loop defers glucose alerts to the CGM's own alerts,
    /// or when the user turned off watch alarms.
    @MainActor
    init(_ manager: GlucoseAlertManager) {
        let configuration = manager.activeConfiguration()
        var mask = 0
        if manager.effectiveLoopAlertsEnabled, UserDefaults.standard.lupedPebbleAlarmsEnabled {
            if configuration.urgentLowEnabled { mask |= Self.urgentLowBit }
            if configuration.lowEnabled { mask |= Self.lowBit }
            if configuration.highEnabled { mask |= Self.highBit }
        }
        self.init(
            urgentLowMgDL: configuration.urgentLowThresholdMgDL,
            lowMgDL: configuration.lowThresholdMgDL,
            highMgDL: configuration.highThresholdMgDL,
            enabledMask: mask,
            urgentLowRepeat: configuration.urgentLowRepeatInterval,
            lowRepeat: configuration.lowSnoozeEnabled ? configuration.lowRepeatInterval : Self.oncePerEpisode,
            highRepeat: configuration.highSnoozeEnabled ? configuration.highRepeatInterval : Self.oncePerEpisode
        )
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

private extension UUID {
    var bytes: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    /// Appends a Pebble dictionary tuple with a little-endian key and length.
    mutating func appendTuple(key: UInt32, type: UInt8, value: Data) {
        Swift.withUnsafeBytes(of: key.littleEndian) { append(contentsOf: $0) }
        append(type)
        Swift.withUnsafeBytes(of: UInt16(value.count).littleEndian) { append(contentsOf: $0) }
        append(value)
    }
}
#endif
