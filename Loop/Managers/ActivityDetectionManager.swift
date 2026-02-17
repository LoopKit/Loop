//
//  ActivityDetectionManager.swift
//  Loop
//
//  Created for Loop AutoPresets Feature
//

import CoreMotion
import Foundation
import os.log

// MARK: - Internal Delegate Protocol

/// Internal protocol for activity detection callbacks
protocol ActivityDetectionDelegate: AnyObject {
    func activityDetectionDidConfirm(_ activity: AutoPresetActivityType)
    func activityDetectionDidStop(_ activity: AutoPresetActivityType)
    func activityDetectionDidEncounterError(_ error: AutoPresetDetectionError)
}

// MARK: - Activity Detection Manager

/// Manages CoreMotion-based activity detection for auto-preset activation.
///
/// Detection flow (pedometer-first):
/// 1. Pedometer live updates count steps continuously
/// 2. When 20+ steps accumulate → start Continuous Activity Time timer
/// 3. Activity classifier determines type (walking vs running) for preset selection
/// 4. When timer fires → query pedometer for additional steps since threshold
/// 5. If steps still accumulating → confirm activity and notify delegate
class ActivityDetectionManager {

    // MARK: - Constants

    /// Number of steps required before starting the activity timer
    private let stepThreshold = 20

    // MARK: - Properties

    private let log = OSLog(subsystem: "com.loopkit.Loop.AutoPresets", category: "ActivityDetection")
    private let fileLog = AutoPresetsLogger.shared
    private let stateQueue = DispatchQueue(label: "com.loopkit.AutoPresets.ActivityDetection.state", qos: .utility)

    weak var delegate: ActivityDetectionDelegate?

    private let pedometer = CMPedometer()
    private let motionActivityManager = CMMotionActivityManager()

    // Thread-safe state variables
    private var _isMonitoring = false
    private var _currentActivity: AutoPresetActivityType?
    private var _detectedActivityType: AutoPresetActivityType?
    private var _stepThresholdReachedTime: Date?
    private var _pedometerStartTime: Date?
    private var _totalSteps: Int = 0
    private var _lastStepChangeTime: Date?
    private var _lastClassifierTime: Date?

    private var isMonitoring: Bool {
        get { stateQueue.sync { _isMonitoring } }
        set { stateQueue.sync { _isMonitoring = newValue } }
    }

    private var currentActivity: AutoPresetActivityType? {
        get { stateQueue.sync { _currentActivity } }
        set { stateQueue.sync { _currentActivity = newValue } }
    }

    // MARK: - Configuration

    var supportedActivities: Set<AutoPresetActivityType> = [.walking]
    var activityStopInterval: TimeInterval = 300
    var continuousActivityTime: TimeInterval = 30
    var requireHighConfidence: Bool = false

    // Thread-safe timer references
    private var _continuousActivityTimer: Timer?
    private var _activityStopTimer: Timer?

    // MARK: - Public Properties

    var detectedActivity: AutoPresetActivityType? {
        currentActivity
    }

    var isActivityDetected: Bool {
        currentActivity != nil
    }

    // MARK: - Initialization

    init() {
        os_log("ActivityDetectionManager initialized", log: log, type: .debug)
    }

    deinit {
        os_log("ActivityDetectionManager deinitializing", log: log, type: .debug)
        stopMonitoring()
        cleanupTimers()
    }

    // MARK: - Public Methods

    func startMonitoring() {
        guard !isMonitoring else {
            os_log("Activity detection already monitoring", log: log, type: .debug)
            return
        }

        // Check device capability
        guard CMPedometer.isStepCountingAvailable(), CMMotionActivityManager.isActivityAvailable() else {
            os_log("Motion detection not available on this device", log: log, type: .error)
            delegate?.activityDetectionDidEncounterError(.motionNotAvailable)
            return
        }

        // Check authorization status
        let authorizationStatus = CMMotionActivityManager.authorizationStatus()
        switch authorizationStatus {
        case .notDetermined:
            break
        case .denied, .restricted:
            os_log("Motion & Fitness permission denied or restricted", log: log, type: .error)
            delegate?.activityDetectionDidEncounterError(.permissionDenied)
            return
        case .authorized:
            break
        @unknown default:
            os_log("Unknown motion authorization status", log: log, type: .error)
            delegate?.activityDetectionDidEncounterError(.permissionDenied)
            return
        }

        isMonitoring = true
        startPedometerUpdates()
        startMotionActivityUpdates()

        os_log(
            "Started activity detection - supported: %{public}@, continuous activity time: %.0fs, stop delay: %.0fs",
            log: log,
            type: .info,
            supportedActivities.map(\.displayName).joined(separator: ", "),
            continuousActivityTime,
            activityStopInterval
        )
        fileLog.log("Started monitoring - continuousActivityTime: \(continuousActivityTime)s, stopInterval: \(activityStopInterval)s")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        pedometer.stopUpdates()
        motionActivityManager.stopActivityUpdates()
        cleanupTimers()

        if let activity = currentActivity {
            currentActivity = nil
            delegate?.activityDetectionDidStop(activity)
        }

        stateQueue.sync {
            _detectedActivityType = nil
            _stepThresholdReachedTime = nil
            _pedometerStartTime = nil
            _totalSteps = 0
            _lastStepChangeTime = nil
            _lastClassifierTime = nil
        }

        os_log("Stopped activity detection monitoring", log: log, type: .info)
    }

