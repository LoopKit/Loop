//
//  LoanTransport.swift
//  LoopCore — one module, linked by both the phone app and the watch app.
//  (The fork compiled this file into four targets; LoopCore replaces that with a single
//  compilation both platforms share, which is the same guarantee by simpler means.)
//
//  How a loan message crosses between the phone and the watch.
//
//  One WatchConnectivity dictionary key carries JSON of a `LoanEnvelope`: a version, a kind,
//  and the message body. The kind discriminator is written by hand rather than synthesised so
//  that an unknown kind or version THROWS rather than decoding to something plausible. The two
//  apps install separately and can run different builds, so this is the one place that has to
//  assume the other side is older or newer than we are.
//
//  A message that cannot be decoded is nacked, never quietly dropped: silence on this channel
//  looks exactly like a watch that is out of range, and the two must not be confused.
//

import Foundation
import HealthKit
import LoopKit

/// Wire constants shared by both apps.
public enum LoanProtocol {
    /// Bumped only for a change the other side could not survive. A bump strands a loan — both
    /// halves refuse to decode — which is the intended outcome: better a session that will not
    /// start than one where a dose is misread. Additive changes use optional fields instead.
    public static let version = 2

    public static let userInfoKey = "podLoanV2"

    /// Dates go over the wire as whole milliseconds since 1970. A JSON Double drifts below the
    /// millisecond, and these timestamps are compared for ordering on both sides. Time zone is
    /// not part of a date here; it travels separately with the therapy settings.
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let milliseconds = try decoder.singleValueContainer().decode(Int64.self)
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        return d
    }
}

/// The only failure this layer reports. `seenVersion` is nil when the payload was not even
/// shaped like an envelope, and set when it was a version we do not speak.
public enum LoanProtocolError: Error {
    case undecodable(seenVersion: Int?)
}

/// Every message the two apps exchange during a loan, in roughly the order a session uses them.
public enum LoanMessage: Equatable {
    case request(LoanRequest)
    case grant(LoanGrant)
    case takeoverComplete(TakeoverComplete)
    case takeoverFailed(TakeoverFailed)
    case doseRecordBatch(DoseRecordBatch)
    case handbackOffer(HandbackOffer)
    case handbackAck(HandbackAck)
    case revoke(Revoke)
    case statusQuery(StatusQuery)
    case statusReport(StatusReport)
    case nack(ProtocolNack)
    case denied(LoanDenied)
    case diag(LoanDiag)

    /// Not part of a session: the standing copy of the phone's state that the watch keeps so it
    /// can start one without the phone.
    case dormantGrant(DormantGrant)
}

/// What actually goes on the wire. Decoding checks the version before it looks at anything
/// else, so a future build's message cannot be half-read by this one.
public struct LoanEnvelope: Codable {
    public let protocolVersion: Int
    public let message: LoanMessage

    public init(message: LoanMessage) {
        self.protocolVersion = LoanProtocol.version
        self.message = message
    }

    private enum CodingKeys: String, CodingKey { case protocolVersion, kind, body }

    private enum Kind: String, Codable {
        case request, grant, takeoverComplete, takeoverFailed, doseRecordBatch
        case handbackOffer, handbackAck, revoke, statusQuery, statusReport, nack, denied
        case diag, dormantGrant
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .protocolVersion)
        self.protocolVersion = version
        guard version == LoanProtocol.version else {
            throw LoanProtocolError.undecodable(seenVersion: version)
        }
        guard let kindString = try? c.decode(String.self, forKey: .kind),
              let kind = Kind(rawValue: kindString) else {
            throw LoanProtocolError.undecodable(seenVersion: version)
        }
        switch kind {
        case .request: self.message = .request(try c.decode(LoanRequest.self, forKey: .body))
        case .grant: self.message = .grant(try c.decode(LoanGrant.self, forKey: .body))
        case .takeoverComplete: self.message = .takeoverComplete(try c.decode(TakeoverComplete.self, forKey: .body))
        case .takeoverFailed: self.message = .takeoverFailed(try c.decode(TakeoverFailed.self, forKey: .body))
        case .doseRecordBatch: self.message = .doseRecordBatch(try c.decode(DoseRecordBatch.self, forKey: .body))
        case .handbackOffer: self.message = .handbackOffer(try c.decode(HandbackOffer.self, forKey: .body))
        case .handbackAck: self.message = .handbackAck(try c.decode(HandbackAck.self, forKey: .body))
        case .revoke: self.message = .revoke(try c.decode(Revoke.self, forKey: .body))
        case .statusQuery: self.message = .statusQuery(try c.decode(StatusQuery.self, forKey: .body))
        case .statusReport: self.message = .statusReport(try c.decode(StatusReport.self, forKey: .body))
        case .nack: self.message = .nack(try c.decode(ProtocolNack.self, forKey: .body))
        case .denied: self.message = .denied(try c.decode(LoanDenied.self, forKey: .body))
        case .diag: self.message = .diag(try c.decode(LoanDiag.self, forKey: .body))
        case .dormantGrant: self.message = .dormantGrant(try c.decode(DormantGrant.self, forKey: .body))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(protocolVersion, forKey: .protocolVersion)
        switch message {
        case .request(let m): try c.encode(Kind.request, forKey: .kind); try c.encode(m, forKey: .body)
        case .grant(let m): try c.encode(Kind.grant, forKey: .kind); try c.encode(m, forKey: .body)
        case .takeoverComplete(let m): try c.encode(Kind.takeoverComplete, forKey: .kind); try c.encode(m, forKey: .body)
        case .takeoverFailed(let m): try c.encode(Kind.takeoverFailed, forKey: .kind); try c.encode(m, forKey: .body)
        case .doseRecordBatch(let m): try c.encode(Kind.doseRecordBatch, forKey: .kind); try c.encode(m, forKey: .body)
        case .handbackOffer(let m): try c.encode(Kind.handbackOffer, forKey: .kind); try c.encode(m, forKey: .body)
        case .handbackAck(let m): try c.encode(Kind.handbackAck, forKey: .kind); try c.encode(m, forKey: .body)
        case .revoke(let m): try c.encode(Kind.revoke, forKey: .kind); try c.encode(m, forKey: .body)
        case .statusQuery(let m): try c.encode(Kind.statusQuery, forKey: .kind); try c.encode(m, forKey: .body)
        case .statusReport(let m): try c.encode(Kind.statusReport, forKey: .kind); try c.encode(m, forKey: .body)
        case .nack(let m): try c.encode(Kind.nack, forKey: .kind); try c.encode(m, forKey: .body)
        case .denied(let m): try c.encode(Kind.denied, forKey: .kind); try c.encode(m, forKey: .body)
        case .diag(let m): try c.encode(Kind.diag, forKey: .kind); try c.encode(m, forKey: .body)
        case .dormantGrant(let m): try c.encode(Kind.dormantGrant, forKey: .kind); try c.encode(m, forKey: .body)
        }
    }
}

