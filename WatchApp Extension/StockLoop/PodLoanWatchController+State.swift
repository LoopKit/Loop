//
//  PodLoanWatchController+State.swift
//  WatchApp Extension
//
//  The watch controller's persisted state: one value, saved and restored as a unit, like a
//  device manager's state.
//

import Foundation
import LoopCore

struct PodLoanWatchState: RawRepresentable {
    static let version = 1

    var phase: PodLoanWatchController.Phase = .idle
    /// The live loan's epoch; cleared at close.
    var epoch: Int?
    /// The highest epoch ever accepted; never cleared, so a spent epoch is never reused.
    var highWaterEpoch = 0
    /// The newest revoke heard; any grant at or below it is refused, across relaunches too.
    var lastRevokedEpoch: Int?

    /// What a resume needs from the grant: the settings, and the phone's capability flags.
    struct GrantedSettings {
        var therapySettingsRaw: Data
        var supplementRaw: Data?
        var supportsInterimHandback: Bool
        var supportsOverrideRecords: Bool
        var glucoseAlertSettings: Data? = nil
        var settingsHistory: LoanSettingsHistory? = nil
    }
    var grantedSettings: GrantedSettings?

    /// The odometer at takeover; every audit is measured from it.
    var deliveredAtTakeover: Double?
    /// The reunion token for a seized loan, echoed by every offer until the loan closes.
    var seizeToken: UUID?

    init() {}

    init?(rawValue: [String: Any]) {
        phase = (rawValue["phase"] as? String).flatMap(PodLoanWatchController.Phase.init(rawValue:)) ?? .idle
        epoch = rawValue["epoch"] as? Int
        highWaterEpoch = rawValue["highWaterEpoch"] as? Int ?? 0
        lastRevokedEpoch = rawValue["lastRevokedEpoch"] as? Int
        grantedSettings = (rawValue["grantedSettings"] as? [String: Any]).flatMap(Self.grantedSettings(from:))
        deliveredAtTakeover = rawValue["deliveredAtTakeover"] as? Double
        seizeToken = (rawValue["seizeToken"] as? String).flatMap(UUID.init(uuidString:))
    }

    var rawValue: [String: Any] {
        var raw: [String: Any] = ["version": Self.version, "phase": phase.rawValue, "highWaterEpoch": highWaterEpoch]
        raw["epoch"] = epoch
        raw["lastRevokedEpoch"] = lastRevokedEpoch
        raw["grantedSettings"] = grantedSettings.map {
            var d: [String: Any] = ["raw": $0.therapySettingsRaw, "interim": $0.supportsInterimHandback,
                                    "overrideRecords": $0.supportsOverrideRecords]
            d["supplement"] = $0.supplementRaw
            d["glucoseAlerts"] = $0.glucoseAlertSettings
            d["settingsHistory"] = $0.settingsHistory.flatMap { try? LoanProtocol.encoder.encode($0) }
            return d
        }
        raw["deliveredAtTakeover"] = deliveredAtTakeover
        raw["seizeToken"] = seizeToken?.uuidString
        return raw
    }

    /// The settings' dictionary shape in the state file.
    static func grantedSettings(from d: [String: Any]) -> GrantedSettings? {
        guard let raw = d["raw"] as? Data else { return nil }
        return GrantedSettings(therapySettingsRaw: raw, supplementRaw: d["supplement"] as? Data,
                               supportsInterimHandback: d["interim"] as? Bool ?? false,
                               supportsOverrideRecords: d["overrideRecords"] as? Bool ?? false,
                               glucoseAlertSettings: d["glucoseAlerts"] as? Data,
                               settingsHistory: (d["settingsHistory"] as? Data).flatMap {
                                   try? LoanProtocol.decoder.decode(LoanSettingsHistory.self, from: $0)
                               })
    }

}

extension PodLoanWatchController {
    /// A file-backed value in `directory`, or in the app's default location.
    static func fileStore<V>(_ key: String, in directory: URL?) -> PersistedProperty<V> {
        directory.map { PersistedProperty<V>(key: key, directory: $0) } ?? PersistedProperty(key: key)
    }

    /// The persisted state, readable from any queue.
    var persisted: PodLoanWatchState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _persisted
    }

    /// Applies one change and writes the whole value once, before returning. Phase observers
    /// run afterwards, outside the lock.
    func updateState(_ change: (inout PodLoanWatchState) -> Void) {
        stateLock.lock()
        let old = _persisted.phase
        change(&_persisted)
        stateStore.wrappedValue = _persisted.rawValue
        let new = _persisted.phase
        stateLock.unlock()
        phaseDidChange(from: old, to: new)
    }

    /// The loan phase; its observers drive the mirrors, runtime holds and the glance.
    var phase: Phase {
        get { persisted.phase }
        set { updateState { $0.phase = newValue } }
    }

    var epoch: Int? {
        get { persisted.epoch }
        set { updateState { $0.epoch = newValue } }
    }

    /// Recorded before matching the epoch, so any grant at or below it is refused.
    var lastRevokedEpoch: Int? {
        get { persisted.lastRevokedEpoch }
        set { updateState { $0.lastRevokedEpoch = newValue } }
    }

    var deliveredAtTakeover: Double? {
        get { persisted.deliveredAtTakeover }
        set { updateState { $0.deliveredAtTakeover = newValue } }
    }

    /// Mirrored synchronously, so main-thread readers never lag the queue.
    func phaseDidChange(from oldValue: Phase, to phase: Phase) {
        loanActiveMirrorLock.lock()
        _loanActiveMirror = (phase == .active)
        loanActiveMirrorLock.unlock()
        // Holds are edge-triggered, so re-asserting a phase cannot double-acquire.
        if (oldValue == .takingOver) != (phase == .takingOver) {
            onTakeoverRadioHold?(phase == .takingOver)
            setTakeoverSessionListener(phase == .takingOver)
        }
        if (oldValue == .handingBack) != (phase == .handingBack) {
            onHandbackRuntimeHold?(phase == .handingBack)
        }
        if oldValue != phase {
            NotificationCenter.default.post(name: .podLoanPhaseDidChange, object: nil)
        }
    }
}
