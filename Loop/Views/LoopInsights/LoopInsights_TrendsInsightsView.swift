//
//  LoopInsights_TrendsInsightsView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Tab-based Trends & Insights view with Daily/Weekly/Monthly/Stats/Advisor tabs.
/// Shows AI-generated summaries of glucose data with stats chips, summary cards,
/// and highlights sections. Dark-themed to match the restyled ChatView.
struct LoopInsights_TrendsInsightsView: View {

    let coordinator: LoopInsights_Coordinator
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TrendsViewModel()
    @State private var showingChat = false

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
                tabBar
                tabContent
            }
        }
        .navigationTitle(NSLocalizedString("Trends & Insights", comment: "LoopInsights trends title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.selectedTab.isTimePeriod {
                    Button(action: { viewModel.refresh(coordinator: coordinator) }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .onAppear {
            viewModel.loadIfNeeded(coordinator: coordinator)
        }
        .sheet(isPresented: $showingChat) {
            NavigationView {
                LoopInsights_ChatView(
                    viewModel: LoopInsights_ChatViewModel(coordinator: coordinator)
                )
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TrendsTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedTab = tab
                        }
                        if tab == .advisor {
                            showingChat = true
                        } else {
                            viewModel.loadIfNeeded(coordinator: coordinator)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.caption2)
                            Text(tab.label)
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(viewModel.selectedTab == tab ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(viewModel.selectedTab == tab
                                    ? Color.purple.opacity(0.6)
                                    : Color.white.opacity(0.08)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .daily, .weekly, .monthly:
            timePeriodContent
        case .stats:
            statsContent
        case .advisor:
            // Advisor shows a prompt card; tapping opens chat
            advisorContent
        }
    }

    // MARK: - Time Period Content (Daily/Weekly/Monthly)

    private var timePeriodContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Date header
                dateHeader

                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorCard(error)
                } else {
                    // Stats chips
                    if let stats = viewModel.cachedStats[viewModel.selectedTab] {
                        statsChipsRow(stats: stats)
                    }

                    // Summary card
                    if let summary = viewModel.cachedSummaries[viewModel.selectedTab], !summary.isEmpty {
                        summaryCard(summary)
                    }

                    // Highlights card
                    if let highlights = viewModel.cachedHighlights[viewModel.selectedTab], !highlights.isEmpty {
                        highlightsCard(highlights)
                    }

                    // Show placeholder if no data yet
                    if viewModel.cachedSummaries[viewModel.selectedTab] == nil
                        && viewModel.cachedStats[viewModel.selectedTab] == nil {
                        noDataPlaceholder
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.dayFormatter.string(from: Date()))
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            if let generatedAt = viewModel.cachedGeneratedAt[viewModel.selectedTab] {
                Text(String(
                    format: NSLocalizedString("Generated %@ at %@", comment: "LoopInsights trends generated at"),
                    Self.dateMediumFormatter.string(from: generatedAt),
                    Self.timeShortFormatter.string(from: generatedAt)
                ))
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.top, 8)
    }

    private func statsChipsRow(stats: LoopInsightsAggregatedStats) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statsChip(
                    label: NSLocalizedString("TIR", comment: "LoopInsights trends TIR chip"),
                    value: String(format: "%.0f%%", stats.glucoseStats.timeInRange),
                    color: tirColor(stats.glucoseStats.timeInRange)
                )
                statsChip(
                    label: NSLocalizedString("Avg", comment: "LoopInsights trends avg chip"),
                    value: String(format: "%.0f", stats.glucoseStats.averageGlucose),
                    color: avgColor(stats.glucoseStats.averageGlucose)
                )
                statsChip(
                    label: NSLocalizedString("Readings", comment: "LoopInsights trends readings chip"),
                    value: "\(stats.glucoseStats.sampleCount)",
                    color: .teal
                )
                statsChip(
                    label: NSLocalizedString("CV", comment: "LoopInsights trends CV chip"),
                    value: String(format: "%.0f%%", stats.glucoseStats.coefficientOfVariation),
                    color: stats.glucoseStats.coefficientOfVariation <= 36 ? .green : .orange
                )
            }
        }
    }

    private func statsChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(color.opacity(0.25))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                    .foregroundColor(.purple.opacity(0.8))
                Text(NSLocalizedString("Summary", comment: "LoopInsights trends summary header"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            Text(summary)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.78))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func highlightsCard(_ highlights: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow.opacity(0.8))
                Text(NSLocalizedString("Highlights", comment: "LoopInsights trends highlights header"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            ForEach(highlights.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{2022}")
                        .foregroundColor(.purple.opacity(0.8))
                    Text(highlights[index])
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.08))
        )
    }

    // MARK: - Stats Content

    private var statsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("Detailed Statistics", comment: "LoopInsights trends stats header"))
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)

                if viewModel.isLoading {
                    loadingView
                } else if let stats = viewModel.statsTabData {
                    // Glucose section
                    statsSectionCard(
                        title: NSLocalizedString("Glucose", comment: "LoopInsights trends stats glucose"),
                        icon: "drop.fill",
                        rows: [
                            (NSLocalizedString("Time in Range (70-180)", comment: ""), String(format: "%.1f%%", stats.glucoseStats.timeInRange)),
                            (NSLocalizedString("Below Range (<70)", comment: ""), String(format: "%.1f%%", stats.glucoseStats.timeBelowRange)),
                            (NSLocalizedString("Above Range (>180)", comment: ""), String(format: "%.1f%%", stats.glucoseStats.timeAboveRange)),
                            (NSLocalizedString("Average Glucose", comment: ""), String(format: "%.0f mg/dL", stats.glucoseStats.averageGlucose)),
                            (NSLocalizedString("GMI (est. A1C)", comment: ""), String(format: "%.1f%%", stats.glucoseStats.gmi)),
                            (NSLocalizedString("Coefficient of Variation", comment: ""), String(format: "%.1f%%", stats.glucoseStats.coefficientOfVariation)),
                            (NSLocalizedString("Std Deviation", comment: ""), String(format: "%.1f mg/dL", stats.glucoseStats.standardDeviation)),
                            (NSLocalizedString("Readings", comment: ""), "\(stats.glucoseStats.sampleCount)")
                        ]
                    )

                    // Insulin section
                    statsSectionCard(
                        title: NSLocalizedString("Insulin", comment: "LoopInsights trends stats insulin"),
                        icon: "syringe.fill",
                        rows: [
                            (NSLocalizedString("Total Daily Dose", comment: ""), String(format: "%.1f U/day", stats.insulinStats.totalDailyDose)),
                            (NSLocalizedString("Basal", comment: ""), String(format: "%.0f%%", stats.insulinStats.basalPercentage)),
                            (NSLocalizedString("Bolus", comment: ""), String(format: "%.0f%%", stats.insulinStats.bolusPercentage)),
                            (NSLocalizedString("Correction Boluses", comment: ""), "\(stats.insulinStats.correctionBolusCount)")
                        ]
                    )

                    // Carb section
                    statsSectionCard(
                        title: NSLocalizedString("Carbs", comment: "LoopInsights trends stats carbs"),
                        icon: "fork.knife",
                        rows: [
                            (NSLocalizedString("Daily Average", comment: ""), String(format: "%.0f g/day", stats.carbStats.averageDailyCarbs)),
                            (NSLocalizedString("Per Meal Average", comment: ""), String(format: "%.0f g", stats.carbStats.averageCarbsPerMeal)),
                            (NSLocalizedString("Meals Logged", comment: ""), "\(stats.carbStats.mealCount)")
                        ]
                    )
                } else {
                    noDataPlaceholder
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .onAppear {
            viewModel.loadStatsIfNeeded(coordinator: coordinator)
        }
    }

    private func statsSectionCard(title: String, icon: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.purple.opacity(0.8))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            ForEach(rows.indices, id: \.self) { index in
                HStack {
                    Text(rows[index].0)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                    Spacer()
                    Text(rows[index].1)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                if index < rows.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.08))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.08))
        )
    }

    // MARK: - Advisor Content

    private var advisorContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.purple.opacity(0.5))

            Text(NSLocalizedString("Chat with your AI Advisor", comment: "LoopInsights trends advisor title"))
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))

            Text(NSLocalizedString("Ask questions about your glucose trends, therapy settings, and get personalized advice.", comment: "LoopInsights trends advisor subtitle"))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: { showingChat = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "message.fill")
                    Text(NSLocalizedString("Open Chat", comment: "LoopInsights trends advisor button"))
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.25, blue: 0.85),
                            Color(red: 0.75, green: 0.20, blue: 0.65)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Shared Components

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 40)
            ProgressView()
                .scaleEffect(1.2)
                .tint(.purple)
            Text(NSLocalizedString("Generating insights...", comment: "LoopInsights trends loading"))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red.opacity(0.8))
            Text(message)
                .font(.caption)
                .foregroundColor(.red.opacity(0.8))
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
    }

    private var noDataPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 40)
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.3))
            Text(NSLocalizedString("Tap refresh to generate insights", comment: "LoopInsights trends no data"))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Color Helpers

    private func tirColor(_ tir: Double) -> Color {
        if tir >= 70 { return .green }
        if tir >= 50 { return .yellow }
        return .red
    }

    private func avgColor(_ avg: Double) -> Color {
        if avg >= 70 && avg <= 180 { return .green }
        if avg >= 60 && avg <= 200 { return .yellow }
        return .red
    }

    // MARK: - Formatters

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private static let dateMediumFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static let timeShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Trends Tab Enum

