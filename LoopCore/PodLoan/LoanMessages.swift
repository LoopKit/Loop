//
//  LoanMessages.swift
//  LoopCore
//
//  The messages the phone and watch exchange. Fields added after the format froze are
//  Optional, and nil means "an older build sent this": the apps install separately.
//

import Foundation
import HealthKit
import LoopAlgorithm
import LoopKit

extension LoanGrant {
    /// The pump's configuration, or nil if it does not decode.
    public var sharedPumpConfiguration: SharedDeviceConfiguration? {
        let plist = try? PropertyListSerialization.propertyList(from: pumpConfiguration, options: [], format: nil)
        return (plist as? SharedDeviceConfiguration.RawValue).flatMap(SharedDeviceConfiguration.init(rawValue:))
    }

    public func seedDoseEntries() -> [DoseEntry] {
        return doseHistory.enumerated().compactMap { index, record in

            let syncId = record.syncIdentifier ?? "loanv2-grant-\(epoch)-\(index)"
            return record.seedDoseEntry(syncIdentifier: syncId)
        }
    }

    public func seedDoseEntries(finishedBy instant: Date) -> (seed: [DoseEntry], live: [DoseEntry]) {
        let all = seedDoseEntries()
        return (all.filter { $0.endDate <= instant }, all.filter { $0.endDate > instant })
    }

    /// The phone's recent overrides; nil from a phone that does not send them.
    public var overrideHistory: [TemporaryScheduleOverride]? {
        guard let data = overrideHistoryRaw,
              let raws = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [TemporaryScheduleOverride.RawValue]
        else { return nil }
        return raws.compactMap(TemporaryScheduleOverride.init(rawValue:))
    }

    /// The raw form drops `actualEnd`, so an early end is folded into the duration, as
    /// `queryByAnchor` does. Deleted overrides are left out.
    public static func overrideHistoryRaw(_ overrides: [TemporaryScheduleOverride]) -> Data? {
        let raws: [TemporaryScheduleOverride.RawValue] = overrides.compactMap { override in
            var folded = override
            switch override.actualEnd {
            case .natural: break
            case .early(let end) where end > override.startDate: folded.scheduledEndDate = end
            case .early, .deleted: return nil
            }
            return folded.rawValue
        }
        return try? PropertyListSerialization.data(fromPropertyList: raws, format: .binary, options: 0)
    }
}

/// The phone's therapy settings over a past window, as stock's settings-history queries return
/// them: absolute timelines, glucose values in mg/dL.
public struct LoanSettingsHistory: Codable, Equatable {
    public let basal: [AbsoluteScheduleValue<Double>]
    public let sensitivity: [AbsoluteScheduleValue<Double>]
    public let carbRatio: [AbsoluteScheduleValue<Double>]
    public let targetRange: [AbsoluteScheduleValue<DoubleRange>]

    public init(basal: [AbsoluteScheduleValue<Double>],
                sensitivity: [AbsoluteScheduleValue<LoopQuantity>],
                carbRatio: [AbsoluteScheduleValue<Double>],
                targetRange: [AbsoluteScheduleValue<ClosedRange<LoopQuantity>>]) {
        let mgdl = LoopUnit.milligramsPerDeciliter
        self.basal = basal
        self.sensitivity = sensitivity.map {
            AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate, value: $0.value.doubleValue(for: mgdl))
        }
        self.carbRatio = carbRatio
        self.targetRange = targetRange.map {
            AbsoluteScheduleValue(startDate: $0.startDate, endDate: $0.endDate,
                                  value: DoubleRange(minValue: $0.value.lowerBound.doubleValue(for: mgdl),
                                                     maxValue: $0.value.upperBound.doubleValue(for: mgdl)))
        }
    }
}

/// The pod's own report at a moment; carried at takeover and hand-back.
public struct LoanPodStatus: Codable, Equatable {
    public let timestamp: Date
    public let deliveredUnits: Double?
    public let reservoirLevel: Double?
    public let isSuspended: Bool
    public let faultCode: String?

    public init(timestamp: Date, deliveredUnits: Double?, reservoirLevel: Double?,
                isSuspended: Bool, faultCode: String?) {
        self.timestamp = timestamp
        self.deliveredUnits = deliveredUnits
        self.reservoirLevel = reservoirLevel
        self.isSuspended = isSuspended
        self.faultCode = faultCode
    }
}

/// How the holder of the pod is dosing.
public enum LoanDosingMode: String, Codable {
    case closedDirect
    case closedPhoneFed
    case cgmViewer
    case pausedStale
    case suspended
}

/// The watch asking for the pod.
public struct LoanRequest: Codable, Equatable {
    public let watchBuild: String
    public let supportedVersions: [Int]

