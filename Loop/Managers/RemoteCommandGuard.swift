//
//  RemoteCommandGuard.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Rejects a remote command when insulin or carbs were recorded that its sender had not seen.
///
/// A treatment is unknown to the sender when it is dated after the command was sent (carbs: and not after now),
/// when it was last edited after the command was sent or after the newest treatment the sender had fetched,
/// or, when the context lists the treatments the sender had seen and the treatment was created after the
/// service started recording uploads, when it is not among them.
struct RemoteCommandGuard {

    struct Treatment: Equatable {
        var syncIdentifier: String?
        var date: Date
        /// Units for insulin, grams for carbs
        var amount: Double
        /// When the user created the entry, when known
        var createdDate: Date? = nil
        /// When the user last edited the entry; an edited entry keeps its Nightscout `_id`
        var updatedDate: Date? = nil
    }

    enum Kind {
        case insulin
        case carbs
    }

    enum UnknownReason: Equatable {
        case recordedAfterSend
        case notSeen
        case notUploaded
    }

    /// How far back treatments are considered
    static let lookbackInterval = TimeInterval(hours: 6)

    /// A bolus is rejected when unknown insulin is at least this fraction of the requested amount
    static let unknownInsulinFraction = 0.2

    /// Tolerance for comparing insulin amounts
    static let insulinTolerance = 1e-6

    let context: RemoteCommandContext
    let now: Date

    func unknownReason(for treatment: Treatment, kind: Kind) -> UnknownReason? {
        guard treatment.date >= now.addingTimeInterval(-Self.lookbackInterval) else {
            return nil
        }
        if isAfterSend(treatment.date, kind: kind) || treatment.updatedDate.map({ $0 > editCutoff }) == true {
            return .recordedAfterSend
        }
        if let known = context.knownTreatments, (treatment.createdDate ?? treatment.date) > known.recordedSince {
            guard let syncIdentifier = treatment.syncIdentifier, known.uploadedSyncIdentifiers.contains(syncIdentifier) else {
                return .notUploaded
            }
            if !known.syncIdentifiers.contains(syncIdentifier) {
                return .notSeen
            }
        }
        return nil
    }

    /// Insulin dated after now counts, as the pump clock can be ahead; future-dated carbs are judged by the marker rule only
    private func isAfterSend(_ date: Date, kind: Kind) -> Bool {
        switch kind {
        case .insulin:
            return date > context.sentAt
        case .carbs:
            return date > context.sentAt && date <= now
        }
    }

    /// The send time, or the marker's time when it is earlier
    private var editCutoff: Date {
        guard let markerDate = context.knownTreatments?.markerDate else {
            return context.sentAt
        }
        return min(context.sentAt, markerDate)
    }

    func checkBolus(amountInUnits: Double, boluses: [Treatment]) throws {
        let unknown = boluses.compactMap { bolus in unknownReason(for: bolus, kind: .insulin).map { (bolus, $0) } }
        let unknownUnits = unknown.reduce(0) { $0 + $1.0.amount }
        guard unknownUnits > 0, unknownUnits + Self.insulinTolerance >= amountInUnits * Self.unknownInsulinFraction else {
            return
        }
        if unknown.allSatisfy({ $0.1 == .notUploaded }) {
            throw RemoteCommandGuardError.insulinNotUploaded(units: unknownUnits)
        } else {
            throw RemoteCommandGuardError.unknownInsulin(units: unknownUnits)
        }
    }

    func checkCarbs(carbEntries: [Treatment]) throws {
        let unknownGrams = carbEntries.filter { unknownReason(for: $0, kind: .carbs) != nil }.map { $0.amount }
        if !unknownGrams.isEmpty {
            throw RemoteCommandGuardError.unknownCarbs(grams: unknownGrams)
        }
    }

    /// Boluses whose start dates and programmed amounts are within these tolerances are the same bolus; Trio uses the same values
    static let sameBolusDateTolerance = TimeInterval(10)
    static let sameBolusUnitsTolerance = 0.025

    /// A pump manager's bolus in progress can carry a different syncIdentifier, or none, than the stored entry for the same bolus
    static func isSameBolus(_ a: DoseEntry, _ b: DoseEntry) -> Bool {
        if let syncIdentifier = a.syncIdentifier, syncIdentifier == b.syncIdentifier {
            return true
        }
        return abs(a.startDate.timeIntervalSince(b.startDate)) <= sameBolusDateTolerance
            && abs(a.programmedUnits - b.programmedUnits) <= sameBolusUnitsTolerance + insulinTolerance
    }

