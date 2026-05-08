//
//  SiteAtlas_Coordinator.swift
//  Loop
//
//  SiteAtlas — Central coordinator for site rotation tracking.
//  Listens for pump deactivation notifications and prompts site logging.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine

// MARK: - Notification Names

extension Notification.Name {
    static let pumpSiteDeactivated = Notification.Name("com.loopkit.Loop.pumpSiteDeactivated")
    static let siteAtlasShouldPromptLog = Notification.Name("com.loopkit.Loop.siteAtlasShouldPromptLog")
}

// MARK: - Coordinator

final class SiteAtlas_Coordinator: ObservableObject {

    static let shared = SiteAtlas_Coordinator()

    /// When true, the UI layer should present the site selection sheet.
    @Published var pendingSiteLog: Bool = false

    /// The type of site to prompt for (set before pendingSiteLog becomes true).
    @Published var promptedSiteType: SiteAtlas_SiteType = .pump

    private var cancellables = Set<AnyCancellable>()
    private let storage = SiteAtlas_Storage.shared

    private init() {
        setupNotificationListeners()
    }

    // MARK: - Public API

    /// Log a new site entry.
    func logSite(_ entry: SiteAtlas_SiteEntry) {
        storage.addEntry(entry)
        pendingSiteLog = false
    }

    /// Skip logging (dismiss prompt without saving).
    func skipLogging() {
        pendingSiteLog = false
    }

    /// Manually trigger a site log prompt (e.g., from Settings).
    func promptManualLog(type: SiteAtlas_SiteType) {
        promptedSiteType = type
        pendingSiteLog = true
    }

    /// All entries from storage.
    func allEntries() -> [SiteAtlas_SiteEntry] {
        storage.loadEntries()
    }

    /// Update an existing entry (date, type, notes).
    func updateEntry(_ entry: SiteAtlas_SiteEntry) {
        storage.updateEntry(entry)
    }

    /// Delete a specific entry.
    func deleteEntry(id: UUID) {
        storage.deleteEntry(id: id)
    }

    /// Delete all entries.
    func deleteAllEntries() {
        storage.deleteAll()
    }

    /// Most recent entry for a given type.
    func mostRecent(ofType type: SiteAtlas_SiteType) -> SiteAtlas_SiteEntry? {
        storage.mostRecent(ofType: type)
    }

    // MARK: - Private

    private func setupNotificationListeners() {
        NotificationCenter.default.publisher(for: .pumpSiteDeactivated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, SiteAtlas_FeatureFlags.isEnabled else { return }
                self.promptedSiteType = .pump
                self.pendingSiteLog = true
            }
            .store(in: &cancellables)
    }
}
