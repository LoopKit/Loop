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

    @State private var showMuteAlertOptions: Bool = false

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
                guard let selectedDurationIndex = formatterDurations.firstIndex(of: newValue)
                else { return }
                DispatchQueue.main.async {
                    // avoid publishing during view update
                    alertMuter.configuration.startTime = Date()
                    alertMuter.configuration.duration = AlertMuter.allowedDurations[selectedDurationIndex]
                }
            }
        )
    }

    private var formatterDurations: [String] {
        AlertMuter.allowedDurations.compactMap { formatter.string(from: $0) }
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
                            .accessibilityIdentifier("settingsViewAlertManagementAlertPermissionsAlertWarning")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var muteAlertsSection: some View {
        Section(
            header: Text(String(format: "%1$@", appName)),
            footer: !alertMuter.configuration.shouldMute ? Text(String(format: NSLocalizedString("Temporarily silence all sounds from %1$@, including sounds for Critical Alerts such as Urgent Low, Sensor Fail, Pump Expiration and others.\n\nWhile sounds are muted, alerts from %1$@ will still vibrate if haptics are enabled. Your insulin pump and CGM hardware may still sound.", comment: ""), appName, appName)) : nil
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
        Button(action: { showMuteAlertOptions = true }) {
            HStack(spacing: 12) {
                Spacer()
                muteAlertIcon
                Text(NSLocalizedString("Mute App Sounds", comment: "Label for button to mute app sounds"))
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .actionSheet(isPresented: $showMuteAlertOptions) {
           muteAlertOptionsActionSheet
        }
    }
    
    private var unmuteAlertsButton: some View {
        Button(action: alertMuter.unmuteAlerts) {
            HStack(spacing: 12) {
                Spacer()
                unmuteAlertIcon
                Text(NSLocalizedString("Tap to Unmute App Sounds", comment: "Label for button to unmute all app sounds"))
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.vertical, 6)
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
            
            Text("All app sounds, including sounds for Critical Alerts such as Urgent Low, Sensor Fail, and Pump Expiration will NOT sound.", comment: "Warning label that all alerts will not sound")
                .font(.footnote)
        }
    }

    private var muteAlertIcon: some View {
        Image(systemName: "speaker.slash.fill")
            .resizable()
            .foregroundColor(.white)
            .padding(5)
            .frame(width: 22, height: 22)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var unmuteAlertIcon: some View {
        Image(systemName: "speaker.wave.2.fill")
            .resizable()
            .foregroundColor(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .frame(width: 22, height: 22)
            .background(guidanceColors.warning)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var muteAlertOptionsActionSheet: ActionSheet {
        var muteAlertDurationOptions: [SwiftUI.Alert.Button] = formatterDurations.map { muteAlertDuration in
            .default(Text(muteAlertDuration),
                     action: { formattedSelectedDuration.wrappedValue =  muteAlertDuration })
        }
        muteAlertDurationOptions.append(.cancel())

        return ActionSheet(
            title: Text(NSLocalizedString("Set Time Duration", comment: "Title for mute alert duration selection action sheet")),
            message: Text(NSLocalizedString("All app sounds, including sounds for Critical Alerts such as Urgent Low, Sensor Fail, and Pump Expiration will NOT sound.", comment: "Message for mute alert duration selection action sheet")),
            buttons: muteAlertDurationOptions)
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