    /// Lets the phone recognise a redelivered copy of the same request.
    public let requestID: String?

    /// The phone refreshes its standing copy only for a watch that can start alone.
    public let supportsSeize: Bool?

    /// A request that sat in a queue is not granted.
    public let sentAt: Date?

    public init(watchBuild: String,
                supportedVersions: [Int] = [LoanProtocol.version],
                requestID: String = UUID().uuidString,
                supportsSeize: Bool? = nil,
                sentAt: Date? = nil) {
        self.watchBuild = watchBuild
        self.supportedVersions = supportedVersions
        self.requestID = requestID
        self.supportsSeize = supportsSeize
        self.sentAt = sentAt
    }
}

/// The standing copy the watch keeps to start a loan without the phone: a complete grant,
/// not yet activated.
public struct DormantGrant: Codable, Equatable {
    public let grant: LoanGrant
    public let issuedAt: Date

    /// Lets the returning phone recognise a loan grown from its own credential.
    public let seizeToken: UUID

    public init(grant: LoanGrant, issuedAt: Date, seizeToken: UUID) {
        self.grant = grant
        self.issuedAt = issuedAt
        self.seizeToken = seizeToken
    }
}

/// The pump's configuration, the therapy settings, and enough history for the first cycle.
public struct LoanGrant: Codable, Equatable {
    /// Increases with every grant; both sides refuse any other epoch.
    public let epoch: Int

    public let expiresAt: Date

    /// The pump's `SharedDeviceConfiguration`, as a binary property list.
    public let pumpConfiguration: Data

    public let podAddress: UInt32

    public let therapySettingsRaw: Data
    public let settingsTimeZoneID: String

    public let doseHistory: [LoanDoseRecord]

    /// The phone can tell an interim offer from a final one.
    public let supportsInterimHandback: Bool?

    /// The phone understands override records; without it overrides stay local to the watch.
    public let supportsOverrideRecords: Bool?

    public let integralRetrospectiveCorrectionEnabled: Bool?

    public let phoneClosedLoopEnabled: Bool?

    public let carbHistory: [LoanCarbRecord]?

    public let lastLoopCompleted: Date?

    /// Recent glucose, so the first prediction has momentum.
    public let glucoseHistory: [LoanGlucoseRecord]?

    public let activeOverrideRaw: Data?

    /// Schedules and insulin model, which the settings blob drops.
    public let therapySettingsSupplementRaw: Data?

    /// The phone's glucose alert settings (JSON), so the wrist sounds the same lows.
    public let glucoseAlertSettings: Data?

    /// The phone's overrides of the last 24 h, ended ones included, as a binary plist of raw values.
    public let overrideHistoryRaw: Data?

    /// The phone's settings over the last 24 h, up to the grant.
    public let settingsHistory: LoanSettingsHistory?

    public init(epoch: Int, expiresAt: Date, pumpConfiguration: Data, podAddress: UInt32,
                therapySettingsRaw: Data, settingsTimeZoneID: String,
                doseHistory: [LoanDoseRecord],
                supportsInterimHandback: Bool? = nil,
                supportsOverrideRecords: Bool? = nil,
                integralRetrospectiveCorrectionEnabled: Bool? = nil,
                phoneClosedLoopEnabled: Bool? = nil,
                carbHistory: [LoanCarbRecord]? = nil,
                glucoseHistory: [LoanGlucoseRecord]? = nil,
                activeOverrideRaw: Data? = nil,
                therapySettingsSupplementRaw: Data? = nil,
                lastLoopCompleted: Date? = nil,
                glucoseAlertSettings: Data? = nil,
                overrideHistoryRaw: Data? = nil,
                settingsHistory: LoanSettingsHistory? = nil) {
        self.epoch = epoch
        self.expiresAt = expiresAt
        self.pumpConfiguration = pumpConfiguration
        self.podAddress = podAddress
        self.therapySettingsRaw = therapySettingsRaw
        self.settingsTimeZoneID = settingsTimeZoneID
        self.doseHistory = doseHistory
        self.supportsInterimHandback = supportsInterimHandback
        self.supportsOverrideRecords = supportsOverrideRecords
        self.integralRetrospectiveCorrectionEnabled = integralRetrospectiveCorrectionEnabled
        self.phoneClosedLoopEnabled = phoneClosedLoopEnabled
        self.carbHistory = carbHistory
        self.glucoseHistory = glucoseHistory
        self.activeOverrideRaw = activeOverrideRaw
        self.therapySettingsSupplementRaw = therapySettingsSupplementRaw
        self.lastLoopCompleted = lastLoopCompleted
        self.glucoseAlertSettings = glucoseAlertSettings
        self.overrideHistoryRaw = overrideHistoryRaw
        self.settingsHistory = settingsHistory
    }
}

