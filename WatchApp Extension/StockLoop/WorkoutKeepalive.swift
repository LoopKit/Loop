// WorkoutKeepalive.swift — background runtime for the watch loop.
//
// watchOS suspends a backgrounded app within seconds; an HKWorkoutSession is the only
// self-service way to keep the process and its BLE links alive. Holds are refcounted by reason
// ("takeover", "handback"). Owned by StockLoopSession.
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

    // Entry points run on main; these two are lock-guarded for the heartbeat's reads.
    private let tagLock = NSLock()
    private var _tag = "keepalive off"

    var stateTag: String { tagLock.lock(); defer { tagLock.unlock() }; return _tag }
    private func setTag(_ s: String) { tagLock.lock(); _tag = s; tagLock.unlock() }

    override init() {
        super.init()
        RuntimeStateLog.keepaliveProbe = { [weak self] in self?.stateTag ?? "keepalive ?" }
    }

    /// Take a hold under `reason`; releasing one never stops a session another still wants.
    func acquire(_ reason: String) { onMain { self.holders.insert(reason); self.startSessionIfNeeded() } }

    /// Drop this reason's hold. The session ends only when the last holder goes.
    func release(_ reason: String) { onMain { self.holders.remove(reason); if self.holders.isEmpty { self.endSession() } } }

    /// Restart a session lost while suspended, without taking a hold.
    func ensureRunning() { onMain { self.startSessionIfNeeded() } }

    /// Adopt a session that outlived a relaunch before starting one; probed once per process.
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

                // Nothing wants a session any more: end what was found.
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

        // The probe may never call back: start fresh after 2 s; the generation stops a late callback.
        recoverGeneration &+= 1
        let generation = recoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.recoverInFlight, self.recoverGeneration == generation else { return }
            self.recoverInFlight = false
            SportLog.event("keepalive", "recoverActiveWorkoutSession did not call back in 2s — starting a fresh session")
            self.authoriseThenStart()
        }
    }

    /// Reads the authorisation status back instead of trusting the request's result.
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

            // A failed start re-opens the probe: usually a session we failed to adopt.
            recoveryProbed = false
            setTag("keepalive START-FAILED")
            SportLog.event("keepalive", "HKWorkoutSession start FAILED: \(error)")
        }
    }

    /// Only when the last holder has gone.
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
    /// Dropped, not retried: the next acquire or ensureRunning rebuilds one.
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        SportLog.event("keepalive", "session FAILED: \(error)")
        setTag("keepalive FAILED")
        onMain { self.session = nil }
    }
}
