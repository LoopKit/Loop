//
//  LoopInsights_ChatView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Minimal Q&A interface for Ask LoopInsights.
/// Quick answers only — just the facts.
struct LoopInsights_ChatView: View {

    @ObservedObject var viewModel: LoopInsights_ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    @State private var previousInputText = ""

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
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
                        .padding(.vertical, 8)
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.15, alpha: 1)
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        .onDisappear {
            viewModel.stopSpeaking()
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = nil
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("Ask LoopInsights", comment: "LoopInsights chat title"))
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

                if !isUser && message.voiceInitiated {
                    Button(action: { viewModel.voiceService.speak(message.content) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption2)
                            Text(NSLocalizedString("Listen", comment: "LoopInsights chat: replay TTS"))
                                .font(.caption2)
                        }
                        .foregroundColor(.purple.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.white.opacity(0.5))
            Text(NSLocalizedString("Thinking...", comment: "LoopInsights chat: AI thinking"))
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 16)
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
        .padding(.horizontal, 12)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 40)

            Text(NSLocalizedString("Ask a question about your data", comment: "LoopInsights chat empty state"))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))

            // Quick-ask chips
            VStack(spacing: 8) {
                ForEach(viewModel.quickAskSuggestions, id: \.self) { suggestion in
                    Button(action: { viewModel.sendQuickAsk(suggestion) }) {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
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
            .onChange(of: viewModel.inputText) { newValue in
                viewModel.handleTextChange(oldValue: previousInputText, newValue: newValue)
                previousInputText = newValue
            }

            if viewModel.isSpeaking {
                Button(action: { viewModel.stopSpeaking() }) {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
            } else {
                Button(action: { viewModel.sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading
                                ? .white.opacity(0.2)
                                : .purple
                        )
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color(red: 0.06, green: 0.07, blue: 0.15)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
