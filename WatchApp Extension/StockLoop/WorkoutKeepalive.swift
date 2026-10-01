// WorkoutKeepalive.swift — the background-runtime vehicle for the watch loop.
//
// watchOS suspends a backgrounded third-party app within seconds, and there is NO CoreBluetooth
// state restoration on watchOS — so a suspended app cannot be woken by a BLE event. An
// HKWorkoutSession is the only self-service API that keeps our process (and its BLE links) alive.
// That is what lets the loop keep dosing and lets stock G7SensorKit keep receiving with the wrist
// down. Riding the Dexcom watch app's authenticated session buys us DATA, not RUNTIME:
// entitlements are not inheritable by a co-resident app.
//
// More than one subsystem can want the keepalive at once, so holds are REFCOUNTED BY REASON —
// "loanWorkout" for the duration of a loan, plus "takeover" and "handback" for the two bounded windows
// that need runtime of their own. Releasing one can never stop a session another still wants.
// Owned by StockLoopSession, which drives all three.
//
import Foundation
import HealthKit

final class WorkoutKeepalive: NSObject, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var holders: Set<String> = []
    private var authOK = false
    private var authInFlight = false
    private var recoverInFlight = false
    private var recoveryProbed = false
    private var recoverGeneration: UInt64 = 0

    // Everything above is MAIN-only — every entry point funnels through `onMain`. The tag and the
    // held flag below are lock-guarded because the runtime heartbeat samples them from its own
    // queue while this class is mid-callback.
    private let tagLock = NSLock()
    private var _tag = "keepalive off"

    var stateTag: String { tagLock.lock(); defer { tagLock.unlock() }; return _tag }
    private func setTag(_ s: String) { tagLock.lock(); _tag = s; tagLock.unlock() }

    private var _held = false
    var isHeld: Bool { tagLock.lock(); defer { tagLock.unlock() }; return _held }
    private func setHeld(_ v: Bool) { tagLock.lock(); _held = v; tagLock.unlock() }

    override init() {
        super.init()
        RuntimeStateLog.keepaliveProbe = { [weak self] in self?.stateTag ?? "keepalive ?" }
    }

    /// Take a hold under `reason`. Holds are refcounted BY REASON, so releasing one can never
    /// stop a session another subsystem still wants. The whole-loan holder is off unless its
    /// diagnostics default is set, so in an ordinary loan only the takeover and hand-back windows
    /// hold runtime and the app sleeps between bursts.
    func acquire(_ reason: String) { setHeld(true); onMain { self.holders.insert(reason); self.startSessionIfNeeded() } }

    /// Drop this reason's hold. The session ends only when the last holder goes.
    func release(_ reason: String) { onMain { self.holders.remove(reason); if self.holders.isEmpty { self.setHeld(false); self.endSession() } } }

    /// Re-drive the start path without taking a hold — for a wake that finds holders but no
    /// session, which is how a session lost while suspended is noticed.
    func ensureRunning() { onMain { self.startSessionIfNeeded() } }

    /// Adopt a session that outlived us before starting a new one: after a relaunch mid-loan
    /// watchOS can still be holding ours, and starting a second on top of it fails. Probed once
    /// per process — after that, straight to authorisation and start.
    private func startSessionIfNeeded() {
        guard session == nil, !authInFlight, !recoverInFlight else { return }
        guard !holders.isEmpty else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            SportLog.event("keepalive", "HealthKit unavailable on this device")
            return
        }

        guard !recoveryProbed else { authoriseThenStart(); return }
        recoveryProbed = true
        recoverInFlight = true
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            guard let self else { return }
            self.onMain {
                self.recoverInFlight = false
                if let error {
                    SportLog.event("keepalive", "recoverActiveWorkoutSession error: \(error)")
                }

                // Holders can all have gone away while the probe was out. End what was found
                // rather than adopting a session nothing wants.
                guard !self.holders.isEmpty, self.session == nil else {
                    if let recovered { recovered.end() }
                    return
                }
                if let recovered, [.running, .paused, .prepared].contains(recovered.state) {
                    recovered.delegate = self
                    self.session = recovered
                    self.authOK = true
                    self.setTag("keepalive recovered(\(self.holderTag()))")
                    SportLog.event("keepalive", "adopted a surviving HKWorkoutSession (state \(recovered.state.rawValue)) — no new session needed (holders: \(self.holderTag()))")
                    return
                }
                if let recovered {
                    recovered.end()
                    SportLog.event("keepalive", "discarded a dead recovered session (state \(recovered.state.rawValue))")
                }
                self.authoriseThenStart()
            }
        }

        // The recovery probe does not always call back. Two seconds, then start fresh — and the
        // generation counter stops a late callback from cancelling the session that replaced it.
        recoverGeneration &+= 1
        let generation = recoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.recoverInFlight, self.recoverGeneration == generation else { return }
            self.recoverInFlight = false
            SportLog.event("keepalive", "recoverActiveWorkoutSession did not call back in 2s — starting a fresh session")
            self.authoriseThenStart()
        }
    }

    /// Request workout-share authorisation, then read the status back rather than trusting the
    /// request's own success flag. Without the grant there is no background runtime at all, so the
    /// denial is stated in the log and in the state tag instead of surfacing later as a dead loop.
    private func authoriseThenStart() {
        if authOK { startSession(); return }
        authInFlight = true
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: share, read: []) { [weak self] ok, err in
            guard let self else { return }
            self.onMain {
                self.authInFlight = false

                let status = self.healthStore.authorizationStatus(for: HKObjectType.workoutType())
                self.authOK = (status == .sharingAuthorized)
                guard self.authOK else {
                    self.setTag("keepalive DENIED")
                    SportLog.event("keepalive", "workout share auth NOT granted (status \(status.rawValue), requestOK \(ok), err \(String(describing: err))) — background keepalive will NOT work; tap Allow on the watch")
                    return
                }

                guard !self.holders.isEmpty, self.session == nil else { return }
                self.startSession()
            }
        }
    }

    private func holderTag() -> String { holders.sorted().joined(separator: ",") }

    private func startSession() {
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .other
        cfg.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: cfg)
            s.delegate = self
            s.startActivity(with: Date())
            session = s
            setTag("keepalive running(\(holderTag()))")
            SportLog.event("keepalive", "HKWorkoutSession(.other) started — background runtime ACTIVE (holders: \(holderTag()))")
        } catch {
            session = nil

            // A failed start re-opens the recovery probe: the usual cause is a session already
            // running that we did not manage to adopt.
            recoveryProbed = false
            setTag("keepalive START-FAILED")
            SportLog.event("keepalive", "HKWorkoutSession start FAILED: \(error)")
        }
    }

    /// Ends the session outright. Background runtime stops here, so it is reached only when the
    /// last holder has gone.
    private func endSession() {
        session?.end()
        session = nil
        setTag("keepalive off")
        SportLog.event("keepalive", "session ended (no holders)")
    }

    /// Runs inline when already on main, so a caller's ordering survives.
    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState,
                        from: HKWorkoutSessionState, date: Date) {
        SportLog.event("keepalive", "state \(from.rawValue) -> \(to.rawValue)")
    }
    /// A failed session is dropped rather than retried in place: the next `acquire` or
    /// `ensureRunning` rebuilds one, which is also what a wake after a suspension does.
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        SportLog.event("keepalive", "session FAILED: \(error)")
        setTag("keepalive FAILED")
        onMain { self.session = nil }
    }
}
