//
//  LoopInsights_ChatHistoryStore.swift
//  Loop
//
//  LoopInsights — Persists Ask Loopy conversation transcripts for later review.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Persists Ask Loopy conversation transcripts to JSON.
/// Keeps the 10 most recent conversations, dropping anything older than 30 days.
/// Each typical 5-exchange session is ~2 KB, so 10 sessions ≈ 20 KB total.
enum LoopInsights_ChatHistoryStore {

    private static let fileName = "LoopInsights_ChatHistory.json"
    private static let maxCount = 10
    private static let retentionDays: TimeInterval = 30 * 24 * 3600

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LoopInsights", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    // MARK: - Read

    /// All saved transcripts, newest first.
    static func loadAll() -> [LoopInsightsChatTranscript] {
        guard let data = try? Data(contentsOf: fileURL),
              let transcripts = try? JSONDecoder().decode([LoopInsightsChatTranscript].self, from: data) else {
            return []
        }
        return transcripts.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Write

    /// Persist a new transcript. Silently ignored if the session had no AI reply.
    /// Prunes to 10 most recent / 30-day retention on every save.
    static func append(_ transcript: LoopInsightsChatTranscript) {
        guard transcript.messages.contains(where: { $0.role == .assistant }) else { return }
        var all = loadAll()
        all.append(transcript)
        save(all)
    }

    /// Delete a single transcript by ID.
    static func delete(id: UUID) {
        var all = loadAll()
        all.removeAll { $0.id == id }
        save(all)
    }

    /// Delete all saved transcripts.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private

    private static func save(_ transcripts: [LoopInsightsChatTranscript]) {
        let cutoff = Date().addingTimeInterval(-retentionDays)
        var pruned = transcripts.filter { $0.startedAt > cutoff }
        if pruned.count > maxCount {
            pruned = Array(pruned.sorted { $0.startedAt > $1.startedAt }.prefix(maxCount))
        }
        if let data = try? JSONEncoder().encode(pruned) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
