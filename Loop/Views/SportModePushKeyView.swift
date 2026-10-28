//
//  SportModePushKeyView.swift
//  Loop
//
//  The user's Apple push key, so a watch with its own internet can tell this phone when it starts
//  Sport Mode without it. Kept in the phone's keychain; the watch receives it with its standing copy.
//  The same kind of key Nightscout's remote commands use; nothing is built into the app.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopCore

struct SportModePushKey: Codable, Equatable {
    var keyID: String
    var key: String

    /// The build's own team, which the key must belong to.
    static var teamID: String? {
        (Bundle.main.object(forInfoDictionaryKey: "DevelopmentTeam") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static let keychainService = "SportModePushKey"

    static func load() -> SportModePushKey? {
        guard let data = try? KeychainManager().getGenericPasswordForServiceAsData(keychainService) else { return nil }
        return try? JSONDecoder().decode(SportModePushKey.self, from: data)
    }

    static func save(_ key: SportModePushKey?) {
        try? KeychainManager().replaceGenericPassword(key.flatMap { try? JSONEncoder().encode($0) }, forService: keychainService)
    }

    /// nil without a key or a push token: the watch then sends nothing.
    static func phoneReach(deviceToken: String?) -> PhoneReach? {
        guard let key = load(), let teamID, let deviceToken, !deviceToken.isEmpty,
              let topic = Bundle.main.bundleIdentifier else { return nil }
        return PhoneReach(deviceToken: deviceToken, topic: topic, production: AppExpirationAlerter.isTestFlightBuild(),
                          keyID: key.keyID, teamID: teamID, key: key.key)
    }
}

struct SportModePushKeyView: View {
    @State private var keyID = ""
    @State private var key = ""
    @State private var savedKeyID = SportModePushKey.load()?.keyID

    var body: some View {
        Form {
            Section {
                if let savedKeyID {
                    Label(String(format: NSLocalizedString("Key %@ saved", comment: "Sport Mode push key: status when a key is saved (1: key ID)"), savedKeyID),
                          systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Text(NSLocalizedString("No key saved", comment: "Sport Mode push key: status when no key is saved"))
                        .foregroundColor(.secondary)
                }
            }
            Section(footer: Text(NSLocalizedString("When Sport Mode starts on a watch with its own internet while this iPhone is out of reach, the watch tells this iPhone right away, so it stops trying to loop. Use an APNs key from the Apple Developer team this app is built with, the same kind Nightscout uses for remote commands.", comment: "Footer explaining the Sport Mode push key"))) {
                TextField(NSLocalizedString("Key ID", comment: "Sport Mode push key: the key's ID"), text: $keyID)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                TextField(savedKeyID == nil
                          ? NSLocalizedString("Paste the key (.p8 contents)", comment: "Sport Mode push key: the key text")
                          : NSLocalizedString("Saved. Paste a new key to replace it.", comment: "Sport Mode push key: the key field once a key is saved"),
                          text: $key, axis: .vertical)
                    .lineLimit(3...6)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            Section {
                Button(NSLocalizedString("Save", comment: "Sport Mode push key: save")) {
                    SportModePushKey.save(SportModePushKey(keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
                                                           key: key.trimmingCharacters(in: .whitespacesAndNewlines)))
                    savedKeyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
                    key = ""
                }
                .disabled(keyID.isEmpty || !key.contains("PRIVATE KEY"))
                if savedKeyID != nil {
                    Button(NSLocalizedString("Remove Key", comment: "Sport Mode push key: remove"), role: .destructive) {
                        SportModePushKey.save(nil)
                        savedKeyID = nil
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Sport Mode Push", comment: "Title of the Sport Mode push key screen"))
        .onAppear {
            if let saved = SportModePushKey.load() {
                keyID = saved.keyID
            }
        }
    }
}

extension SettingsView {
    var sportModePushSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Sport Mode", comment: "The title of the Sport Mode section in settings"))) {
            NavigationLink(destination: SportModePushKeyView()) {
                Text(NSLocalizedString("Push Key", comment: "Settings row for the Sport Mode push key"))
            }
        }
    }
}
