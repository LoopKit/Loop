//
//  LoanRecords.swift
//  LoopCore
//
//  What a loan carries home: doses, wrist carbs and overrides, and the pod's running total.
//  Our own wire types, converted to LoopKit's at the store boundary (`seedDoseEntry`).
//

import Foundation
import HealthKit
import LoopKit

/// Only `.confirmed` remains; kept as a tagged enum so a new case does not change the shape.
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
    /// An unknown case throws on decode rather than being dropped.
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

    /// The dose's existing store identity, so seeding twice updates one row.
    public let syncIdentifier: String?

    public let insulinType: InsulinType?

    public let deliveredUnits: Double?

    /// On `.overrideChange`, nil means the user cleared it; an unreadable payload is not nil.
    public let overrideRaw: Data?
    /// Bolus only: enacted by the loop rather than confirmed by the user. Absent on older records.
    public let automatic: Bool?
    /// The dose's `DoseEntry.decisionId`: the dosing decision that commanded it. Absent on older
    /// records, and ignored by an older peer.
    public let decisionId: UUID?

    public init(kind: Kind, startDate: Date, endDate: Date? = nil, unitsPerHour: Double? = nil,
                amount: Double? = nil, absorptionTime: TimeInterval? = nil, note: String? = nil,
                syncIdentifier: String? = nil, insulinType: InsulinType? = nil,
                deliveredUnits: Double? = nil, overrideRaw: Data? = nil, automatic: Bool? = nil,
                decisionId: UUID? = nil) {
        self.automatic = automatic
        self.decisionId = decisionId
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

    /// nil also when unreadable; see `overrideChangeIsClear`.
    public var overrideChangePayload: TemporaryScheduleOverride? {
        guard kind == .overrideChange, let data = overrideRaw,
              let raw = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? TemporaryScheduleOverride.RawValue
        else { return nil }
        return TemporaryScheduleOverride(rawValue: raw)
    }

    /// True only for an absent payload.
    public var overrideChangeIsClear: Bool {
        return kind == .overrideChange && overrideRaw == nil
    }
}

// MARK: - Into LoopKit

extension LoanDoseRecord {
    /// The LoopKit dose, or nil for carb and override records. A suspend is a zero-rate temp.
    public func seedDoseEntry(syncIdentifier: String) -> DoseEntry? {
        switch kind {
        case .bolus:
            guard let units = amount else { return nil }
            return DoseEntry(type: .bolus, startDate: startDate, endDate: endDate ?? startDate,
                             value: units, unit: .units, decisionId: decisionId, syncIdentifier: syncIdentifier, insulinType: insulinType,
                             automatic: automatic)
        case .tempBasal:
            guard let rate = unitsPerHour, let end = endDate else { return nil }

            return DoseEntry(type: .tempBasal, startDate: startDate, endDate: end,
                             value: rate, unit: .unitsPerHour, decisionId: decisionId, deliveredUnits: deliveredUnits,
                             syncIdentifier: syncIdentifier, insulinType: insulinType)
        case .suspend:
            guard let end = endDate else { return nil }
            return DoseEntry(type: .tempBasal, startDate: startDate, endDate: end,
                             value: 0, unit: .unitsPerHour, decisionId: decisionId, deliveredUnits: deliveredUnits,
                             syncIdentifier: syncIdentifier, insulinType: insulinType)

        case .carb, .carbDeleted, .overrideChange:
            return nil
        }
    }
}

/// LoopKit derives pump-event identity from raw bytes, so raw must hex-encode back to the identifier.
public enum LoanSeedIdentity {
    /// Hex-decoded, falling back to UTF-8.
    public static func raw(forSyncIdentifier syncIdentifier: String) -> Data {
        return hexDecoded(syncIdentifier) ?? Data(syncIdentifier.utf8)
    }

    /// Strict: nil on odd length, non-hex, or empty.
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

/// `id` for acknowledgement; `seq` orders events within a loan.
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

/// The pod's running total: the independent check on the records.
public struct LoanOdometerSnapshot: Codable, Equatable {
    public let deliveredAtStart: Double
    public let deliveredLatest: Double

    /// False: a cached number, not for judging anything.
    public let freshenSucceeded: Bool

    /// A total is only true as of a moment.
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
