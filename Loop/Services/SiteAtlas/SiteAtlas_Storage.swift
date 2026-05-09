//
//  SiteAtlas_Storage.swift
//  Loop
//
//  SiteAtlas — JSON-based persistence for site entries.
//  Thread-safe read/write with automatic 365-day retention pruning.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

final class SiteAtlas_Storage {

    static let shared = SiteAtlas_Storage()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.loopkit.Loop.SiteAtlas.Storage", qos: .utility)

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documents.appendingPathComponent("SiteAtlasEntries.json")
    }

    // MARK: - Public API

    /// Load all entries (pruning expired ones on read).
    func loadEntries() -> [SiteAtlas_SiteEntry] {
        return queue.sync {
            var data = readFromDisk()
            let pruned = prune(&data)
            if pruned {
                writeToDisk(data)
            }
            return data.entries
        }
    }

    /// Add a new site entry.
    func addEntry(_ entry: SiteAtlas_SiteEntry) {
        var existingHadHidden = false
        queue.sync {
            var data = readFromDisk()
            // Track whether we're replacing a recently-hidden entry of the
            // same type — useful churn signal for the dashboard.
            existingHadHidden = data.entries.contains { $0.type == entry.type && $0.isHidden }
            data.entries.append(entry)
            writeToDisk(data)
        }
        postPlacedNotification(entry: entry, replacementOfHidden: existingHadHidden)
    }

    /// Broadcast that a new site was placed so DataLayer can record a
    /// `siteAtlasPlaced` event. Decoupled via NotificationCenter — this
    /// service has zero DataLayer deps.
    private func postPlacedNotification(entry: SiteAtlas_SiteEntry, replacementOfHidden: Bool) {
        let zoneID: String? = SiteAtlas_Zones.zones(for: entry.bodySide).first { zone in
            // Point-in-ellipse test in normalized coords.
            let dx = (entry.normalizedX - zone.centerX) / zone.radiusX
            let dy = (entry.normalizedY - zone.centerY) / zone.radiusY
            return (dx * dx + dy * dy) <= 1.0
        }?.id

        NotificationCenter.default.post(
            name: Notification.Name("com.loopkit.Loop.siteAtlasPlaced"),
            object: nil,
            userInfo: [
                "type": entry.type.rawValue,
                "bodySide": entry.bodySide.rawValue,
                "zoneID": zoneID as Any,
                "replacementOfHidden": replacementOfHidden
            ]
        )
    }

    /// Delete entry by ID.
    func deleteEntry(id: UUID) {
        queue.sync {
            var data = readFromDisk()
            data.entries.removeAll { $0.id == id }
            writeToDisk(data)
        }
    }

    /// Update an existing entry by ID.
    func updateEntry(_ updated: SiteAtlas_SiteEntry) {
        queue.sync {
            var data = readFromDisk()
            if let idx = data.entries.firstIndex(where: { $0.id == updated.id }) {
                data.entries[idx] = updated
                writeToDisk(data)
            }
        }
    }

    /// Delete all entries.
    func deleteAll() {
        queue.sync {
            writeToDisk(SiteAtlas_SiteData())
        }
    }

    /// Get entries filtered by type.
    func entries(ofType type: SiteAtlas_SiteType) -> [SiteAtlas_SiteEntry] {
        return loadEntries().filter { $0.type == type }
    }

    /// Get the most recent entry for a given type.
    func mostRecent(ofType type: SiteAtlas_SiteType) -> SiteAtlas_SiteEntry? {
        return entries(ofType: type).sorted { $0.date > $1.date }.first
    }

    // MARK: - Private

    private func readFromDisk() -> SiteAtlas_SiteData {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.siteAtlasDecoder.decode(SiteAtlas_SiteData.self, from: data)
        else {
            return SiteAtlas_SiteData()
        }
        return decoded
    }

    private func writeToDisk(_ siteData: SiteAtlas_SiteData) {
        guard let data = try? JSONEncoder.siteAtlasEncoder.encode(siteData) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Prune entries older than retention period. Returns true if entries were removed.
    @discardableResult
    private func prune(_ data: inout SiteAtlas_SiteData) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -SiteAtlas_Theme.retentionDays, to: Date())!
        let before = data.entries.count
        data.entries.removeAll { $0.date < cutoff }
        return data.entries.count != before
    }
}

// MARK: - Coders

private extension JSONDecoder {
    static let siteAtlasDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let siteAtlasEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
