//
//  HealthAccessView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI

/// Shows the app's Apple Health access for glucose, insulin, and carbohydrates.
///
/// HealthKit only exposes *sharing* (write) authorization, so this screen can show
/// write status definitively. Read authorization is intentionally hidden by the system
/// for privacy and cannot be displayed — the screen explains that and points the user at
/// the Settings / Health apps, which are the only place permissions can be changed (the
/// app cannot re-prompt once the user has responded).
struct HealthAccessView: View {

    @Environment(\.appName) private var appName

    /// Closures so status is re-read each time the screen appears (e.g. after the user
    /// returns from the Settings app having changed a permission).
    let glucoseSharingStatus: () -> HKAuthorizationStatus
    let insulinSharingStatus: () -> HKAuthorizationStatus
    let carbSharingStatus: () -> HKAuthorizationStatus
    var exerciseDataSharing: ExerciseDataSharing?

    @State private var glucoseStatus: HKAuthorizationStatus = .notDetermined
    @State private var insulinStatus: HKAuthorizationStatus = .notDetermined
    @State private var carbStatus: HKAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section {
                statusRow(label: NSLocalizedString("Glucose", comment: "Health access row label for glucose"), status: glucoseStatus)
                statusRow(label: NSLocalizedString("Insulin", comment: "Health access row label for insulin"), status: insulinStatus)
                statusRow(label: NSLocalizedString("Carbohydrates", comment: "Health access row label for carbohydrates"), status: carbStatus)
            } header: {
                Text("Sharing to Apple Health", comment: "Health access section header for write access")
            } footer: {
                Text(String(format: NSLocalizedString("Whether %1$@ is allowed to save glucose, insulin, and carbohydrate data to Apple Health.", comment: "Health access write section footer (1: app name)"), appName))
            }

            Section {
                Text(String(format: NSLocalizedString("%1$@ also reads insulin data from other apps in Apple Health. Apple Health does not report whether an app may read data, so read access can't be shown here.", comment: "Health access reading explanation (1: app name)"), appName))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(String(format: NSLocalizedString("Once you have allowed or denied a data type, %1$@ cannot ask again from within the app. To review or change access, open the Health app, tap your profile, then Apps → %1$@.", comment: "Health access change instructions (1: app name)"), appName))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Reading & Changing Access", comment: "Health access section header for reading and changing access")
            }

            if let exerciseDataSharing {
                exerciseSection(exerciseDataSharing)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Apple Health", comment: "Title of the Apple Health access screen"))
        .onAppear(perform: refresh)
    }

    private func refresh() {
        glucoseStatus = glucoseSharingStatus()
        insulinStatus = insulinSharingStatus()
        carbStatus = carbSharingStatus()
    }

    private func exerciseSection(_ sharing: ExerciseDataSharing) -> some View {
        Section {
            Toggle(
                NSLocalizedString("Share Exercise Data", comment: "Health access toggle for sharing workouts with services"),
                isOn: Binding(get: { sharing.isEnabled }, set: { newValue in Task { await sharing.setEnabled(newValue) } })
            )
        } header: {
            Text("Exercise", comment: "Health access section header for exercise data")
        } footer: {
            Text(String(format: NSLocalizedString("When on, %1$@ reads your workouts from Apple Health, along with heart rate throughout the day, resting heart rate, heart rate variability, VO2 max, steps, active energy, physical effort and weight, and uploads them to your connected services. Tidepool currently receives workouts only. If you donate your Tidepool data to research, these workouts are included. Exercise data does not change dosing.", comment: "Health access exercise sharing footer (1: app name)"), appName))
        }
    }

    private func statusRow(label: String, status: HKAuthorizationStatus) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: status.iconSystemName)
                .foregroundStyle(status.tintColor)
            Text(status.localizedDescription)
                .foregroundStyle(.secondary)
        }
    }
}

private extension HKAuthorizationStatus {
    var localizedDescription: String {
        switch self {
        case .sharingAuthorized:
            return NSLocalizedString("Allowed", comment: "Health sharing status: authorized")
        case .sharingDenied:
            return NSLocalizedString("Denied", comment: "Health sharing status: denied")
        case .notDetermined:
            return NSLocalizedString("Not Set", comment: "Health sharing status: not determined")
        @unknown default:
            return NSLocalizedString("Unknown", comment: "Health sharing status: unknown")
        }
    }

    var iconSystemName: String {
        switch self {
        case .sharingAuthorized: return "checkmark.circle.fill"
        case .sharingDenied: return "xmark.circle.fill"
        case .notDetermined: return "circle"
        @unknown default: return "questionmark.circle"
        }
    }

    var tintColor: Color {
        switch self {
        case .sharingAuthorized: return .green
        case .sharingDenied: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }
}
