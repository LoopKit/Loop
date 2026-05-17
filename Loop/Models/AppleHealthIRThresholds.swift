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
    case invalidClampRange

    var errorDescription: String? {
        switch self {
        case .invalidSleepOrdering:
            return "Sleep severe threshold must be less than mild threshold."
        case .invalidStepsOrdering:
            return "Steps thresholds must be in ascending order."
        case .invalidHRVOrdering:
            return "HRV thresholds must be in ascending order."
        case .invalidExerciseOrdering:
            return "Exercise thresholds must be in ascending order."
        case .invalidClampRange:
            return "Multiplier minimum must be less than maximum and both must be positive."
        }
    }
}

struct AppleHealthIRThresholds: Codable, Equatable {

    static let userDefaultsKey = "appleHealthIRThresholds"

    var sleepSevereThreshold: Double = 5.0
    var sleepMildThreshold: Double = 7.0
    var sleepSevereEffect: Double = 20.0
    var sleepMildEffect: Double = 0.0

    var stepsLowMin: Double = 2000
    var stepsMediumMin: Double = 5000
    var stepsHighMin: Double = 10000
    var stepsLowEffect: Double = -3.0
    var stepsMediumEffect: Double = -5.0
    var stepsHighEffect: Double = -8.0

    var hrvVeryLowMax: Double = 20.0
    var hrvLowMax: Double = 40.0
    var hrvNormalMax: Double = 60.0
    var hrvVeryLowEffect: Double = 15.0
    var hrvLowEffect: Double = 8.0
    var hrvNormalEffect: Double = 0.0
    var hrvHighEffect: Double = -5.0

    var exerciseMinThreshold: Double = 20.0
    var exerciseModerateMax: Double = 60.0
    var exerciseSubstantialMax: Double = 120.0
    var exerciseModerateEffect: Double = -5.0
    var exerciseSubstantialEffect: Double = -10.0
    var exerciseHeavyEffect: Double = -15.0

    var multiplierMin: Double = 0.5
    var multiplierMax: Double = 2.0

    static let `default` = AppleHealthIRThresholds()

    func validate() throws {
        guard sleepSevereThreshold < sleepMildThreshold else {
            throw AppleHealthIRThresholdsError.invalidSleepOrdering
        }
        guard stepsLowMin < stepsMediumMin && stepsMediumMin < stepsHighMin else {
            throw AppleHealthIRThresholdsError.invalidStepsOrdering
        }
        guard hrvVeryLowMax < hrvLowMax && hrvLowMax < hrvNormalMax else {
            throw AppleHealthIRThresholdsError.invalidHRVOrdering
        }
        guard exerciseMinThreshold < exerciseModerateMax && exerciseModerateMax < exerciseSubstantialMax else {
            throw AppleHealthIRThresholdsError.invalidExerciseOrdering
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
