#if LUPED_PEBBLE
import LoopKitUI
import SwiftUI

/// Settings → Devices → Pebble: controls the Pebble watchface transport.
struct LupedWatchSettingsView: View {
    @AppStorage(UserDefaults.lupedPebbleEnabledKey) private var isEnabled = true
    @AppStorage(UserDefaults.lupedPebbleAlarmsEnabledKey) private var alarmsEnabled = true
    @AppStorage(UserDefaults.lupedPebbleFullScreenKey) private var fullScreen = false
    @AppStorage(UserDefaults.lupedPebbleWatchfaceUUIDKey) private var watchfaceUUID = UserDefaults.lupedDefaultWatchfaceUUID
    @State private var draft = ""

    private var draftUUID: UUID? {
        UUID(uuidString: draft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var hasUnsavedDraft: Bool {
        draftUUID?.uuidString.lowercased() != watchfaceUUID.lowercased()
    }

    var body: some View {
        List {
            LupedLinkStatusSection(status: LupedPebbleTransport.shared.status)

            Section {
                Toggle(NSLocalizedString("Send to Pebble", comment: "Toggle enabling the Pebble watchface transport"), isOn: $isEnabled)
            } footer: {
                Text(NSLocalizedString("Loop sends glucose readings and glucose alert settings to a Pebble watchface over Bluetooth. Keep the watch paired with the Pebble app.", comment: "Footer for the Pebble watchface transport toggle"))
            }

            LupedWatchInfoSection(status: LupedPebbleTransport.shared.status)

            Section {
                Toggle(NSLocalizedString("Watch Alarms", comment: "Toggle enabling Pebble watch vibration alarms"), isOn: $alarmsEnabled)
            } footer: {
                Text(NSLocalizedString("Vibrate on the watch using the thresholds and repeat intervals from Settings → Alert Management → Glucose Alerts. Turning this off silences the watch only; Loop's alerts are unaffected.", comment: "Footer for the Pebble watch alarms toggle"))
            }
            .disabled(!isEnabled)

            Section {
                Toggle(NSLocalizedString("Full-Screen Ring", comment: "Toggle showing the Pebble glucose ring full screen"), isOn: $fullScreen)
            } footer: {
                Text(NSLocalizedString("Show a large glucose ring with the reading time inside it instead of the ring with a trend graph.", comment: "Footer for the Pebble full-screen ring toggle"))
            }
            .disabled(!isEnabled)

            Section {
                TextField(UserDefaults.lupedDefaultWatchfaceUUID, text: $draft)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(save)
                if hasUnsavedDraft {
                    Button(NSLocalizedString("Save", comment: "Button saving the Pebble watchface UUID"), action: save)
                        .disabled(draftUUID == nil)
                }
                if watchfaceUUID.lowercased() != UserDefaults.lupedDefaultWatchfaceUUID {
                    Button(NSLocalizedString("Use Luped CGM", comment: "Button restoring the default Pebble watchface UUID")) {
                        draft = UserDefaults.lupedDefaultWatchfaceUUID
                        save()
                    }
                }
            } header: {
                Text(NSLocalizedString("Watchface UUID", comment: "Header for the Pebble watchface UUID"))
            } footer: {
                if draftUUID == nil {
                    Text(NSLocalizedString("Enter a UUID such as bf32924c-4839-449e-9e56-ee190249acb2.", comment: "Footer shown for an invalid Pebble watchface UUID"))
                        .foregroundColor(.red)
                } else {
                    Text(NSLocalizedString("The UUID from the watchface's package.json. The watchface must use Luped's AppMessage keys and must not use PebbleKit JS.", comment: "Footer explaining the Pebble watchface UUID"))
                }
            }
            .disabled(!isEnabled)

            Section {
                NavigationLink(destination: LupedCommunicationLogView(log: LupedPebbleTransport.shared.communicationLog)) {
                    Text(NSLocalizedString("Communication Log", comment: "Row opening the Pebble communication log"))
                }
            } header: {
                Text(NSLocalizedString("Log", comment: "Header for the Pebble log section"))
            } footer: {
                Text(NSLocalizedString("Everything Loop sends to and receives from the watch since Loop started, newest first.", comment: "Footer for the Pebble log section"))
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(NSLocalizedString("Pebble", comment: "Title of the Pebble smartwatch settings screen"))
        .onAppear { draft = watchfaceUUID }
    }

    private func save() {
        guard let uuid = draftUUID else { return }
        watchfaceUUID = uuid.uuidString.lowercased()
        draft = watchfaceUUID
    }
}
/// Whether Loop is connected to the watch and when it last delivered a reading.
struct LupedLinkStatusSection: View {
    @ObservedObject var status: LupedLinkStatus

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private var watchfaceRejected: Bool {
        guard let rejected = status.lastRejectedAt else { return false }
        return rejected > (status.lastDelivery?.deliveredAt ?? .distantPast)
    }

    private var headline: String {
        switch status.link {
        case .off: return NSLocalizedString("Off", comment: "Pebble link status: disabled")
        case .bluetoothUnavailable: return NSLocalizedString("Bluetooth unavailable", comment: "Pebble link status: Bluetooth off or unauthorized")
        case .waitingForWatch: return NSLocalizedString("Waiting for the watch", comment: "Pebble link status: no watch session")
        case .connecting: return NSLocalizedString("Connecting", comment: "Pebble link status: session handshake in progress")
        case .open:
            if status.paused {
                return NSLocalizedString("Connected · paused, watchface not running", comment: "Pebble link status: sending paused after repeated rejections")
            }
            return watchfaceRejected
                ? NSLocalizedString("Connected · watchface not running", comment: "Pebble link status: connected but the watch rejected the reading")
                : NSLocalizedString("Connected", comment: "Pebble link status: session open")
        }
    }

    private var color: Color {
        switch status.link {
        case .open: return status.paused || watchfaceRejected ? .orange : .green
        case .connecting, .waitingForWatch: return .orange
        case .bluetoothUnavailable: return .red
        case .off: return .secondary
        }
    }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(headline).bold()
            }
            if let delivery = status.lastDelivery {
                Text(String(format: NSLocalizedString("Last reading %1$@ delivered at %2$@ in %3$d ms", comment: "Pebble status detail (1: reading time, 2: delivery time, 3: round trip)"), Self.timeFormatter.string(from: delivery.readingDate), Self.timeFormatter.string(from: delivery.deliveredAt), delivery.milliseconds))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if let retryAt = status.retryAt {
                Text(String(format: NSLocalizedString("Next retry at %@", comment: "Pebble status detail (1: retry time)"), Self.timeFormatter.string(from: retryAt)))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Button(NSLocalizedString("Send Now", comment: "Button pushing the current reading to the Pebble watch")) {
                LupedPebbleTransport.shared.sendNow()
            }
            .disabled(status.link == .off)
            if let result = status.lastResult {
                Text(result)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text(NSLocalizedString("Status", comment: "Header for the Pebble link status section"))
        }
    }
}

/// Battery and counters reported by the watchface.
struct LupedWatchInfoSection: View {
    @ObservedObject var status: LupedLinkStatus

    var body: some View {
        Section {
            if let info = status.diagnostics {
                row(NSLocalizedString("Battery", comment: "Pebble watch info: battery"), info.battery.map { "\($0)%" })
                row(NSLocalizedString("Readings received", comment: "Pebble watch info: DATA messages received"), info.readingsReceived.map(String.init))
                row(NSLocalizedString("Refresh requests", comment: "Pebble watch info: refresh requests sent"), info.refreshRequests.map(String.init))
                row(NSLocalizedString("Alarms (urgent low / low / high)", comment: "Pebble watch info: alarm counts"), alarmCounts(info))
                row(NSLocalizedString("Stale data events", comment: "Pebble watch info: stale transitions"), info.staleTransitions.map(String.init))
                row(NSLocalizedString("Phone disconnects", comment: "Pebble watch info: disconnects and total time"), disconnects(info))
                row(NSLocalizedString("Counting since", comment: "Pebble watch info: diagnostics window start"), info.countingSince.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) })
                row(NSLocalizedString("Updated", comment: "Pebble watch info: time the snapshot arrived"), DateFormatter.localizedString(from: info.receivedAt, dateStyle: .none, timeStyle: .medium))
            } else {
                Text(NSLocalizedString("No watch info yet.", comment: "Shown before the Pebble watch has sent diagnostics"))
                    .foregroundColor(.secondary)
            }
            if let note = status.watchInfoNote {
                Text(note)
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
            Button(NSLocalizedString("Refresh Watch Info", comment: "Button requesting Pebble watch diagnostics")) {
                LupedPebbleTransport.shared.requestDiagnostics()
            }
            .disabled(status.link != .open)
        } header: {
            Text(NSLocalizedString("Watch", comment: "Header for the Pebble watch info section"))
        } footer: {
            Text(NSLocalizedString("Reported by the watchface when you tap Refresh Watch Info. After Loop reconnects, the watchface restarts for a moment so it can reply. Counters cover at most the last 48 hours.", comment: "Footer for the Pebble watch info section"))
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value {
            LabeledContent(label, value: value)
        }
    }

    private func alarmCounts(_ info: LupedWatchDiagnostics) -> String? {
        guard let urgentLow = info.urgentLowAlarms, let low = info.lowAlarms, let high = info.highAlarms else { return nil }
        return "\(urgentLow) / \(low) / \(high)"
    }

    private func disconnects(_ info: LupedWatchDiagnostics) -> String? {
        guard let count = info.phoneDisconnects else { return nil }
        let seconds = info.phoneDisconnectedSeconds ?? 0
        return String(format: NSLocalizedString("%1$d (%2$d min total)", comment: "Pebble watch info: disconnect count and total minutes"), count, seconds / 60)
    }
}

/// The watch communication log, newest first.
struct LupedCommunicationLogView: View {
    @ObservedObject var log: LupedCommunicationLog

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text(NSLocalizedString("No watch communication yet.", comment: "Shown when the Pebble communication log is empty"))
                    .foregroundColor(.secondary)
            }
            ForEach(log.entries.reversed()) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol(for: entry.kind))
                        .foregroundColor(color(for: entry.kind))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.timeFormatter.string(from: entry.date))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                        Text(entry.message)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(NSLocalizedString("Communication Log", comment: "Title of the Pebble communication log"))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                ShareLink(item: log.text)
                    .disabled(log.entries.isEmpty)
                Button(role: .destructive) {
                    log.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(log.entries.isEmpty)
            }
        }
    }

    private func symbol(for kind: LupedCommunicationLog.Kind) -> String {
        switch kind {
        case .toWatch: return "arrow.up.right"
        case .fromWatch: return "arrow.down.left"
        case .info: return "info.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func color(for kind: LupedCommunicationLog.Kind) -> Color {
        switch kind {
        case .toWatch: return .blue
        case .fromWatch: return .green
        case .info: return .secondary
        case .error: return .red
        }
    }
}
#endif
