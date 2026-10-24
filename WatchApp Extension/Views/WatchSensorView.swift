//
//  WatchSensorView.swift
//  WatchApp Extension
//
//  The CGM the watch reads itself: what it needs from the user, and its last reading and connection.
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopCore

struct WatchSensorView: View {
    @Environment(LoopDataManager.self) var loopManager

    private var host: WatchCGMHost { WatchCGMHost.shared }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                Text(host.sensorName ?? String(localized: "Sensor", comment: "Title of the watch's sensor page when the sensor has no name yet"))
                    .font(.headline)

                if let note = host.statusNote {
                    Text(note)
                        .font(.footnote)
                }

                LabelValueRow("Last Reading") {
                    if let reading = loopManager.latestDirectGlucose {
                        Text(glucoseText(reading)) + Text(" ") + Text(reading.date, style: .time).font(.footnote)
                    } else {
                        Text("—")
                    }
                }

                LabelValueRow("Next Reading") {
                    if let lastConnection = host.lastConnection {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Self.countdown(to: Self.nextReading(after: lastConnection, now: context.date), now: context.date))
                                .monospacedDigit()
                        }
                    } else {
                        Text("—")
                    }
                }

                LabelValueRow("Last Connection") {
                    if let date = host.lastConnection {
                        Text(date, style: .time)
                    } else {
                        Text("—")
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    /// The sensor's 5-minute cadence, counted from the last link-up, which comes a few seconds into a window.
    static let readingInterval: TimeInterval = 5 * 60

    static func nextReading(after lastConnection: Date, now: Date) -> Date {
        let elapsed = max(0, now.timeIntervalSince(lastConnection))
        return lastConnection.addingTimeInterval((floor(elapsed / readingInterval) + 1) * readingInterval)
    }

    static func countdown(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func glucoseText(_ reading: NewGlucoseSample) -> String {
        let unit = loopManager.displayGlucoseUnit
        let value = NumberFormatter.glucoseFormatter(for: unit).string(from: reading.quantity.doubleValue(for: unit)) ?? ""
        return value + (reading.trend?.symbol ?? "")
    }
}