private enum TrendsTab: String, CaseIterable, Identifiable, Hashable {
    case daily
    case weekly
    case monthly
    case stats
    case advisor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return NSLocalizedString("Daily", comment: "LoopInsights trends tab: daily")
        case .weekly: return NSLocalizedString("Weekly", comment: "LoopInsights trends tab: weekly")
        case .monthly: return NSLocalizedString("Monthly", comment: "LoopInsights trends tab: monthly")
        case .stats: return NSLocalizedString("Stats", comment: "LoopInsights trends tab: stats")
        case .advisor: return NSLocalizedString("Advisor", comment: "LoopInsights trends tab: advisor")
        }
    }

    var icon: String {
        switch self {
        case .daily: return "sun.max"
        case .weekly: return "calendar"
        case .monthly: return "calendar.badge.clock"
        case .stats: return "chart.bar.fill"
        case .advisor: return "bubble.left.and.bubble.right"
        }
    }

    var isTimePeriod: Bool {
        switch self {
        case .daily, .weekly, .monthly: return true
        default: return false
        }
    }

    var analysisPeriod: LoopInsightsAnalysisPeriod? {
        switch self {
        case .daily: return .threeDays
        case .weekly: return .sevenDays
        case .monthly: return .thirtyDays
        default: return nil
        }
    }
}

