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
        exerciseMinutes: Double?,
        heartRate: Double?
    ) -> Double
    func updateBiometrics(
        sleepHours: Double?,
        stepCount: Double?,
        hrvSDNN: Double?,
        exerciseMinutes: Double?,
        heartRate: Double?
    )
}

extension AppleHealthIRServiceProtocol {
    func computeMultiplier(sleepHours: Double?, stepCount: Double?,
                           hrvSDNN: Double?, exerciseMinutes: Double?) -> Double {
        computeMultiplier(sleepHours: sleepHours, stepCount: stepCount,
                          hrvSDNN: hrvSDNN, exerciseMinutes: exerciseMinutes, heartRate: nil)
    }
    func updateBiometrics(sleepHours: Double?, stepCount: Double?,
                          hrvSDNN: Double?, exerciseMinutes: Double?) {
        updateBiometrics(sleepHours: sleepHours, stepCount: stepCount,
                         hrvSDNN: hrvSDNN, exerciseMinutes: exerciseMinutes, heartRate: nil)
    }
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
        exerciseMinutes: Double?,
        heartRate: Double?
    ) -> Double {
        let sd = sleepDelta(hours: sleepHours)
        let stpd = stepsDelta(count: stepCount)
        let hd = hrvDelta(sdnn: hrvSDNN)
        let ed = exerciseDelta(minutes: exerciseMinutes)
        let rd = rhrDelta(bpm: heartRate)
        let combined = sd + stpd + hd + ed + rd
        let raw = 1.0 + combined / 100.0
        return clamp(raw)
    }

    func updateBiometrics(
        sleepHours: Double?,
        stepCount: Double?,
        hrvSDNN: Double?,
        exerciseMinutes: Double?,
        heartRate: Double?
    ) {
        let sd = sleepDelta(hours: sleepHours)
        let stpd = stepsDelta(count: stepCount)
        let hd = hrvDelta(sdnn: hrvSDNN)
        let ed = exerciseDelta(minutes: exerciseMinutes)
        let rd = rhrDelta(bpm: heartRate)
        let combined = sd + stpd + hd + ed + rd
        let raw = 1.0 + combined / 100.0
        let multiplier = clamp(raw)

        let entry = AppleHealthIREntry(
            id: UUID(),
            timestamp: Date(),
            sleepHours: sleepHours,
            stepCount: stepCount,
            hrvSDNN: hrvSDNN,
            exerciseMinutes: exerciseMinutes,
            heartRate: heartRate,
            sleepDelta: sd,
            stepsDelta: stpd,
            hrvDelta: hd,
            exerciseDelta: ed,
            rhrDelta: rd,
            combinedDelta: combined,
            multiplier: multiplier,
            thresholdsSnapshot: thresholds
        )
        AppleHealthIREntry.append(entry)
        latestEntry = entry
        multiplierSubject.send(multiplier)
    }

    // MARK: - Private delta calculators
    // Each uses 5-zone logic: if < T1 → E1; elif < T2 → E2; elif < T3 → E3; elif < T4 → E4; else → 0.0

    private func sleepDelta(hours: Double?) -> Double {
        guard let hours = hours else { return 0.0 }
        let t = thresholds
        if hours < t.sleepT1 { return t.sleepE1 }
        if hours < t.sleepT2 { return t.sleepE2 }
        if hours < t.sleepT3 { return t.sleepE3 }
        if hours < t.sleepT4 { return t.sleepE4 }
        return 0.0
    }

    private func stepsDelta(count: Double?) -> Double {
        guard let count = count else { return 0.0 }
        let t = thresholds
        if count < t.stepsT1 { return t.stepsE1 }
        if count < t.stepsT2 { return t.stepsE2 }
        if count < t.stepsT3 { return t.stepsE3 }
        if count < t.stepsT4 { return t.stepsE4 }
        return 0.0
    }

    private func hrvDelta(sdnn: Double?) -> Double {
        guard let sdnn = sdnn else { return 0.0 }
        let t = thresholds
        if sdnn < t.hrvT1 { return t.hrvE1 }
        if sdnn < t.hrvT2 { return t.hrvE2 }
        if sdnn < t.hrvT3 { return t.hrvE3 }
        if sdnn < t.hrvT4 { return t.hrvE4 }
        return 0.0
    }

    private func exerciseDelta(minutes: Double?) -> Double {
        guard let minutes = minutes else { return 0.0 }
        let t = thresholds
        if minutes < t.exerciseT1 { return t.exerciseE1 }
        if minutes < t.exerciseT2 { return t.exerciseE2 }
        if minutes < t.exerciseT3 { return t.exerciseE3 }
        if minutes < t.exerciseT4 { return t.exerciseE4 }
        return 0.0
    }

    private func rhrDelta(bpm: Double?) -> Double {
        guard let bpm = bpm else { return 0.0 }
        let t = thresholds
        if bpm < t.rhrT1 { return 0.0 }
        if bpm < t.rhrT2 { return t.rhrE1 }
        if bpm < t.rhrT3 { return t.rhrE2 }
        if bpm < t.rhrT4 { return t.rhrE3 }
        return t.rhrE4
    }

    private func clamp(_ value: Double) -> Double {
        min(thresholds.multiplierMax, max(thresholds.multiplierMin, value))
    }
}
