//
//  AppleHealthIRThresholds.swift
//  Loop
//

import Foundation

enum AppleHealthIRThresholdsError: LocalizedError {
    case invalidSleepOrdering
    case invalidStepsOrdering
    case invalidHRVOrdering
    case invalidExerciseOrdering
    case invalidRHROrdering
    case invalidClampRange

    var errorDescription: String? {
        switch self {
        case .invalidSleepOrdering:
            return "Sleep thresholds must be in ascending order (T1 < T2 < T3 < T4)."
        case .invalidStepsOrdering:
            return "Steps thresholds must be in ascending order (T1 < T2 < T3 < T4)."
        case .invalidHRVOrdering:
            return "HRV thresholds must be in ascending order (T1 < T2 < T3 < T4)."
        case .invalidExerciseOrdering:
            return "Exercise thresholds must be in ascending order (T1 < T2 < T3 < T4)."
        case .invalidRHROrdering:
            return "RHR thresholds must be in ascending order (T1 < T2 < T3 < T4)."
        case .invalidClampRange:
            return "Multiplier minimum must be less than maximum and both must be positive."
        }
    }
}

struct AppleHealthIRThresholds: Codable, Equatable {

    static let userDefaultsKey = "appleHealthIRThresholds"

    // MARK: - Sleep (hours)
    // Zone logic: < T1 → E1; < T2 → E2; < T3 → E3; < T4 → E4; else → 0
    var sleepT1: Double = 4.0
    var sleepT2: Double = 5.5
    var sleepT3: Double = 6.5
    var sleepT4: Double = 7.5
    var sleepE1: Double = 30.0
    var sleepE2: Double = 20.0
    var sleepE3: Double = 10.0
    var sleepE4: Double = 5.0

    // MARK: - Steps (count)
    // Zone logic: < T1 → E1; < T2 → E2; < T3 → E3; < T4 → E4; else → 0
    var stepsT1: Double = 2000
    var stepsT2: Double = 5000
    var stepsT3: Double = 8000
    var stepsT4: Double = 12000
    var stepsE1: Double = 5.0
    var stepsE2: Double = 0.0
    var stepsE3: Double = -3.0
    var stepsE4: Double = -6.0

    // MARK: - HRV SDNN (ms)
    // Zone logic: < T1 → E1; < T2 → E2; < T3 → E3; < T4 → E4; else → 0
    var hrvT1: Double = 20.0
    var hrvT2: Double = 35.0
    var hrvT3: Double = 50.0
    var hrvT4: Double = 70.0
    var hrvE1: Double = 20.0
    var hrvE2: Double = 10.0
    var hrvE3: Double = 5.0
    var hrvE4: Double = 0.0

    // MARK: - Exercise (minutes)
    // Zone logic: < T1 → E1; < T2 → E2; < T3 → E3; < T4 → E4; else → 0
    var exerciseT1: Double = 10.0
    var exerciseT2: Double = 30.0
    var exerciseT3: Double = 60.0
    var exerciseT4: Double = 120.0
    var exerciseE1: Double = 5.0
    var exerciseE2: Double = -3.0
    var exerciseE3: Double = -8.0
    var exerciseE4: Double = -12.0

    // MARK: - RHR (bpm)
    // Zone logic: < T1 → 0; < T2 → E1; < T3 → E2; < T4 → E3; ≥ T4 → E4
    var rhrT1: Double = 50.0
    var rhrT2: Double = 65.0
    var rhrT3: Double = 75.0
    var rhrT4: Double = 85.0
    var rhrE1: Double = -2.0
    var rhrE2: Double = 0.0
    var rhrE3: Double = 5.0
    var rhrE4: Double = 10.0

    // MARK: - Multiplier clamp
    var multiplierMin: Double = 0.5
    var multiplierMax: Double = 2.0

    static let `default` = AppleHealthIRThresholds()

    func validate() throws {
        guard sleepT1 < sleepT2 && sleepT2 < sleepT3 && sleepT3 < sleepT4 else {
            throw AppleHealthIRThresholdsError.invalidSleepOrdering
        }
        guard stepsT1 < stepsT2 && stepsT2 < stepsT3 && stepsT3 < stepsT4 else {
            throw AppleHealthIRThresholdsError.invalidStepsOrdering
        }
        guard hrvT1 < hrvT2 && hrvT2 < hrvT3 && hrvT3 < hrvT4 else {
            throw AppleHealthIRThresholdsError.invalidHRVOrdering
        }
        guard exerciseT1 < exerciseT2 && exerciseT2 < exerciseT3 && exerciseT3 < exerciseT4 else {
            throw AppleHealthIRThresholdsError.invalidExerciseOrdering
        }
        guard rhrT1 < rhrT2 && rhrT2 < rhrT3 && rhrT3 < rhrT4 else {
            throw AppleHealthIRThresholdsError.invalidRHROrdering
        }
        guard multiplierMin > 0 && multiplierMin < multiplierMax else {
            throw AppleHealthIRThresholdsError.invalidClampRange
        }
    }

    mutating func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    static func load() -> AppleHealthIRThresholds {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(AppleHealthIRThresholds.self, from: data)
        else {
            return .default
        }
        return decoded
    }
}
