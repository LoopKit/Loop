//
//  GlucoseAlertManager+Sharing.swift
//  Loop
//
//  What the glucose alerts are configured from, so another controller can run the same rules.
//

import Foundation

/// The settings `GlucoseAlertManager` evaluates against; episode state and sounds stay local.
struct GlucoseAlertSettings: Codable, Equatable {
    var profiles: [GlucoseAlertProfile]
    var activeProfileID: UUID
    var cgmProvidesOwnAlerts: Bool
    var loopAlertsOverrideForOwnAlertingCGM: Bool

    init?(encoded data: Data?) {
        guard let data, let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = decoded
    }

    init(profiles: [GlucoseAlertProfile], activeProfileID: UUID,
         cgmProvidesOwnAlerts: Bool, loopAlertsOverrideForOwnAlertingCGM: Bool) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.cgmProvidesOwnAlerts = cgmProvidesOwnAlerts
        self.loopAlertsOverrideForOwnAlertingCGM = loopAlertsOverrideForOwnAlertingCGM
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
}

extension GlucoseAlertManager {
    var sharedSettings: GlucoseAlertSettings {
        GlucoseAlertSettings(profiles: profiles, activeProfileID: activeProfileID,
                             cgmProvidesOwnAlerts: cgmProvidesOwnAlerts,
                             loopAlertsOverrideForOwnAlertingCGM: loopAlertsOverrideForOwnAlertingCGM)
    }

    /// Takes another controller's settings; this manager keeps its own episode state.
    func adopt(_ settings: GlucoseAlertSettings) {
        guard !settings.profiles.isEmpty else { return }
        profiles = settings.profiles
        activeProfileID = settings.activeProfileID
        cgmProvidesOwnAlerts = settings.cgmProvidesOwnAlerts
        loopAlertsOverrideForOwnAlertingCGM = settings.loopAlertsOverrideForOwnAlertingCGM
    }
}
