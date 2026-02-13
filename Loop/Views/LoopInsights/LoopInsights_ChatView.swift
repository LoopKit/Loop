//
//  LoopInsights_ChatView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Full chat interface for Ask LoopInsights.
/// Dark-themed design with gradient background, purple user bubbles,
/// dark card AI bubbles, and a dark input bar.
struct LoopInsights_ChatView: View {

    @ObservedObject var viewModel: LoopInsights_ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.15),
                    Color(red: 0.08, green: 0.10, blue: 0.22),
                    Color(red: 0.05, green: 0.06, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if viewModel.messages.isEmpty {
                                emptyStateView
                            } else {
                                ForEach(viewModel.messages) { message in
                                    chatBubble(message)
                                        .id(message.id)
                                }
                            }

                            if viewModel.isLoading {
                                loadingIndicator
                                    .id("loading")
                            }

                            if let error = viewModel.errorMessage {
                                errorView(error)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation {
                            if let lastMessage = viewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            } else if viewModel.isLoading {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }

                inputBar
            }
        }
        .navigationTitle(NSLocalizedString("Ask LoopInsights", comment: "LoopInsights chat title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.messages.isEmpty {
                    Button(action: { viewModel.clearConversation() }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    // MARK: - Chat Bubble

    private func chatBubble(_ message: LoopInsightsChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 50) }

            if !isUser {
                // AI avatar
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundColor(.purple.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if isUser {
                    // Purple gradient user bubble
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.25, blue: 0.85),
                                    Color(red: 0.75, green: 0.20, blue: 0.65)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    // Dark card AI bubble
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.92))
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.10))
                        )
                }

                Text(Self.timeFormatter.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 50) }
        }
        .padding(.horizontal)
    }

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.caption)
                .foregroundColor(.purple.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())

            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white.opacity(0.6))
                Text(NSLocalizedString("Thinking...", comment: "LoopInsights chat: AI thinking"))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
            )

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red.opacity(0.8))
            Text(error)
                .font(.caption)
                .foregroundColor(.red.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.1))
        )
        .padding(.horizontal)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 60)

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.purple.opacity(0.5))

            Text(NSLocalizedString("Ask me anything about your diabetes management", comment: "LoopInsights chat empty state title"))
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("I have access to your current therapy settings and recent glucose data. Try one of the suggestions below or type your own question.", comment: "LoopInsights chat empty state subtitle"))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Quick-ask chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.quickAskSuggestions, id: \.self) { suggestion in
                        Button(action: { viewModel.sendQuickAsk(suggestion) }) {
                            Text(suggestion)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.purple.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Placeholder "+" button (non-functional for now)
            Button(action: {}) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.3))
            }
            .disabled(true)

            // Text field area
            HStack(spacing: 8) {
                TextField(
                    NSLocalizedString("Ask a question...", comment: "LoopInsights chat input placeholder"),
                    text: $viewModel.inputText
                )
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .focused($isInputFocused)
                .onSubmit {
                    viewModel.sendMessage()
                }
                .tint(.purple)

                // Send button
                Button(action: { viewModel.sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading
                                ? .white.opacity(0.2)
                                : .purple
                        )
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(red: 0.06, green: 0.07, blue: 0.15)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
