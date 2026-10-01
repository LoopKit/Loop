//
//  LoanMessages.swift
//  LoopCore — one module, linked by both the phone app and the watch app.
//
//  The messages the two apps exchange, and what each one carries.
//
//  Every field added since the format froze is Optional, and nil must mean "an older build sent
//  this, behave as that build's counterpart did" — never "no". The apps install separately, so a
//  watch newer than its phone is routine, and an older decoder simply drops a key it has never
//  heard of. A required field added here would strand every session with an older counterpart.
//

import Foundation
import HealthKit
import LoopKit

extension LoanGrant {
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
}

/// What the pod itself reported, at a moment. Carried at takeover and again at hand-back so
/// both sides can see the pod's own account rather than only each other's.
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

    /// Identifies this request so a redelivered copy can be recognised. The transport can
    /// deliver the same payload twice; without this the phone treats the second as a new
    /// request, takes the pod back to grant it again, and the watch ends up holding a grant for
    /// a pod the phone has re-armed.
    public let requestID: String?

    /// Whether this watch can start a session without the phone. The phone only keeps its
    /// standing copy refreshed for a watch that says yes.
    public let supportsSeize: Bool?

    /// When the watch sent it. A request that has been sitting in a queue must not be granted:
    /// the user asked minutes ago and has long since seen it fail.
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

/// The standing copy the phone keeps on the watch so a session can start without it.
///
/// It is a complete grant that has not been activated. The watch stores the newest one and uses
/// it only when the user confirms a start the phone did not answer.
public struct DormantGrant: Codable, Equatable {
    public let grant: LoanGrant
    public let issuedAt: Date

    /// Identifies the copy, so that when the phone comes back it can recognise the session as
    /// one grown from its own credential rather than an unexplained loan.
    public let seizeToken: UUID

    public init(grant: LoanGrant, issuedAt: Date, seizeToken: UUID) {
        self.grant = grant
        self.issuedAt = issuedAt
        self.seizeToken = seizeToken
    }
}

/// Everything the watch needs to run the loop with the pod: the pod itself, the therapy
/// settings to dose by, and enough history to be right from the first cycle rather than after
/// a warm-up.
public struct LoanGrant: Codable, Equatable {
    /// Which session this is. It increases with every grant, and both sides refuse anything
    /// stamped with an epoch that is not the one they are running — which is what stops a late
    /// message from a finished session being applied to a live one.
    public let epoch: Int

    public let expiresAt: Date

    public let pumpManagerRawState: Data

    public let podAddress: UInt32

    public let therapySettingsRaw: Data
    public let settingsTimeZoneID: String

    public let doseHistory: [LoanDoseRecord]

    /// Whether the phone can tell an interim hand-back offer from a final one. An older phone
    /// drops the flag that distinguishes them and reads the first interim offer as the end of
    /// the session — taking the pod back while the watch is still dosing.
    public let supportsInterimHandback: Bool?

    /// Whether the phone understands override records. Without it the watch still applies an
    /// override locally, and says plainly that it will not follow the pod home.
    public let supportsOverrideRecords: Bool?

    public let integralRetrospectiveCorrectionEnabled: Bool?

    public let phoneClosedLoopEnabled: Bool?

    public let carbHistory: [LoanCarbRecord]?

    public let lastLoopCompleted: Date?

    /// Recent glucose, so the watch's first prediction has momentum and retrospective
    /// correction to work from instead of starting cold.
    public let glucoseHistory: [LoanGlucoseRecord]?

    public let predictionSnapshot: LoanPredictionSnapshot?

    public let activeOverrideRaw: Data?

    /// Basal schedule, sensitivity, carb ratio and the default insulin model, carried
    /// separately because the settings blob above drops all four. A watch missing schedules
    /// refuses the loan out loud; one missing the insulin model would dose on a default and say
    /// nothing, which is worse.
    public let therapySettingsSupplementRaw: Data?

    public init(epoch: Int, expiresAt: Date, pumpManagerRawState: Data, podAddress: UInt32,
                therapySettingsRaw: Data, settingsTimeZoneID: String,
                doseHistory: [LoanDoseRecord],
                supportsInterimHandback: Bool? = nil,
                supportsOverrideRecords: Bool? = nil,
                integralRetrospectiveCorrectionEnabled: Bool? = nil,
                phoneClosedLoopEnabled: Bool? = nil,
                carbHistory: [LoanCarbRecord]? = nil,
                glucoseHistory: [LoanGlucoseRecord]? = nil,
                predictionSnapshot: LoanPredictionSnapshot? = nil,
                activeOverrideRaw: Data? = nil,
                therapySettingsSupplementRaw: Data? = nil,
                lastLoopCompleted: Date? = nil) {
        self.epoch = epoch
        self.expiresAt = expiresAt
        self.pumpManagerRawState = pumpManagerRawState
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
        self.predictionSnapshot = predictionSnapshot
        self.activeOverrideRaw = activeOverrideRaw
        self.therapySettingsSupplementRaw = therapySettingsSupplementRaw
        self.lastLoopCompleted = lastLoopCompleted
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

/// The watch's ordinary report: what it has recorded since the phone last acknowledged.
///
/// Sent every cycle even when there is nothing new, because an empty batch is still the watch
/// saying it is alive and looping.
public struct DoseRecordBatch: Codable, Equatable {
    public let epoch: Int
    public let events: [LoanEvent]
    public let tombstones: [UUID]

    public let odometer: LoanOdometerSnapshot?

    /// When the watch sent it. The phone judges the watch's liveness by this rather than by
    /// arrival: a batch that spent an hour in a queue proves nothing about now.
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

/// The watch offering the pod back, with everything it has not yet had acknowledged.
///
/// It is sent repeatedly until the phone acknowledges, and the same offer arriving twice must
/// be harmless — the phone commits by event identity, not by the offer.
public struct HandbackOffer: Codable, Equatable {
    public let epoch: Int
    public let handedBackAt: Date
    public let finalStatus: LoanPodStatus?
    public let odometer: LoanOdometerSnapshot?
    public let events: [LoanEvent]
    public let tombstones: [UUID]
    public let recovered: Bool

    /// Whether the watch has actually let go of the pod. An interim offer (false) means the
    /// watch is still dosing and only sending its records ahead; the final offer (true) means
    /// the pod is free. A phone that cannot read this flag must be told so by the grant's
    /// capability field, or it will reclaim during a session that is still running.
    public let released: Bool?

    public let watchClosedLoopEnabled: Bool?

    /// Present when the session grew from the standing copy, so a phone that never granted it
    /// can recognise its own credential and adopt the session instead of treating the records
    /// as belonging to nothing.
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
