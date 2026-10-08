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
            Section {
                Toggle(NSLocalizedString("Send to Pebble", comment: "Toggle enabling the Pebble watchface transport"), isOn: $isEnabled)
            } footer: {
                Text(NSLocalizedString("Loop sends glucose readings and glucose alert settings to a Pebble watchface over Bluetooth. Keep the watch paired with the Pebble app.", comment: "Footer for the Pebble watchface transport toggle"))
            }

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