    // MARK: - Pedometer (Phase 1: Step Detection)

    private func startPedometerUpdates() {
        let startDate = Date()
        stateQueue.sync {
            _pedometerStartTime = startDate
            _totalSteps = 0
            _stepThresholdReachedTime = nil
            _lastStepChangeTime = nil
        }

        fileLog.log("Pedometer started from: \(startDate)")

        pedometer.startUpdates(from: startDate) { [weak self] pedometerData, error in
            guard let self = self, self.isMonitoring else { return }

            if let error = error {
                os_log("Pedometer error: %{public}@", log: self.log, type: .error, error.localizedDescription)
                self.fileLog.log("Pedometer ERROR: \(error.localizedDescription)")
                return
            }

            guard let data = pedometerData else {
                self.fileLog.log("Pedometer callback with nil data")
                return
            }

            let steps = data.numberOfSteps.intValue
            self.fileLog.log("Pedometer update: \(steps) steps")

            DispatchQueue.main.async { [weak self] in
                self?.processPedometerUpdate(totalSteps: steps)
            }
        }
    }

    private func processPedometerUpdate(totalSteps: Int) {
        fileLog.log("Processing pedometer: \(totalSteps) steps (threshold: \(stepThreshold))")

        let (shouldStartTimer, alreadyConfirmed, stepsChanged) = stateQueue.sync { () -> (Bool, Bool, Bool) in
            let previousSteps = _totalSteps
            _totalSteps = totalSteps
            let changed = totalSteps != previousSteps

            // Track when steps last changed (for recency check at confirmation)
            if changed {
                _lastStepChangeTime = Date()
            }

            // Already confirmed — only care if steps actually changed
            guard _currentActivity == nil else {
                return (false, true, changed)
            }

            // Check if we just crossed the step threshold
            if totalSteps >= stepThreshold && _stepThresholdReachedTime == nil {
                _stepThresholdReachedTime = Date()
                return (true, false, changed)
            }

            return (false, false, changed)
        }

        if alreadyConfirmed {
            // Only restart the stop timer when new steps actually come in.
            // Pedometer fires callbacks every ~2.5s even with unchanged count —
            // restarting on every callback prevents the stop timer from ever expiring.
            if stepsChanged {
                startActivityStopTimer()
            }
            return
        }

        if shouldStartTimer {
            // Determine activity type from classifier, default to walking
            let activityType = stateQueue.sync { _detectedActivityType } ?? .walking

            os_log(
                "Step threshold reached (%{public}d steps) - starting continuous activity timer (%.0fs) for %{public}@",
                log: log,
                type: .info,
                totalSteps,
                continuousActivityTime,
                activityType.displayName
            )
            fileLog.log("Step threshold reached (\(totalSteps) steps) - starting \(continuousActivityTime)s timer for \(activityType.displayName)")

            startContinuousActivityTimer(for: activityType)
        }
    }

    // MARK: - Activity Classifier (determines walking vs running)

    private func startMotionActivityUpdates() {
        let queue = OperationQueue()
        queue.name = "AutoPresetsActivityClassifierQueue"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1

        motionActivityManager.startActivityUpdates(to: queue) { [weak self] activity in
            guard let self = self, self.isMonitoring else { return }
            guard let activity = activity else { return }

            // Filter stale updates
            guard Date().timeIntervalSince(activity.startDate) < 300 else { return }

            // Check confidence
            let acceptable: Bool
            if self.requireHighConfidence {
                acceptable = activity.confidence == .high
            } else {
                acceptable = activity.confidence == .high || activity.confidence == .medium
            }
            guard acceptable else { return }

            // Determine activity type
            var type: AutoPresetActivityType?
            if self.supportedActivities.contains(.walking), activity.walking,
               !activity.automotive, !activity.cycling
            {
                type = .walking
            } else if self.supportedActivities.contains(.running), activity.running,
                      !activity.automotive, !activity.cycling
            {
                type = .running
            }

            if let type = type {
                self.stateQueue.sync {
                    self._detectedActivityType = type
                    self._lastClassifierTime = Date()
                }
            } else {
                // Non-target activity detected — may need to trigger stop
                let shouldStop = activity.confidence != .low &&
                    (activity.automotive || activity.cycling)

                if shouldStop {
                    DispatchQueue.main.async { [weak self] in
                        self?.handleNonTargetActivity()
                    }
                }
            }
        }
    }

