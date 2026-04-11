//
//  LoopInsights_ChatHistoryView.swift
//  Loop
//
//  LoopInsights — Browse and re-read saved Ask Loopy conversations.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - History List

/// Shows all saved Ask Loopy conversations. Tap any row to read the full transcript.
struct LoopInsights_ChatHistoryView: View {

    @State private var transcripts: [LoopInsightsChatTranscript] = []
    @State private var selectedTranscript: LoopInsightsChatTranscript?
    @State private var showingDeleteAllConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.15)
                .ignoresSafeArea()

            if transcripts.isEmpty {
                emptyState
            } else {
                transcriptList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            transcripts = LoopInsights_ChatHistoryStore.loadAll()
            UITableView.appearance().backgroundColor = .clear
        }
        .onDisappear {
            UITableView.appearance().backgroundColor = .systemBackground
        }
        .sheet(item: $selectedTranscript) { transcript in
            NavigationView {
                LoopInsights_ChatTranscriptView(transcript: transcript)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("Past Conversations", comment: "LoopInsights chat history title"))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingDeleteAllConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.white.opacity(transcripts.isEmpty ? 0 : 0.7))
                }
                .disabled(transcripts.isEmpty)
            }
        }
        .confirmationDialog(
            NSLocalizedString("Clear all past conversations?", comment: "LoopInsights chat history: delete all title"),
            isPresented: $showingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Clear All", comment: "LoopInsights chat history: clear all button"), role: .destructive) {
                LoopInsights_ChatHistoryStore.deleteAll()
                transcripts = []
            }
        }
    }

    // MARK: - List

    private var transcriptList: some View {
        List {
            ForEach(transcripts) { transcript in
                Button(action: { selectedTranscript = transcript }) {
                    transcriptRow(transcript)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.white.opacity(0.05))
                .listRowSeparatorTint(.white.opacity(0.08))
            }
            .onDelete { indexSet in
                for index in indexSet {
                    LoopInsights_ChatHistoryStore.delete(id: transcripts[index].id)
                }
                transcripts.remove(atOffsets: indexSet)
            }
        }
        .listStyle(.plain)
    }

    private func transcriptRow(_ transcript: LoopInsightsChatTranscript) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(transcript.startedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                Text(transcript.preview)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                Text(String(format: NSLocalizedString("%d messages", comment: "LoopInsights chat history: message count"), transcript.visibleMessageCount))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.2))
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.15))
            Text(NSLocalizedString("No saved conversations yet", comment: "LoopInsights chat history: empty title"))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.35))
            Text(NSLocalizedString("Conversations are saved automatically when you close Ask Loopy.", comment: "LoopInsights chat history: empty subtitle"))
                .font(.caption)
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Read-Only Transcript

/// Displays a single saved conversation in the same dark chat style as Ask Loopy,
/// but read-only — no input bar, no actions.
struct LoopInsights_ChatTranscriptView: View {

    let transcript: LoopInsightsChatTranscript
    @Environment(\.dismiss) private var dismiss

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.15)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(transcript.messages.filter { $0.role != .system }) { message in
                        chatBubble(message)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("🌀 " + NSLocalizedString("Ask Loopy!", comment: "LoopInsights Loopy chat title"))
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(transcript.startedAt, style: .date)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Bubble

    private func chatBubble(_ message: LoopInsightsChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.subheadline)
                    .foregroundColor(isUser ? .white : .white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isUser ? Color.purple.opacity(0.6) : Color.white.opacity(0.08))
                    )

                Text(timeFormatter.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
    }
}
