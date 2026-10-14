//
//  PresetActivateCrownConfirm.swift
//  Loop
//
//  Created by Pete Schwamb on 9/23/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopCore

struct PresetActivateCrownConfirm: View {
    @Environment(LoopDataManager.self) var loopManager
    @Environment(\.sizeClass) private var sizeClass

    @State private var crownValue: CGFloat = 0 // Tracks Digital Crown rotation
    @State private var startingPreset: Bool = false
    @State private var lastInteractionTime: Date? // Tracks last crown interaction

    private let resetDelay: TimeInterval = 0.25 // pause for reset

    let preset: SelectablePreset

    var progress: CGFloat {
        if startingPreset {
            return 1
        } else {
            return abs(crownValue)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            PresetDetailView(preset: preset)

            Spacer()

            ZStack(alignment: .center) {
                if progress == 0 {
                    Text(startingPreset ? "Starting Preset..." : "Turn Digital Crown to Start")
                        .font(.system(size: 16))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    CircularProgressWithCheckmark(progress: progress, isComplete: startingPreset)
                                    .animation(.easeInOut(duration: 0.2), value: crownValue) // Smooth animation for progress
                                    .animation(.easeOut(duration: 0.3), value: startingPreset) // Fast animation for completion
                }
            }

        }
        .padding()
        .focusable() // Required for Digital Crown interaction
        .digitalCrownRotation(
            $crownValue,
            over: -1...1,
            sensitivity: .low,
            scalingRotationBy: 4
        )
        .onDisappear() {
            if let reminder = loopManager.pendingPresetReminder, reminder.presetIdentifier == preset.id {
                // If this was shown for confirming preset activation from a reminder notification, and we
                // are being dismissed, treat the dismissal as an acknowledgement
                loopManager.pendingPresetReminder = nil
                Task {
                    try? await loopManager.acknowledgeAlert(alertIdentifier: reminder.alertIdentifier, managerIdentifier: reminder.managerIdentifier)
                }
            }
        }
        .onChange(of: crownValue) { (oldValue, newValue) in
            lastInteractionTime = Date()

            Task {
                try? await Task.sleep(nanoseconds: UInt64(resetDelay * 1_000_000_000)) // Wait for 1 second
                if let lastTime = lastInteractionTime, Date().timeIntervalSince(lastTime) >= resetDelay && !startingPreset {
                    withAnimation {
                        crownValue = 0 // Reset progress
                    }
                }
            }

            if abs(newValue) >= 1 && !startingPreset {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    startingPreset = true
                    Task {
                        do {
                            var alertIdentifier: String? = nil
                            // If we're starting the preset from a reminder alert, then set alert identifier to acknowledge the alert
                            if let reminder = loopManager.pendingPresetReminder, reminder.presetIdentifier == preset.id {
                                alertIdentifier = reminder.presetIdentifier
                            }
                            try await loopManager.activateOverride(preset.createOverride(), alertIdentifierToAcknowledge: alertIdentifier)
                            WKInterfaceDevice.current().play(.success)
                        } catch {
                            print("Error! Could not activate preset: \(error)")
                            WKInterfaceDevice.current().play(.failure)
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(false) // Ensure back button is visible
    }
}