extension LoanMessage {
    public func transportDictionary() throws -> [String: Any] {
        let data = try LoanProtocol.encoder.encode(LoanEnvelope(message: self))
        return [LoanProtocol.userInfoKey: data]
    }

    /// The kind's name, for logs on both sides.
    public var kindLabel: String {
        switch self {
        case .request:          return "request"
        case .grant:            return "grant"
        case .takeoverComplete: return "takeoverComplete"
        case .takeoverFailed:   return "takeoverFailed"
        case .doseRecordBatch:  return "doseRecordBatch"
        case .handbackOffer:    return "handbackOffer"
        case .handbackAck:      return "handbackAck"
        case .revoke:           return "revoke"
        case .statusQuery:      return "statusQuery"
        case .statusReport:     return "statusReport"
        case .nack:             return "nack"
        case .denied:           return "denied"
        case .diag:             return "diag"
        case .dormantGrant:     return "dormantGrant"
        }
    }

    /// Whether this message should wake the other app now (`sendMessage`) rather than wait in
    /// the delivery queue (`transferUserInfo`).
    ///
    /// The queue is explicitly not urgent and can hold a message until the other side happens to
    /// wake — long enough for a grant's answer to land after the watch has already told the user
    /// the takeover failed. So every moment a person is waiting through goes urgent, and routine
    /// bookkeeping stays queued, where delivery is guaranteed even across a relaunch.
    ///
    /// `.takeoverComplete` belongs on the urgent side for a reason that is easy to undo: the
    /// phone's pump tile stops saying "Taking over…" when it arrives. Queued, that label can sit
    /// for minutes after the pod is already on the wrist.
    public var isInteractiveHandshake: Bool {
        switch self {
        case .request, .grant, .denied, .nack, .revoke, .handbackOffer, .handbackAck,
             .takeoverComplete:
            return true
        case .takeoverFailed, .doseRecordBatch, .statusQuery,
             .statusReport, .diag,

             .dormantGrant:
            return false
        }
    }

    /// The kind alone, without decoding the body — enough for a log line or a routing decision
    /// about a message we may not need to read.
    public static func peekKind(transport userInfo: [String: Any]) -> String? {
        guard let data = userInfo[LoanProtocol.userInfoKey] as? Data else { return nil }
        struct Peek: Decodable { let kind: String }
        return (try? JSONDecoder().decode(Peek.self, from: data))?.kind
    }

    /// The same question asked of an encoded payload, with the size limit applied.
    ///
    /// The urgent channel refuses payloads near 65 KB, and a refusal there is silent. A grant
    /// carries pod state plus dose, carb and glucose history and can approach that, so anything
    /// above 60 KB is sent queued on purpose rather than failing on the way out.
    public static func isInteractiveHandshake(transport userInfo: [String: Any]) -> Bool {
        if let data = userInfo[LoanProtocol.userInfoKey] as? Data, data.count > 60_000 {
            return false
        }

        guard let message = try? decode(fromTransport: userInfo) else { return false }
        return message.isInteractiveHandshake
    }

    /// Decode a received payload. Returns nil when the dictionary is not ours at all (the same
    /// channel carries the stock watch app's own traffic), and throws when it is ours and we
    /// cannot read it — a distinction the caller acts on: ignore the first, nack the second.
    public static func decode(fromTransport userInfo: [String: Any]) throws -> LoanMessage? {
        guard let data = userInfo[LoanProtocol.userInfoKey] as? Data else { return nil }
        do {
            return try LoanProtocol.decoder.decode(LoanEnvelope.self, from: data).message
        } catch let error as LoanProtocolError {
            throw error
        } catch {
            throw LoanProtocolError.undecodable(seenVersion: nil)
        }
    }
}
