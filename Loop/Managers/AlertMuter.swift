//
//  AlertMuter.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2022-09-14.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import SwiftUI
import LoopKit

public class AlertMuter: ObservableObject {
    struct Configuration: Equatable, RawRepresentable {
        typealias RawValue = [String: Any]

        enum ConfigurationKey: String {
            case duration
            case startTime
        }

        init?(rawValue: [String : Any]) {
            guard let duration = rawValue[ConfigurationKey.duration.rawValue] as? TimeInterval
            else { return nil }

            self.duration = duration
            self.startTime = rawValue[ConfigurationKey.startTime.rawValue] as? Date
        }

        var rawValue: [String : Any] {
            var rawValue: [String : Any] = [:]
            rawValue[ConfigurationKey.duration.rawValue] = duration
            rawValue[ConfigurationKey.startTime.rawValue] = startTime
            return rawValue
        }

        var duration: TimeInterval

        var startTime: Date?

        var shouldMute: Bool {
            guard let mutingEndTime = mutingEndTime else { return false }
            return mutingEndTime >= Date()
        }

        var mutingEndTime: Date? {
            startTime?.addingTimeInterval(duration)
        }

        init(startTime: Date? = nil, duration: TimeInterval = AlertMuter.allowedDurations[0]) {
            self.duration = duration
            self.startTime = startTime
        }

        func shouldMuteAlert(scheduledAt timeFromNow: TimeInterval = 0, now: Date = Date()) -> Bool {
            guard let mutingEndTime = mutingEndTime else { return false }

            let alertTriggerTime = now.advanced(by: timeFromNow)
            guard let startTime = startTime,
                  alertTriggerTime >= startTime,
                  alertTriggerTime < mutingEndTime
            else { return false }

            return true
        }
    }

    @Published var configuration: Configuration {
        didSet {
            if oldValue != configuration {
                updateMutePeriodEndingWatcher()
            }
        }
    }

    private var mutePeriodEndingTimer: Timer?

    private lazy var cancellables = Set<AnyCancellable>()

    static var allowedDurations: [TimeInterval] { [.minutes(30), .hours(1), .hours(2), .hours(4)] }

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.updateMutePeriodEndingWatcher()
            }
            .store(in: &cancellables)

        updateMutePeriodEndingWatcher()
    }

    convenience init(startTime: Date? = nil, duration: TimeInterval = AlertMuter.allowedDurations[0]) {
        self.init(configuration: Configuration(startTime: startTime, duration: duration))
    }

    private func updateMutePeriodEndingWatcher(_ now: Date = Date()) {
        mutePeriodEndingTimer?.invalidate()

        guard let mutingEndTime = configuration.mutingEndTime else { return }

        guard mutingEndTime > now else {
            configuration.startTime = nil
            return
        }

        let timeInterval = mutingEndTime.timeIntervalSince(now)
        mutePeriodEndingTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            self?.configuration.startTime = nil
        }
    }

    func shouldMuteAlert(scheduledAt timeFromNow: TimeInterval = 0) -> Bool {
        return configuration.shouldMuteAlert(scheduledAt: timeFromNow)
    }

    func shouldMuteAlert(_ alert: LoopKit.Alert, issuedDate: Date? = nil, now: Date = Date()) -> Bool {
        switch alert.trigger {
        case .immediate:
            return shouldMuteAlert(scheduledAt: (issuedDate ?? now).timeIntervalSince(now))
        case .delayed(let interval), .repeating(let interval):
            let triggerInterval = ((issuedDate ?? now) + interval).timeIntervalSince(now)
            return shouldMuteAlert(scheduledAt: triggerInterval)
        }
    }

    func unmuteAlerts() {
        configuration.startTime = nil
    }

    var formattedEndTime: String {
        guard let endTime = configuration.mutingEndTime else { return NSLocalizedString("Unknown", comment: "result when time cannot be formatted") }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: endTime)
    }
}