public struct TakeoverComplete: Codable, Equatable {
    public let epoch: Int
    public let firstPodStatus: LoanPodStatus

    public init(epoch: Int, firstPodStatus: LoanPodStatus) {
        self.epoch = epoch
        self.firstPodStatus = firstPodStatus
    }
}

public struct TakeoverFailed: Codable, Equatable {
    public let epoch: Int
    public let reason: String

    public init(epoch: Int, reason: String) {
        self.epoch = epoch
        self.reason = reason
    }
}

/// What the watch recorded since the last ack. Sent every cycle, empty or not, as a liveness signal.
public struct DoseRecordBatch: Codable, Equatable {
    public let epoch: Int
    public let events: [LoanEvent]
    public let tombstones: [UUID]

    public let odometer: LoanOdometerSnapshot?

    /// Liveness is judged by send time, not arrival.
    public let sentAt: Date?

    public init(epoch: Int, events: [LoanEvent], tombstones: [UUID],
                odometer: LoanOdometerSnapshot? = nil, sentAt: Date? = nil) {
        self.epoch = epoch
        self.events = events
        self.tombstones = tombstones
        self.odometer = odometer
        self.sentAt = sentAt
    }
}

/// The watch offering the pod back; resent until acked, and harmless to receive twice.
public struct HandbackOffer: Codable, Equatable {
    public let epoch: Int
    public let handedBackAt: Date
    public let finalStatus: LoanPodStatus?
    public let odometer: LoanOdometerSnapshot?
    public let events: [LoanEvent]
    public let tombstones: [UUID]
    public let recovered: Bool

    /// False: an interim offer, the watch still dosing. True: the pod is free.
    public let released: Bool?

    public let watchClosedLoopEnabled: Bool?

    /// Present for a loan grown from the standing copy, so the phone can adopt it.
    public let seizeToken: UUID?

    public let lastLoopCompleted: Date?

    public init(epoch: Int, handedBackAt: Date, finalStatus: LoanPodStatus?,
                odometer: LoanOdometerSnapshot?, events: [LoanEvent], tombstones: [UUID],
                recovered: Bool, released: Bool? = nil, watchClosedLoopEnabled: Bool? = nil,
                seizeToken: UUID? = nil,
                lastLoopCompleted: Date? = nil) {
        self.epoch = epoch
        self.handedBackAt = handedBackAt
        self.finalStatus = finalStatus
        self.odometer = odometer
        self.events = events
        self.tombstones = tombstones
        self.recovered = recovered
        self.released = released
        self.watchClosedLoopEnabled = watchClosedLoopEnabled
        self.seizeToken = seizeToken
        self.lastLoopCompleted = lastLoopCompleted
    }
}

public struct HandbackAck: Codable, Equatable {
    public let epoch: Int
    public let committedCursor: Int
    public let stale: Bool

    public init(epoch: Int, committedCursor: Int, stale: Bool = false) {
        self.epoch = epoch
        self.committedCursor = committedCursor
        self.stale = stale
    }
}

public struct Revoke: Codable, Equatable {
    public let epoch: Int

    public init(epoch: Int) {
        self.epoch = epoch
    }
}

public struct StatusQuery: Codable, Equatable {
    public let epoch: Int

    public init(epoch: Int) {
        self.epoch = epoch
    }
}

public struct StatusReport: Codable, Equatable {
    public let epoch: Int
    public let mode: LoanDosingMode

    public let lastDirectGlucoseAge: TimeInterval?
    public let lastEventSeq: Int
    public let podFault: String?
    public let holdsPod: Bool

    public let knowsGrant: Bool?

    public init(epoch: Int, mode: LoanDosingMode, lastDirectGlucoseAge: TimeInterval?,
                lastEventSeq: Int, podFault: String?, holdsPod: Bool, knowsGrant: Bool? = nil) {
        self.epoch = epoch
        self.mode = mode
        self.lastDirectGlucoseAge = lastDirectGlucoseAge
        self.lastEventSeq = lastEventSeq
        self.podFault = podFault
        self.holdsPod = holdsPod
        self.knowsGrant = knowsGrant
    }
}

public struct ProtocolNack: Codable, Equatable {
    public let seenVersion: Int?
    public let supportedVersions: [Int]

    public init(seenVersion: Int?, supportedVersions: [Int] = [LoanProtocol.version]) {
        self.seenVersion = seenVersion
        self.supportedVersions = supportedVersions
    }
}

public struct LoanDenied: Codable, Equatable {
    public let reason: String
    public init(reason: String) { self.reason = reason }
}

public struct LoanDiag: Codable, Equatable {
    public let epoch: Int
    public let text: String
    public init(epoch: Int, text: String) {
        self.epoch = epoch
        self.text = text
    }
}