    private func handleNonTargetActivity() {
        let shouldStartStopTimer = stateQueue.sync { () -> Bool in
            _currentActivity != nil && _activityStopTimer == nil
        }

        if shouldStartStopTimer {
            os_log("Non-target activity detected (automotive/cycling), starting stop timer", log: log, type: .debug)
            startActivityStopTimer()
        }
    }

    // MARK: - Continuous Activity Timer (Phase 2: Sustained Activity Check)

    private func startContinuousActivityTimer(for activity: AutoPresetActivityType) {
        os_log(
            "Starting continuous activity timer with interval: %.0fs (setting value: %.0fs)",
            log: log,
            type: .debug,
            continuousActivityTime,
            continuousActivityTime
        )
        fileLog.log("Timer created with interval: \(continuousActivityTime)s")

        stateQueue.sync {
            _continuousActivityTimer?.invalidate()
            _continuousActivityTimer = nil
        }

        let stepsAtThreshold = stateQueue.sync { _totalSteps }
        let timerInterval = continuousActivityTime  // Capture the value
        let timerStartTime = Date()

        let newTimer = Timer(timeInterval: timerInterval, repeats: false) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(timerStartTime)
            os_log(
                "Continuous activity timer fired - expected: %.0fs, actual elapsed: %.1fs",
                log: self.log,
                type: .debug,
                timerInterval,
                elapsed
            )
            self.fileLog.log("Timer FIRED - expected: \(timerInterval)s, actual elapsed: \(String(format: "%.1f", elapsed))s")

            guard self.isMonitoring else {
                timer.invalidate()
                return
            }

            // Check if steps increased since the threshold was reached
            let (currentSteps, thresholdTime, lastStepTime, classifierType, classifierTime) = self.stateQueue.sync { () -> (Int, Date?, Date?, AutoPresetActivityType?, Date?) in
                return (self._totalSteps, self._stepThresholdReachedTime, self._lastStepChangeTime, self._detectedActivityType, self._lastClassifierTime)
            }

            let additionalSteps = currentSteps - stepsAtThreshold

            // Require a walking pace of at least 30 steps/minute based on
            // ACTUAL elapsed time (not configured interval). iOS often delays
            // timers when backgrounded, so actual elapsed can be 2-3x longer.
            // Using actual elapsed prevents casual household steps from passing
            // during extended timer delays.
            // For 120s actual: need 60. For 293s actual: need 146.
            let minAdditionalSteps = max(15, Int(elapsed / 60.0 * 30.0))

            // Recency check: user must have been walking recently.
            // Base limit: 30s — if the timer fires on time, user must still be
            // actively stepping. But iOS often backgrounds the app, delaying the
            // timer by 2-5x. A 60s timer can fire at 293s. The user may have
            // walked for 3 minutes (exceeding CAT) but stopped before the delayed
            // timer fires. Adding the timer delay to the recency limit ensures
            // the user isn't penalized for iOS backgrounding delays.
            let timerDelay = max(0, elapsed - timerInterval)
            let stepRecencyLimit: TimeInterval = 30 + timerDelay
            let now = Date()
            let stepIsRecent: Bool
            if let lastStep = lastStepTime {
                let sinceLast = now.timeIntervalSince(lastStep)
                stepIsRecent = sinceLast <= stepRecencyLimit
                self.fileLog.log("Recency check: last step change \(String(format: "%.1f", sinceLast))s ago (limit: \(String(format: "%.0f", stepRecencyLimit))s = 30s base + \(String(format: "%.0f", timerDelay))s timer delay) → \(stepIsRecent ? "PASS" : "FAIL")")
            } else {
                stepIsRecent = false
                self.fileLog.log("Recency check: no step changes recorded → FAIL")
            }

            // Classifier check: when Require High Confidence is ON, CoreMotion's
            // activity classifier must have recently confirmed the activity type
            // (at high confidence only). This prevents step-count-only confirmation
            // when the device isn't confident the user is actually walking/running.
            let classifierConfirmed: Bool
            if self.requireHighConfidence {
                let classifierRecencyLimit: TimeInterval = 60
                if let cType = classifierType, let cTime = classifierTime {
                    let sinceClassifier = now.timeIntervalSince(cTime)
                    classifierConfirmed = sinceClassifier <= classifierRecencyLimit
                    self.fileLog.log("Classifier check (high confidence required): \(cType.displayName) confirmed \(String(format: "%.1f", sinceClassifier))s ago (limit: \(classifierRecencyLimit)s) → \(classifierConfirmed ? "PASS" : "FAIL")")
                } else {
                    classifierConfirmed = false
                    self.fileLog.log("Classifier check (high confidence required): no classifier data → FAIL")
                }
            } else {
                classifierConfirmed = true // not required when toggle is off
            }

            if additionalSteps >= minAdditionalSteps && stepIsRecent && classifierConfirmed {
                // Steps are accumulating at a walking pace — confirm the activity
                let activityType = classifierType ?? activity

                os_log(
                    "%{public}@ confirmed after %.1fs - %{public}d total steps (%{public}d additional since threshold)",
                    log: self.log,
                    type: .info,
                    activityType.displayName,
                    elapsed,
                    currentSteps,
                    additionalSteps
                )
                self.fileLog.log("CONFIRMED \(activityType.displayName) after \(String(format: "%.1f", elapsed))s - \(currentSteps) total steps (\(additionalSteps) additional)")

                self.stateQueue.sync {
                    self._currentActivity = activityType
                    self._continuousActivityTimer = nil
                }
                self.delegate?.activityDetectionDidConfirm(activityType)

                // Start the stop timer - will fire if no more steps come in
                self.startActivityStopTimer()
            } else {
                // Not enough additional steps, user stopped, or classifier didn't confirm
                let reason: String
                if !stepIsRecent {
                    reason = "user stopped walking before timer fired"
                } else if !classifierConfirmed {
                    reason = "CoreMotion classifier did not confirm activity at high confidence"
                } else {
                    reason = "only \(additionalSteps) additional steps (need >= \(minAdditionalSteps))"
                }
                os_log(
                    "%{public}@ confirmation failed - %{public}@",
                    log: self.log,
                    type: .debug,
                    activity.displayName,
                    reason
                )
                self.fileLog.log("REJECTED \(activity.displayName) - \(reason) in \(String(format: "%.0f", elapsed))s")

                self.stateQueue.sync {
                    self._stepThresholdReachedTime = nil
                    self._continuousActivityTimer = nil
                }

                // Reset pedometer to start fresh
                self.resetPedometer()
            }

            timer.invalidate()
        }

