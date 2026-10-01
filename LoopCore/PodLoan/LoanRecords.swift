//
//  LoanRecords.swift
//  LoopCore — one module, linked by both the phone app and the watch app.
//
//  What a session actually carries home: the doses the watch delivered, the carbs and override
//  changes the user entered on the wrist, and the pod's own running total.
//
//  These types are ours rather than LoopKit's on purpose. The wire format has to stay stable
//  across two apps that update separately, so it must not move whenever LoopKit's own encoding
//  does. Conversion to LoopKit's types happens at the store boundary, in `seedDoseEntry`.
//

import Foundation
import HealthKit
import LoopKit

/// Where a record came from. Only one case survives: the watch streams a record once the pod
/// has confirmed the delivery, so everything that crosses the wire is confirmed by definition.
/// It stays an enum, encoded as a tagged object, so a future provenance can be added without
/// changing the shape of every record already written.
public enum EventProvenance: Codable, Equatable {
    case confirmed

    private enum CodingKeys: String, CodingKey { case tag }
    private enum Tag: String, Codable { case confirmed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .tag) {
        case .confirmed: self = .confirmed
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Tag.confirmed, forKey: .tag)
    }
}

/// One thing that happened during a session, in the form that travels.
public struct LoanDoseRecord: Codable, Equatable {
    /// A plain String enum, which means a build that predates a case THROWS on decode rather
    /// than quietly ignoring it. That is deliberate: a session that refuses to decode is
    /// recoverable, while one that silently drops a record is not.
    public enum Kind: String, Codable {
        case bolus
        case tempBasal

        case suspend
        case carb

        case carbDeleted

        case overrideChange
    }

    public let kind: Kind
    public let startDate: Date
    public let endDate: Date?

    public let unitsPerHour: Double?

    public let amount: Double?

    public let absorptionTime: TimeInterval?

    public let note: String?

    /// The identity the dose already has in the phone's store, when it has one. Carrying it
    /// means a record seeded twice updates one row instead of becoming two doses.
    public let syncIdentifier: String?

    public let insulinType: InsulinType?

    public let deliveredUnits: Double?

    /// An override, serialised as a property list. On an `.overrideChange` record, nil means
    /// the user CLEARED the override. A payload that fails to decode must therefore never be
    /// treated as nil: cancelling a live override nobody asked to cancel is a therapy change.
    public let overrideRaw: Data?

    public init(kind: Kind, startDate: Date, endDate: Date? = nil, unitsPerHour: Double? = nil,
                amount: Double? = nil, absorptionTime: TimeInterval? = nil, note: String? = nil,
                syncIdentifier: String? = nil, insulinType: InsulinType? = nil,
                deliveredUnits: Double? = nil, overrideRaw: Data? = nil) {
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.unitsPerHour = unitsPerHour
        self.amount = amount
        self.absorptionTime = absorptionTime
        self.note = note
        self.syncIdentifier = syncIdentifier
        self.insulinType = insulinType
        self.deliveredUnits = deliveredUnits
        self.overrideRaw = overrideRaw
    }
}

// MARK: - Overrides

extension LoanDoseRecord {
    /// A record of the user setting or clearing an override on the wrist.
    public static func overrideChange(_ override: TemporaryScheduleOverride?,
                                      at date: Date,
                                      note: String? = nil) -> LoanDoseRecord {
        let raw: Data? = override.flatMap { o in
            try? PropertyListSerialization.data(fromPropertyList: o.rawValue, format: .binary, options: 0)
        }
        return LoanDoseRecord(
            kind: .overrideChange,
            startDate: date,
            endDate: override.flatMap { $0.duration.isInfinite ? nil : $0.scheduledEndDate },
            note: note,
            syncIdentifier: override?.syncIdentifier.uuidString,
            overrideRaw: raw)
    }

    /// The override this record carries, or nil if it is not an override record or the payload
    /// cannot be read. Callers must distinguish this from `overrideChangeIsClear`.
    public var overrideChangePayload: TemporaryScheduleOverride? {
        guard kind == .overrideChange, let data = overrideRaw,
              let raw = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? TemporaryScheduleOverride.RawValue
        else { return nil }
        return TemporaryScheduleOverride(rawValue: raw)
    }

