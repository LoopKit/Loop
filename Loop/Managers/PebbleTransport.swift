#if LUPED_PEBBLE
import CoreBluetooth
import Foundation

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
    /// window negotiation; it is ample for one small message at a time.
    static let version: UInt8 = 0
    static let windowSize = 4
    static let sequenceModulus: UInt8 = 32
    static let ackTimeout: TimeInterval = 5
    static let maxRetransmissions = 2
}

/// Pebble Protocol endpoint and AppMessage wire constants.
enum PebbleAppMessage {
    static let endpoint: UInt16 = 0x30
    static let push: UInt8 = 0x01
    static let ack: UInt8 = 0xFF
    static let nack: UInt8 = 0x7F

    static let tupleCString: UInt8 = 1
    static let tupleUnsigned: UInt8 = 2

    /// How long to wait for the watch's ACK or NACK of a push.
    static let ackTimeout: TimeInterval = 10

    /// Alloy's startup handshake key (`kPKJSReadyMessage`). An Alloy watchface
    /// sends it on start and keeps its outbox closed until the phone replies.
    static let alloyReadyKey: UInt32 = 15_025
}

/// PebbleOS app run-state endpoint: start or stop an app by UUID.
private enum AppRunState {
    static let endpoint: UInt16 = 0x34
    static let run: UInt8 = 0x01
    static let stop: UInt8 = 0x02
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

/// The watch link as shown to the user.
enum PebbleLinkState: Equatable {
    case off, bluetoothUnavailable, waitingForWatch, connecting, open
}

/// Who a transport log line describes.
enum PebbleLogKind {
    case toWatch, fromWatch, info, error
}

/// One AppMessage dictionary tuple received from the watch.
struct AppMessageTuple {
    let type: UInt8
    let value: ArraySlice<UInt8>

    /// The value of a C-string tuple, without its terminator.
    var string: String? {
        type == PebbleAppMessage.tupleCString ? String(decoding: value.prefix { $0 != 0 }, as: UTF8.self) : nil
    }
}

/// A value to send in an AppMessage dictionary.
enum AppMessageValue {
    case cString(String)
    case uint8(UInt8)
}

/// Reports a `PebbleTransport`'s session, messages and log lines to the app layer
/// built on it.
@MainActor
protocol PebbleTransportDelegate: AnyObject {
    /// A line for the app's communication log.
    func pebbleTransport(_ transport: PebbleTransport, log kind: PebbleLogKind, _ message: String)
    func pebbleTransportDidChangeLink(_ transport: PebbleTransport)
    /// The PPoGATT session opened; messages can be pushed.
    func pebbleTransportSessionDidOpen(_ transport: PebbleTransport)
    /// The session is resetting or closing: anything in flight is lost.
    func pebbleTransportSessionWillReset(_ transport: PebbleTransport)
    /// An AppMessage push from the app, after the transport acknowledged it.
    /// `message` is the raw AppMessage payload.
    func pebbleTransport(_ transport: PebbleTransport, didReceive tuples: [UInt32: AppMessageTuple], message: [UInt8])
    /// The watch's ACK or NACK of one of our pushes. `message` is the raw payload.
    func pebbleTransport(_ transport: PebbleTransport, didReceiveReply acknowledged: Bool, transactionID: UInt8, message: [UInt8])
}

/// A generic phone-side Pebble link for one JS-free watch app.
///
/// The phone publishes its own PPoGATT service through CoreBluetooth rather
/// than using the legacy PebbleKit iOS SDK, whose watch discovery does not
/// recognize Core Devices watches (Pebble Time 2, Pebble Round 2, Pebble 2
/// Duo). The watch must be paired with and connected to the Pebble app; it then
/// discovers this service and opens a session for the configured app UUID.
///
/// The transport runs PPoGATT and the Pebble Protocol, answers the phone-version
/// exchange, acknowledges the app's AppMessages and decodes them, and sends
/// AppMessages and app run-state commands. What to send, when, and how to retry
/// belongs to the delegate.
@MainActor
final class PebbleTransport: NSObject, @preconcurrency CBPeripheralManagerDelegate {
    weak var delegate: PebbleTransportDelegate?

    private(set) var isEnabled: Bool {
        didSet { updateLink() }
    }
    private(set) var appUUID: UUID
    private(set) var link = PebbleLinkState.off

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

    private var watch: CBCentral? {
        didSet { updateLink() }
    }
    private var sessionState = SessionState.closed {
        didSet { updateLink() }
    }
    private var nextInboundSequence: UInt8 = 0
    private var lastSentAck: UInt8?
    private var nextOutboundSequence: UInt8 = 0
    private var inflightPackets: [(sequence: UInt8, packet: Data)] = []
    private var outboundChunks: [Data] = []
    private var pendingNotifications: [Data] = []
    private var retransmissions = 0
    private var packetAckTimeout: Task<Void, Never>?
    private var inboundFrames = Data()
    private var nextTransactionID: UInt8 = 0

    init(isEnabled: Bool, appUUID: UUID) {
        self.isEnabled = isEnabled
        self.appUUID = appUUID
        super.init()
    }

