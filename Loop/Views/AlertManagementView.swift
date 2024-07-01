//
//  AlertManagementView.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2022-09-09.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct AlertManagementView: View {
    @Environment(\.appName) private var appName
    @Environment(\.guidanceColors) private var guidanceColors

    @ObservedObject private var checker: AlertPermissionsChecker
    @ObservedObject private var alertMuter: AlertMuter

    enum Sheet: Hashable, Identifiable {
        case durationSelection
        case confirmation(resumeDate: Date)
        
        var id: Int {
            hashValue
        }
    }
    
    @State private var sheet: Sheet?
    @State private var durationSelection: TimeInterval?
    @State private var durationWasSelection: Bool = false

    private var formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    private var formattedSelectedDuration: Binding<String> {
        Binding(
            get: { formatter.string(from: alertMuter.configuration.duration)! },
            set: { newValue in
                guard let selectedDurationIndex = AlertMuter.allowedDurations.compactMap({ formatter.string(from: $0) }).firstIndex(of: newValue)
                else { return }
                DispatchQueue.main.async {
                    // avoid publishing during view update
                    alertMuter.configuration.startTime = Date()
                    alertMuter.configuration.duration = AlertMuter.allowedDurations[selectedDurationIndex]
                }
            }
        )
    }
    
    private var missedMealNotificationsEnabled: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.missedMealNotificationsEnabled },
            set: { enabled in
                UserDefaults.standard.missedMealNotificationsEnabled = enabled
            }
        )
    }

    public init(checker: AlertPermissionsChecker, alertMuter: AlertMuter = AlertMuter()) {
        self.checker = checker
        self.alertMuter = alertMuter
    }

    var body: some View {
        List {
            alertPermissionsSection
            if FeatureFlags.criticalAlertsEnabled {
                muteAlertsSection
            }
            if FeatureFlags.missedMealNotifications {
                missedMealAlertSection
            }
            supportSection
        }
        .navigationTitle(NSLocalizedString("Alert Management", comment: "Title of alert management screen"))
    }

    private var alertPermissionsSection: some View {
        Section(header: Text("iOS").textCase(nil)) {
            NavigationLink(destination:
                            NotificationsCriticalAlertPermissionsView(mode: .flow, checker: checker))
            {
                HStack {
                    Text(NSLocalizedString("iOS Permissions", comment: "iOS Permissions button text"))
                    if checker.showWarning ||
                        checker.notificationCenterSettings.scheduledDeliveryEnabled {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.critical)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var muteAlertsSection: some View {
        Section(
            header: Text(String(format: "%1$@", appName)),
            footer: !alertMuter.configuration.shouldMute ? Text(String(format: NSLocalizedString("Temporarily silence all sounds from %1$@, including sounds for all critical alerts such as Urgent Low, Sensor Fail, Pump Expiration and others.", comment: ""), appName)) : nil
        ) {
            if !alertMuter.configuration.shouldMute {
                muteAlertsButton
            } else {
                unmuteAlertsButton
                    .listRowSeparator(.visible, edges: .all)
                muteAlertsSummary
            }
        }
    }
    
    private var muteAlertsButton: some View {
        Button {
            if !alertMuter.configuration.shouldMute {
                sheet = .durationSelection
            }
        } label: {
            HStack(spacing: 12) {
                Spacer()
                Text(NSLocalizedString("Mute All App Sounds", comment: "Label for button to mute all app sounds"))
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .durationSelection:
                DurationSheet(
                    allowedDurations: AlertMuter.allowedDurations,
                    duration: $durationSelection,
                    durationWasSelected: $durationWasSelection
                )
            case .confirmation(let resumeDate):
                ConfirmationSheet(resumeDate: resumeDate)
            }
        }
        .onChange(of: durationWasSelection) { _ in
            if durationWasSelection, let durationSelection, let durationSelectionString = formatter.string(from: durationSelection) {
                sheet = .confirmation(resumeDate: Date().addingTimeInterval(durationSelection))
                formattedSelectedDuration.wrappedValue = durationSelectionString
                self.durationSelection = nil
                self.durationWasSelection = false
            }
        }
    }
    
    private var unmuteAlertsButton: some View {
        Button(action: alertMuter.unmuteAlerts) {
            Group {
                Text(Image(systemName: "speaker.slash.fill"))
                    .foregroundColor(guidanceColors.warning)
                + Text("  ")
                + Text(NSLocalizedString("Tap to Unmute All App Sounds", comment: "Label for button to unmute all app sounds"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
        }
    }
    
    private var muteAlertsSummary: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("Muted until", comment: "Label for when mute alert will end"))
                Spacer()
                Text(alertMuter.formattedEndTime)
                    .foregroundColor(.secondary)
            }
            
            Text("All app sounds, including sounds for all critical alerts such as Urgent Low, Sensor Fail, Pump Expiration, and others will NOT sound.", comment: "Warning label that all alerts will not sound")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var missedMealAlertSection: some View {
        Section(footer: DescriptiveText(label: NSLocalizedString("When enabled, Loop can notify you when it detects a meal that wasn't logged.", comment: "Description of missed meal notifications."))) {
            Toggle(NSLocalizedString("Missed Meal Notifications", comment: "Title for missed meal notifications toggle"), isOn: missedMealNotificationsEnabled)
        }
    }
    
    @ViewBuilder
    private var supportSection: some View {
        Section(
            header: SectionHeader(label: NSLocalizedString("Support", comment: "Section title for Support")).padding(.leading, -16).padding(.bottom, 4),
            footer: Text(String(format: "Frequently asked questions about alerts from iOS and %1$@.", appName))) {
                NavigationLink {
                    HowMuteAlertWorkView()
                } label: {
                    Text("Learn more about Alerts", comment: "Link to learn more about alerts")
                }

        }
    }
}

extension UserDefaults {
    private enum Key: String {
        case missedMealNotificationsEnabled = "com.loopkit.Loop.MissedMealNotificationsEnabled"
    }
    
    var missedMealNotificationsEnabled: Bool {
        get {
            return object(forKey: Key.missedMealNotificationsEnabled.rawValue) as? Bool ?? false
        }
        set {
            set(newValue, forKey: Key.missedMealNotificationsEnabled.rawValue)
        }
    }
}

struct AlertManagementView_Previews: PreviewProvider {
    static var previews: some View {
        AlertManagementView(checker: AlertPermissionsChecker(), alertMuter: AlertMuter())
    }
}