    /// True only when the record genuinely says "the user cleared it" — an absent payload, not
    /// an unreadable one.
    public var overrideChangeIsClear: Bool {
        return kind == .overrideChange && overrideRaw == nil
    }
}

// MARK: - Into LoopKit

extension LoanDoseRecord {
    /// The LoopKit dose this record becomes in a store. Carb, carb-deletion and override records
    /// return nil: they are not insulin and travel to their own stores.
    ///
    /// A suspend arrives as a zero-rate temp basal, which is what the pod actually did and what
    /// the algorithm can reason about.
    public func seedDoseEntry(syncIdentifier: String) -> DoseEntry? {
        switch kind {
        case .bolus:
            guard let units = amount else { return nil }
            return DoseEntry(type: .bolus, startDate: startDate, endDate: endDate ?? startDate,
                             value: units, unit: .units, decisionId: nil, syncIdentifier: syncIdentifier, insulinType: insulinType)
        case .tempBasal:
            guard let rate = unitsPerHour, let end = endDate else { return nil }

            return DoseEntry(type: .tempBasal, startDate: startDate, endDate: end,
                             value: rate, unit: .unitsPerHour, decisionId: nil, deliveredUnits: deliveredUnits,
                             syncIdentifier: syncIdentifier, insulinType: insulinType)
        case .suspend:
            guard let end = endDate else { return nil }
            return DoseEntry(type: .tempBasal, startDate: startDate, endDate: end,
                             value: 0, unit: .unitsPerHour, decisionId: nil, deliveredUnits: deliveredUnits,
                             syncIdentifier: syncIdentifier, insulinType: insulinType)

        case .carb, .carbDeleted, .overrideChange:
            return nil
        }
    }
}

/// Identity for a seeded dose, in the form LoopKit actually uses.
///
/// LoopKit discards an incoming `DoseEntry.syncIdentifier` for pump events and derives identity
/// from the event's raw bytes instead. So a dose must be seeded with raw bytes that hex-encode
/// back to the same identifier — seeding the text of the identifier gives one physical dose two
/// different identities, and nothing downstream can tell they are the same dose.
public enum LoanSeedIdentity {
    /// The raw bytes for an identifier, decoding hex when it is hex and falling back to its
    /// UTF-8 for identifiers that are not.
    public static func raw(forSyncIdentifier syncIdentifier: String) -> Data {
        return hexDecoded(syncIdentifier) ?? Data(syncIdentifier.utf8)
    }

    /// Strict hex decode: an odd number of digits, any non-hex character, or an empty result
    /// returns nil rather than a partial decode.
    public static func hexDecoded(_ string: String) -> Data? {
        func nibble(_ u: UInt16) -> UInt8? {
            switch u {
            case 0x30...0x39: return UInt8(u - 0x30)
            case 0x41...0x46: return UInt8(u - 0x41 + 10)
            case 0x61...0x66: return UInt8(u - 0x61 + 10)
            default: return nil
            }
        }
        var data = Data(capacity: string.utf16.count / 2)
        var even = true
        var byte: UInt8 = 0
        for c in string.utf16 {
            guard let val = nibble(c) else { return nil }
            if even { byte = val << 4 } else { byte += val; data.append(byte) }
            even.toggle()
        }
        guard even, !data.isEmpty else { return nil }
        return data
    }
}

/// A record plus the bookkeeping that lets both sides agree on what has been delivered.
///
/// `id` identifies the event for acknowledgement; `seq` orders events within one session and is
/// what the phone's cursor advances through, so records can be re-sent without being re-applied.
public struct LoanEvent: Codable, Equatable {
    public let id: UUID

    public let seq: Int
    public let provenance: EventProvenance
    public let record: LoanDoseRecord
    public let loggedAt: Date

    public init(id: UUID, seq: Int, provenance: EventProvenance, record: LoanDoseRecord, loggedAt: Date) {
        self.id = id
        self.seq = seq
        self.provenance = provenance
        self.record = record
        self.loggedAt = loggedAt
    }
}

/// The pod's own running total of insulin delivered, read at the start of a session and again
/// later. It is the independent check on the records: the records say what the watch intended,
/// this says what the pod did.
public struct LoanOdometerSnapshot: Codable, Equatable {
    public let deliveredAtStart: Double
    public let deliveredLatest: Double

    /// Whether the later reading came from a fresh pod round-trip. False means the number is a
    /// cached one and must not be used to judge anything.
    public let freshenSucceeded: Bool