    var isSessionOpen: Bool {
        if case .open = sessionState {
            return true
        }
        return false
    }

    static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func record(_ kind: PebbleLogKind, _ message: String) {
        delegate?.pebbleTransport(self, log: kind, message)
    }

    private func updateLink() {
        let link: PebbleLinkState
        if !isEnabled {
            link = .off
        } else if peripheralManager?.state != .poweredOn {
            link = .bluetoothUnavailable
        } else if case .open = sessionState {
            link = .open
        } else if watch != nil {
            link = .connecting
        } else {
            link = .waitingForWatch
        }
        if self.link != link {
            self.link = link
            delegate?.pebbleTransportDidChangeLink(self)
        }
    }

    /// Starts Bluetooth and publishes the service once it is powered on.
    func start() {
        guard isEnabled, peripheralManager == nil else {
            return
        }

        record(.info, String(format: "Starting PPoGATT service for app %@", appUUID.uuidString))
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    /// Applies a new enabled state or app UUID. Removing the service ends the
    /// watch's session; publishing it under a new UUID makes the watch open a
    /// new one. Disabling releases Bluetooth entirely.
    func reconfigure(isEnabled: Bool, appUUID: UUID) {
        self.isEnabled = isEnabled
        self.appUUID = appUUID

        closeSession(reason: "settings changed")
        watch = nil
        peripheralManager?.removeAllServices()
        isServicePublished = false
        dataCharacteristic = nil

        guard isEnabled else {
            peripheralManager?.delegate = nil
            peripheralManager = nil
            updateLink()
            return
        }
        if let peripheralManager {
            if peripheralManager.state == .poweredOn {
                publishService(on: peripheralManager)
            }
        } else {
            start()
        }
    }

    // MARK: - Sending

    /// The transaction ID for the next push; pass it to `push(transactionID:tuples:)`.
    func makeTransactionID() -> UInt8 {
        defer { nextTransactionID &+= 1 }
        return nextTransactionID
    }

    /// Pushes an AppMessage dictionary to the app. The watch's reply arrives
    /// through `pebbleTransport(_:didReceiveReply:transactionID:message:)`.
    func push(transactionID: UInt8, tuples: [(key: UInt32, value: AppMessageValue)]) {
        var message = Data([PebbleAppMessage.push, transactionID])
        message.append(appUUID.bytes)
        message.append(UInt8(tuples.count))
        for tuple in tuples {
            switch tuple.value {
            case .cString(let string):
                message.appendTuple(key: tuple.key, type: PebbleAppMessage.tupleCString, value: Data(string.utf8) + [0])
            case .uint8(let value):
                message.appendTuple(key: tuple.key, type: PebbleAppMessage.tupleUnsigned, value: Data([value]))
            }
        }
        sendFrame(endpoint: PebbleAppMessage.endpoint, payload: message)
    }

    /// Starts or stops the app on the watch.
    func sendAppRunState(run: Bool) {
        sendFrame(endpoint: AppRunState.endpoint, payload: Data([run ? AppRunState.run : AppRunState.stop]) + appUUID.bytes)
    }

    // MARK: - GATT service

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
        defer { updateLink() }
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
            delegate?.pebbleTransportSessionDidOpen(self)
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
        delegate?.pebbleTransportSessionWillReset(self)
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

            if endpoint == PebbleAppMessage.endpoint, payload.count >= 2 {
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
        case PebbleAppMessage.push:
            sendFrame(endpoint: PebbleAppMessage.endpoint, payload: Data([PebbleAppMessage.ack, transactionID]))
            record(.toWatch, "ACK for watch transaction \(transactionID)")
            guard let tuples = tuples(in: message) else {
                return
            }
            delegate?.pebbleTransport(self, didReceive: tuples, message: message)
        case PebbleAppMessage.ack, PebbleAppMessage.nack:
            delegate?.pebbleTransport(self, didReceiveReply: command == PebbleAppMessage.ack, transactionID: transactionID, message: message)
        default:
            break
        }
    }

    /// The tuples of an AppMessage push for this app, by key; `nil` for other apps.
    private func tuples(in message: [UInt8]) -> [UInt32: AppMessageTuple]? {
        // [command][transaction][app UUID x16][tuple count][tuples...]
        guard message.count >= 19, Data(message[2..<18]) == appUUID.bytes else {
            return nil
        }
        var tuples: [UInt32: AppMessageTuple] = [:]
        var offset = 19
        for _ in 0..<Int(message[18]) {
            // Tuple: [key u32 LE][type u8][length u16 LE][value]
            guard offset + 7 <= message.count else { break }
            let key = UInt32(message[offset]) | UInt32(message[offset + 1]) << 8 | UInt32(message[offset + 2]) << 16 | UInt32(message[offset + 3]) << 24
            let type = message[offset + 4]
            let length = Int(message[offset + 5]) | Int(message[offset + 6]) << 8
            let valueStart = offset + 7
            guard valueStart + length <= message.count else { break }
            tuples[key] = AppMessageTuple(type: type, value: message[valueStart..<valueStart + length])
            offset = valueStart + length
        }
        return tuples
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