    /// Boluses from the dose history plus the pump's bolus in progress, when the history does not yet hold it
    static func bolusCandidates(history: [DoseEntry], inProgress: DoseEntry?) -> [DoseEntry] {
        var candidates = history
        if let inProgress, !history.contains(where: { isSameBolus($0, inProgress) }) {
            candidates.append(inProgress)
        }
        return candidates
    }
}

enum RemoteCommandGuardError: RemoteCommandRejection, Equatable {
    case unknownInsulin(units: Double)
    case insulinNotUploaded(units: Double)
    case unknownCarbs(grams: [Double])
    case historyUnavailable

    var errorDescription: String? {
        switch self {
        case .unknownInsulin(let units):
            return String(format: NSLocalizedString("Command rejected: %1$@ U of insulin was delivered after the command was sent (or after the newest treatment you had seen).", comment: "Remote bolus error description: insulin the sender had not seen. (1: units of insulin)"), Self.format(units, scale: 2))
        case .insulinNotUploaded(let units):
            return String(format: NSLocalizedString("Command rejected: %1$@ U of insulin has not been uploaded to Nightscout yet.", comment: "Remote bolus error description: insulin not yet uploaded. (1: units of insulin)"), Self.format(units, scale: 2))
        case .unknownCarbs(let grams):
            if grams.count == 1 {
                return String(format: NSLocalizedString("Command rejected: a carb entry of %1$@ g was recorded that you had not seen.", comment: "Remote carb error description: one carb entry the sender had not seen. (1: grams of carbs)"), Self.format(grams[0], scale: 0))
            } else {
                return String(format: NSLocalizedString("Command rejected: %1$d carb entries totaling %2$@ g were recorded that you had not seen.", comment: "Remote carb error description: several carb entries the sender had not seen. (1: number of entries, 2: total grams of carbs)"), grams.count, Self.format(grams.reduce(0, +), scale: 0))
            }
        case .historyUnavailable:
            return NSLocalizedString("Command rejected: treatment history is not available.", comment: "Remote command error description: treatment history could not be checked.")
        }
    }

    var replyText: String {
        switch self {
        case .unknownInsulin(let units):
            return "Command rejected: \(Self.format(units, scale: 2)) U of insulin was delivered after the command was sent (or after the newest treatment you had seen)."
        case .insulinNotUploaded(let units):
            return "Command rejected: \(Self.format(units, scale: 2)) U of insulin has not been uploaded to Nightscout yet."
        case .unknownCarbs(let grams):
            if grams.count == 1 {
                return "Command rejected: a carb entry of \(Self.format(grams[0], scale: 0)) g was recorded that you had not seen."
            } else {
                return "Command rejected: \(grams.count) carb entries totaling \(Self.format(grams.reduce(0, +), scale: 0)) g were recorded that you had not seen."
            }
        case .historyUnavailable:
            return "Command rejected: treatment history is not available."
        }
    }

    /// `value` rounded half up to `scale` decimals from its shortest decimal representation, printed with "." and without trailing zeros, as Trio prints it
    static func format(_ value: Double, scale: Int) -> String {
        var input = Decimal(string: "\(value)", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, scale, .plain)
        return NSDecimalNumber(decimal: rounded).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }
}

enum RemoteBolusDeliveryError: RemoteCommandRejection, Equatable {
    case uncertainDelivery

    var errorDescription: String? {
        switch self {
        case .uncertainDelivery:
            return NSLocalizedString("Bolus may have been delivered. Check the history before sending another bolus.", comment: "Remote bolus error description: the pump did not confirm whether the bolus was delivered.")
        }
    }

    var replyText: String {
        switch self {
        case .uncertainDelivery:
            return "Bolus may have been delivered. Check the history before sending another bolus."
        }
    }
}

extension RemoteCommandGuard.Treatment {
    /// Uses programmed units while the bolus is in progress or has no delivered amount
    init(bolus: DoseEntry) {
        let units = bolus.isMutable ? bolus.programmedUnits : (bolus.deliveredUnits ?? bolus.programmedUnits)
        self.init(syncIdentifier: bolus.syncIdentifier, date: bolus.startDate, amount: units)
    }

    init(carbEntry: StoredCarbEntry) {
        self.init(
            syncIdentifier: carbEntry.syncIdentifier,
            date: carbEntry.startDate,
            amount: carbEntry.quantity.doubleValue(for: .gram),
            createdDate: carbEntry.userCreatedDate,
            updatedDate: carbEntry.userUpdatedDate
        )
    }
}

