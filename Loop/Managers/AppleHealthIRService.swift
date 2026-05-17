//
//  AppleHealthIRService.swift
//  Loop
//

import Foundation
import Combine

protocol AppleHealthIRServiceProtocol: AnyObject {
    var multiplierPublisher: AnyPublisher<Double, Never> { get }
    var currentMultiplier: Double { get }
    var latestEntry: AppleHealthIREntry? { get }
    var thresholds: AppleHealthIRThresholds { get set }
    func computeMultiplier(
        sleepHours: Double?,
        stepCount: Double?,
        hrvSDNN: Double?,
        exerciseMinutes: Double?
    ) -> Double
    func updateBiometrics(
        sleepHours: Double?,
        stepCount: Double?,
        hrvSDNN: Double?,
        exerciseMinutes: Double?
    )
}

final class AppleHealthIRService: AppleHealthIRServiceProtocol {

    var thresholds: AppleHealthIRThresholds
    private(set) var latestEntry: AppleHealthIREntry?
    private let multiplierSubject: CurrentValueSubject<Double, Never>

    var multiplierPublisher: AnyPublisher<Double, Never> {
        multiplierSubject.eraseToAnyPublisher()
    }

    var currentMultiplier: Double {
        multiplierSubject.value
    }

    init(thresholds: AppleHealthIRThresholds = .load()) {
        self.thresholds = thresholds
        self.multiplierSubject = CurrentValueSubject(1.0)
    }

    func computeMultiplier(
        sleepHours: Double?,
        stepCount: Double?,
        hrvSDNN: Double?,
        exerciseMinutes: Double?
    ) -> Double {
        let sd = sleepDelta(hours: sleepHours)
        let stpd = stepsDelta(count: stepCount)
        let hd = hrvDelta(sdnn: hrvSDNN)
        let ed = exerciseDelta(minutes: exerciseMinutes)
        let combined = sd + stpd + hd + ed
        let raw = 1.0 + combined / 100.0
        return clamp(raw)
    }

    func updateBiometrics(
        sleepHours: Double?,
        stepCount: Double?,
        hrvSDNN: Double?,
        exerciseMinutes: Double?
    ) {
        let sd = sleepDelta(hours: sleepHours)
        let stpd = stepsDelta(count: stepCount)
        let hd = hrvDelta(sdnn: hrvSDNN)
        let ed = exerciseDelta(minutes: exerciseMinutes)
        let combined = sd + stpd + hd + ed
        let raw = 1.0 + combined / 100.0
        let multiplier = clamp(raw)

        let entry = AppleHealthIREntry(
            id: UUID(),
            timestamp: Date(),
            sleepHours: sleepHours,
            stepCount: stepCount,
            hrvSDNN: hrvSDNN,
            exerciseMinutes: exerciseMinutes,
            sleepDelta: sd,
            stepsDelta: stpd,
            hrvDelta: hd,
            exerciseDelta: ed,
            combinedDelta: combined,
            multiplier: multiplier,
            thresholdsSnapshot: thresholds
        )
        AppleHealthIREntry.append(entry)
        latestEntry = entry
        multiplierSubject.send(multiplier)
    }

    // MARK: - Private delta calculators

    private func sleepDelta(hours: Double?) -> Double {
        guard let hours = hours else { return 0.0 }
        let t = thresholds
        if hours >= t.sleepMildThreshold {
            return t.sleepMildEffect
        }
        if hours <= t.sleepSevereThreshold {
            return t.sleepSevereEffect
        }
        // Guard against equal thresholds producing divide-by-zero (safety invariant)
        guard t.sleepMildThreshold != t.sleepSevereThreshold else { return t.sleepSevereEffect }
        return linearInterpolate(
            value: hours,
            low: t.sleepSevereThreshold,
            high: t.sleepMildThreshold,
            lowEffect: t.sleepSevereEffect,
            highEffect: t.sleepMildEffect
        )
    }

    private func stepsDelta(count: Double?) -> Double {
        guard let count = count else { return 0.0 }
        let t = thresholds
        if count < t.stepsLowMin { return 0.0 }
        if count >= t.stepsHighMin { return t.stepsHighEffect }
        if count >= t.stepsMediumMin { return t.stepsMediumEffect }
        return t.stepsLowEffect
    }

    private func hrvDelta(sdnn: Double?) -> Double {
        guard let sdnn = sdnn else { return 0.0 }
        let t = thresholds
        if sdnn <= t.hrvVeryLowMax { return t.hrvVeryLowEffect }
        if sdnn <= t.hrvLowMax { return t.hrvLowEffect }
        if sdnn <= t.hrvNormalMax { return t.hrvNormalEffect }
        return t.hrvHighEffect
    }

    private func exerciseDelta(minutes: Double?) -> Double {
        guard let minutes = minutes else { return 0.0 }
        let t = thresholds
        if minutes < t.exerciseMinThreshold { return 0.0 }
        if minutes >= t.exerciseSubstantialMax { return t.exerciseHeavyEffect }
        if minutes >= t.exerciseModerateMax { return t.exerciseSubstantialEffect }
        return t.exerciseModerateEffect
    }

    private func clamp(_ value: Double) -> Double {
        min(thresholds.multiplierMax, max(thresholds.multiplierMin, value))
    }

    private func linearInterpolate(
        value: Double,
        low: Double,
        high: Double,
        lowEffect: Double,
        highEffect: Double
    ) -> Double {
        // Guard checked by all callers; this is the only place interpolation occurs
        let fraction = (value - low) / (high - low)
        return lowEffect + fraction * (highEffect - lowEffect)
    }
}