        stateQueue.sync {
            _continuousActivityTimer = newTimer
        }
        RunLoop.main.add(newTimer, forMode: .common)
    }

    // MARK: - Stop Detection

    private func startActivityStopTimer() {
        stateQueue.sync {
            _activityStopTimer?.invalidate()
            _activityStopTimer = nil
        }

        let newTimer = Timer(timeInterval: activityStopInterval, repeats: false) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            guard self.isMonitoring else {
                timer.invalidate()
                return
            }

            // This timer only fires after activityStopInterval seconds of no step changes,
            // because every step change restarts it (see processPedometerUpdate).
            // If we get here, the user has stopped walking.
            let activityToStop = self.stateQueue.sync { () -> AutoPresetActivityType? in
                let activity = self._currentActivity
                self._currentActivity = nil
                self._stepThresholdReachedTime = nil
                self._activityStopTimer = nil
                return activity
            }

            if let activity = activityToStop {
                self.delegate?.activityDetectionDidStop(activity)
                os_log(
                    "%{public}@ stopped after %.0fs of inactivity",
                    log: self.log,
                    type: .info,
                    activity.displayName,
                    self.activityStopInterval
                )
                self.fileLog.log("DEACTIVATED \(activity.displayName) after \(self.activityStopInterval)s of no steps")
            }

            // Reset pedometer for next detection cycle
            self.resetPedometer()

            timer.invalidate()
        }

        stateQueue.sync {
            _activityStopTimer = newTimer
        }
        RunLoop.main.add(newTimer, forMode: .common)
    }

    // MARK: - Helpers

    private func cleanupTimers() {
        stateQueue.sync {
            _continuousActivityTimer?.invalidate()
            _continuousActivityTimer = nil
            _activityStopTimer?.invalidate()
            _activityStopTimer = nil
        }
    }

    private func resetPedometer() {
        pedometer.stopUpdates()

        stateQueue.sync {
            _totalSteps = 0
            _stepThresholdReachedTime = nil
            _pedometerStartTime = nil
            _lastStepChangeTime = nil
        }

        // Restart pedometer for next detection cycle
        if isMonitoring {
            startPedometerUpdates()
        }
    }
}