@MainActor
protocol RemoteCommandTreatmentSource: AnyObject {
    func bolusHistory(since start: Date) async throws -> [DoseEntry]
    var bolusInProgress: DoseEntry? { get }
    func carbEntries(since start: Date) async throws -> [StoredCarbEntry]
    /// The amount the pump delivers for a requested bolus
    func roundToSupportedBolusVolume(units: Double) -> Double
}

/// Runs remote bolus and carb commands one at a time, each checked by `RemoteCommandGuard` before delivery.
@MainActor
final class RemoteCommandGate {

    /// How long an accepted remote bolus is counted while it is missing from the dose history
    static let acceptedBolusRetention = TimeInterval(minutes: 15)

    weak var treatmentSource: RemoteCommandTreatmentSource?

    private let now: () -> Date

    private var lastCommand: Task<Void, Never>?

    /// The most recent remote bolus accepted, until the dose history or the pump shows it, or for `acceptedBolusRetention`
    private(set) var acceptedRemoteBolus: DoseEntry?

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func deliverBolus(amountInUnits: Double, context: RemoteCommandContext?, deliver: @escaping @MainActor () async throws -> Void) async throws {
        try await serially {
            if let context {
                try await self.checkBolus(amountInUnits: amountInUnits, context: context)
            }
            let units = self.treatmentSource?.roundToSupportedBolusVolume(units: amountInUnits) ?? amountInUnits
            let accepted = DoseEntry(type: .bolus, startDate: self.now(), value: units, unit: .units, isMutable: true)
            do {
                try await deliver()
            } catch PumpManagerError.uncertainDelivery {
                // The bolus may have been delivered, so later commands count it
                self.acceptedRemoteBolus = accepted
                throw RemoteBolusDeliveryError.uncertainDelivery
            }
            self.acceptedRemoteBolus = accepted
        }
    }

    func deliverCarbs(context: RemoteCommandContext?, deliver: @escaping @MainActor () async throws -> Void) async throws {
        try await serially {
            if let context {
                try await self.checkCarbs(context: context)
            }
            try await deliver()
        }
    }

    private func checkBolus(amountInUnits: Double, context: RemoteCommandContext) async throws {
        guard let treatmentSource else {
            throw RemoteCommandGuardError.historyUnavailable
        }
        let now = now()
        let history = try await treatmentSource.bolusHistory(since: now.addingTimeInterval(-RemoteCommandGuard.lookbackInterval))
        var candidates = RemoteCommandGuard.bolusCandidates(history: history, inProgress: treatmentSource.bolusInProgress)
        if let accepted = acceptedRemoteBolus {
            if now.timeIntervalSince(accepted.startDate) > Self.acceptedBolusRetention
                || candidates.contains(where: { Self.shows($0, accepted: accepted) })
            {
                acceptedRemoteBolus = nil
            } else {
                candidates.append(accepted)
            }
        }
        try RemoteCommandGuard(context: context, now: now).checkBolus(amountInUnits: amountInUnits, boluses: candidates.map { RemoteCommandGuard.Treatment(bolus: $0) })
    }

    /// A bolus shows the accepted one when it is not automatic, starts at most `sameBolusDateTolerance` before it,
    /// and has the same programmed units within `sameBolusUnitsTolerance`; Trio uses the same rule
    static func shows(_ bolus: DoseEntry, accepted: DoseEntry) -> Bool {
        bolus.automatic != true
            && bolus.startDate >= accepted.startDate.addingTimeInterval(-RemoteCommandGuard.sameBolusDateTolerance)
            && abs(bolus.programmedUnits - accepted.programmedUnits) <= RemoteCommandGuard.sameBolusUnitsTolerance + RemoteCommandGuard.insulinTolerance
    }

    private func checkCarbs(context: RemoteCommandContext) async throws {
        guard let treatmentSource else {
            throw RemoteCommandGuardError.historyUnavailable
        }
        let now = now()
        let entries = try await treatmentSource.carbEntries(since: now.addingTimeInterval(-RemoteCommandGuard.lookbackInterval))
        try RemoteCommandGuard(context: context, now: now).checkCarbs(carbEntries: entries.map { RemoteCommandGuard.Treatment(carbEntry: $0) })
    }

    private func serially(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = lastCommand
        let task = Task { @MainActor in
            await previous?.value
            try await operation()
        }
        lastCommand = Task { _ = try? await task.value }
        try await task.value
    }
}
