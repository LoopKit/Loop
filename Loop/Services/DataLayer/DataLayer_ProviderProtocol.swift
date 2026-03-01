//
//  DataLayer_ProviderProtocol.swift
//  Loop
//
//  DataLayer — Provider integration protocol and registry for direct uploads.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Protocol for healthcare provider integrations (e.g. MyScripps, Epic MyChart).
/// Concrete providers register with the shared registry and appear automatically in the UI.
protocol DataLayer_ProviderProtocol {
    var displayName: String { get }
    var iconName: String { get }        // SF Symbol name
    var requiresAuth: Bool { get }
    var isConfigured: Bool { get }

    func configure() async -> Bool
    func upload(events: [DataLayer_Event], days: Int) async throws -> URL?
}

/// Central registry of available provider integrations.
/// Providers register themselves on app launch; the UI queries hasProviders to decide what to show.
final class DataLayer_ProviderRegistry {
    static let shared = DataLayer_ProviderRegistry()
    private(set) var providers: [DataLayer_ProviderProtocol] = []

    var hasProviders: Bool { !providers.isEmpty }

    func register(_ provider: DataLayer_ProviderProtocol) {
        providers.append(provider)
    }
}
