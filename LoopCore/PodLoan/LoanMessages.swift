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
        SharedDeviceConfiguration(propertyList: pumpConfiguration)
    }

    /// The services' configurations that decode.
    public var sharedServiceConfigurations: [SharedDeviceConfiguration] {
        (serviceConfigurations ?? []).compactMap(SharedDeviceConfiguration.init(propertyList:))
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

/// The watch asking for the pod.
public struct LoanRequest: Codable, Equatable {
    public let watchBuild: String

    /// Lets the phone recognise a redelivered copy of the same request.
    public let requestID: String?

    /// A request that sat in a queue is not granted.
    public let sentAt: Date?

    /// The highest loan number the watch knows, so the phone grants above it: a loan the watch
    /// started alone can be numbered past the phone's own count.
    public let knownEpoch: Int?

    public init(watchBuild: String,
                requestID: String = UUID().uuidString,
                sentAt: Date? = nil,
                knownEpoch: Int? = nil) {
        self.watchBuild = watchBuild
        self.requestID = requestID
        self.sentAt = sentAt
        self.knownEpoch = knownEpoch
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

    public let therapySettingsRaw: Data
    public let settingsTimeZoneID: String

    public let doseHistory: [LoanDoseRecord]

    public let integralRetrospectiveCorrectionEnabled: Bool?

    public let glucoseBasedApplicationFactorEnabled: Bool?

    public let guardAndRunwayEnabled: Bool?

    /// The phone's volatility baseline for guard + runway (LoopAlgorithm's `volatilityBaseline`).
    public let volatilityBaseline: Double?

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

    /// The phone's remote services that share their configuration (Nightscout, Tidepool), each a binary
    /// property list of its `SharedDeviceConfiguration`, so the wrist uploads during the loan. They
    /// hold secrets: Start grants only, never the standing copy, never logged.
    public var serviceConfigurations: [Data]? = nil

    /// The phone's CGM's answer to "upload glucose?" (the CGM simulator's "Upload CGM Samples"),
    /// which the wrist follows while it has no CGM of its own. Nil from an older phone.
    public var phoneCGMUploadsGlucose: Bool? = nil

    public init(epoch: Int, expiresAt: Date, pumpConfiguration: Data,
                therapySettingsRaw: Data, settingsTimeZoneID: String,
                doseHistory: [LoanDoseRecord],
                integralRetrospectiveCorrectionEnabled: Bool? = nil,
                glucoseBasedApplicationFactorEnabled: Bool? = nil,
                guardAndRunwayEnabled: Bool? = nil,
                volatilityBaseline: Double? = nil,
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
        self.therapySettingsRaw = therapySettingsRaw
        self.settingsTimeZoneID = settingsTimeZoneID
        self.doseHistory = doseHistory
        self.integralRetrospectiveCorrectionEnabled = integralRetrospectiveCorrectionEnabled
        self.glucoseBasedApplicationFactorEnabled = glucoseBasedApplicationFactorEnabled
        self.guardAndRunwayEnabled = guardAndRunwayEnabled
        self.volatilityBaseline = volatilityBaseline
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

    /// The latest the loan could have started: nothing is logged or sent before a loan starts. What the
    /// phone judges a claim by (control row 19); nil when the batch is empty and carries no send time.
    public var startedNoLaterThan: Date? {
        (events.map(\.loggedAt) + [sentAt].compactMap { $0 }).min()
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

    /// Per remote service (its `pluginIdentifier`), the data types the watch confirmed it uploaded
    /// in full before releasing ("Glucose", "DosingDecision"): the phone skips those, and uploads
    /// the rest itself. Released offers only; nil from an older watch.
    public let uploadsConfirmed: [String: [String]]?

    public init(epoch: Int, handedBackAt: Date, finalStatus: LoanPodStatus?,
                odometer: LoanOdometerSnapshot?, events: [LoanEvent], tombstones: [UUID],
                recovered: Bool, released: Bool? = nil, watchClosedLoopEnabled: Bool? = nil,
                seizeToken: UUID? = nil,
                lastLoopCompleted: Date? = nil,
                uploadsConfirmed: [String: [String]]? = nil) {
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
        self.uploadsConfirmed = uploadsConfirmed
    }

    /// The services whose `type` the watch confirmed it uploaded in full.
    public func servicesConfirming(_ type: String) -> Set<String> {
        Set((uploadsConfirmed ?? [:]).filter { $0.value.contains(type) }.keys)
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

    public let lastDirectGlucoseAge: TimeInterval?
    public let lastEventSeq: Int
    public let podFault: String?
    public let holdsPod: Bool

    public let knowsGrant: Bool?

    /// With `holdsPod`: whether the watch reached the pod on its last cycle. A holder that cannot reach
    /// the pod is answered like silence. Absent from older watches.
    public let podReachable: Bool?
    /// With `holdsPod`: when the watch's loan started, so a phone that took over on silence can tell a
    /// revived claim from a fresh Start. Absent from older watches.
    public let loanStartedAt: Date?

    public init(epoch: Int, lastDirectGlucoseAge: TimeInterval?,
                lastEventSeq: Int, podFault: String?, holdsPod: Bool, knowsGrant: Bool? = nil,
                podReachable: Bool? = nil, loanStartedAt: Date? = nil) {
        self.epoch = epoch
        self.lastDirectGlucoseAge = lastDirectGlucoseAge
        self.lastEventSeq = lastEventSeq
        self.podFault = podFault
        self.holdsPod = holdsPod
        self.knowsGrant = knowsGrant
        self.podReachable = podReachable
        self.loanStartedAt = loanStartedAt
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

extension PumpManagerStatus.BolusState {
    /// This pump's own bolus as the bolus rule sees it: being started, given or cancelled.
    public var underWay: LoanControl.BolusUnderWay? {
        switch self {
        case .noBolus: return nil
        case .inProgress(let dose): return LoanControl.BolusUnderWay(endsAt: dose.endDate)
        case .initiating, .canceling: return LoanControl.BolusUnderWay(endsAt: nil)
        }
    }
}

extension SharedDeviceConfiguration {
    /// As a grant carries it: a binary property list.
    public var propertyList: Data? {
        try? PropertyListSerialization.data(fromPropertyList: rawValue, format: .binary, options: 0)
    }

    public init?(propertyList data: Data) {
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let raw = plist as? RawValue else { return nil }
        self.init(rawValue: raw)
    }
}