    /// When the later reading was taken. Without it the total cannot be lined up against the
    /// records, because a total is only true as of a moment.
    public let asOf: Date?

    public init(deliveredAtStart: Double, deliveredLatest: Double, freshenSucceeded: Bool,
                asOf: Date? = nil) {
        self.deliveredAtStart = deliveredAtStart
        self.deliveredLatest = deliveredLatest
        self.freshenSucceeded = freshenSucceeded
        self.asOf = asOf
    }
}

public struct LoanPredictionSnapshot: Codable, Equatable {
    public let snapshotAt: Date
    public let startGlucoseMgdl: Double

    public let startGlucoseDate: Date

    public let eventualMgdl: Double

    public let eventualIncludingPendingMgdl: Double?
    public let impactMomentumMgdl: Double
    public let impactInsulinMgdl: Double
    public let impactCarbMgdl: Double
    public let impactRCMgdl: Double

    public let iobUnits: Double
    public let iobDate: Date
    public let cobGrams: Double

    public let momentumPointCount: Int

    public let rcDiscrepancyCount: Int

    public let enabledEffectsRaw: Int

    public init(snapshotAt: Date, startGlucoseMgdl: Double, startGlucoseDate: Date,
                eventualMgdl: Double, eventualIncludingPendingMgdl: Double?,
                impactMomentumMgdl: Double, impactInsulinMgdl: Double,
                impactCarbMgdl: Double, impactRCMgdl: Double,
                iobUnits: Double, iobDate: Date, cobGrams: Double,
                momentumPointCount: Int, rcDiscrepancyCount: Int, enabledEffectsRaw: Int) {
        self.snapshotAt = snapshotAt
        self.startGlucoseMgdl = startGlucoseMgdl
        self.startGlucoseDate = startGlucoseDate
        self.eventualMgdl = eventualMgdl
        self.eventualIncludingPendingMgdl = eventualIncludingPendingMgdl
        self.impactMomentumMgdl = impactMomentumMgdl
        self.impactInsulinMgdl = impactInsulinMgdl
        self.impactCarbMgdl = impactCarbMgdl
        self.impactRCMgdl = impactRCMgdl
        self.iobUnits = iobUnits
        self.iobDate = iobDate
        self.cobGrams = cobGrams
        self.momentumPointCount = momentumPointCount
        self.rcDiscrepancyCount = rcDiscrepancyCount
        self.enabledEffectsRaw = enabledEffectsRaw
    }
}

public struct LoanCarbRecord: Codable, Equatable {
    public let syncIdentifier: String?
    public let provenanceIdentifier: String
    public let syncVersion: Int?
    public let startDate: Date
    public let grams: Double
    public let absorptionTime: TimeInterval?
    public let foodType: String?
    public let userCreatedDate: Date?
    public let userUpdatedDate: Date?

    public init(syncIdentifier: String?, provenanceIdentifier: String, syncVersion: Int?,
                startDate: Date, grams: Double, absorptionTime: TimeInterval?, foodType: String?,
                userCreatedDate: Date?, userUpdatedDate: Date?) {
        self.syncIdentifier = syncIdentifier
        self.provenanceIdentifier = provenanceIdentifier
        self.syncVersion = syncVersion
        self.startDate = startDate
        self.grams = grams
        self.absorptionTime = absorptionTime
        self.foodType = foodType
        self.userCreatedDate = userCreatedDate
        self.userUpdatedDate = userUpdatedDate
    }
}

public struct LoanGlucoseRecord: Codable, Equatable {
    public let syncIdentifier: String?
    public let startDate: Date

    public let valueMgdl: Double

    public let trendRateMgdlPerMin: Double?
    public let isDisplayOnly: Bool
    public let wasUserEntered: Bool

    public init(syncIdentifier: String?, startDate: Date, valueMgdl: Double,
                trendRateMgdlPerMin: Double?, isDisplayOnly: Bool, wasUserEntered: Bool) {
        self.syncIdentifier = syncIdentifier
        self.startDate = startDate
        self.valueMgdl = valueMgdl
        self.trendRateMgdlPerMin = trendRateMgdlPerMin
        self.isDisplayOnly = isDisplayOnly
        self.wasUserEntered = wasUserEntered
    }
}