// MARK: - Trends ViewModel

private final class TrendsViewModel: ObservableObject {

    @Published var selectedTab: TrendsTab = .daily
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Cached results per tab
    var cachedSummaries: [TrendsTab: String] = [:]
    var cachedHighlights: [TrendsTab: [String]] = [:]
    var cachedStats: [TrendsTab: LoopInsightsAggregatedStats] = [:]
    var cachedGeneratedAt: [TrendsTab: Date] = [:]
    var statsTabData: LoopInsightsAggregatedStats?

    // MARK: - Load

    func loadIfNeeded(coordinator: LoopInsights_Coordinator) {
        guard selectedTab.isTimePeriod else { return }
        guard cachedSummaries[selectedTab] == nil else { return }
        refresh(coordinator: coordinator)
    }

    func loadStatsIfNeeded(coordinator: LoopInsights_Coordinator) {
        guard statsTabData == nil else { return }
        loadStats(coordinator: coordinator)
    }

    func refresh(coordinator: LoopInsights_Coordinator) {
        guard selectedTab.isTimePeriod, let period = selectedTab.analysisPeriod else { return }

        isLoading = true
        errorMessage = nil
        let currentTab = selectedTab

        Task { @MainActor in
            do {
                // Fetch aggregated stats
                let stats = try await coordinator.dataAggregator.aggregateData(period: period)
                cachedStats[currentTab] = stats
                cachedGeneratedAt[currentTab] = Date()

                // Build a summary prompt
                let therapyContext = LoopInsights_ChatViewModel.buildTherapyContext(
                    snapshot: try? coordinator.captureCurrentSnapshot(),
                    stats: stats
                )

                let systemPrompt = buildTrendsSystemPrompt()
                let userPrompt = buildTrendsUserPrompt(
                    periodName: currentTab.label,
                    therapyContext: therapyContext
                )

                let response = try await LoopInsights_AIServiceAdapter.shared.sendPrompt(
                    systemPrompt,
                    userPrompt: userPrompt
                )

                // Parse response into summary + highlights
                let parsed = parseTrendsResponse(response)
                cachedSummaries[currentTab] = parsed.summary
                cachedHighlights[currentTab] = parsed.highlights

                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadStats(coordinator: LoopInsights_Coordinator) {
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let stats = try await coordinator.dataAggregator.aggregateData(
                    period: .sevenDays
                )
                statsTabData = stats
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Prompt Building

    private func buildTrendsSystemPrompt() -> String {
        let personality = LoopInsights_FeatureFlags.aiPersonality

        return """
        You are an expert diabetes advisor providing a trends summary for a Loop AID user. \
        \(personality.promptInstruction)

        RESPONSE FORMAT — you MUST use exactly this structure:

        SUMMARY:
        Write 2-4 sentences summarizing the user's glucose control for this period. \
        Mention TIR, average glucose, and any notable patterns. Use **bold** for key numbers.

        HIGHLIGHTS:
        - First key observation (one sentence)
        - Second key observation (one sentence)
        - Third key observation (one sentence)

        Keep it concise and actionable. Reference actual numbers from the data.
        """
    }

    private func buildTrendsUserPrompt(periodName: String, therapyContext: String) -> String {
        return """
        Generate a \(periodName) trends summary for this user's diabetes data:

        \(therapyContext)
        """
    }

    // MARK: - Response Parsing

    private func parseTrendsResponse(_ response: String) -> (summary: String, highlights: [String]) {
        var summary = ""
        var highlights: [String] = []

        let lines = response.components(separatedBy: "\n")
        var section: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.uppercased().hasPrefix("SUMMARY") {
                section = "summary"
                continue
            }
            if trimmed.uppercased().hasPrefix("HIGHLIGHTS") || trimmed.uppercased().hasPrefix("HIGHLIGHT") {
                section = "highlights"
                continue
            }

            if section == "summary" && !trimmed.isEmpty {
                if !summary.isEmpty { summary += " " }
                summary += trimmed
            }

            if section == "highlights" && trimmed.hasPrefix("-") {
                let bullet = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !bullet.isEmpty {
                    highlights.append(bullet)
                }
            }
        }

        // Fallback: if parsing failed, treat entire response as summary
        if summary.isEmpty && highlights.isEmpty {
            summary = response
        }

        return (summary, highlights)
    }
}
