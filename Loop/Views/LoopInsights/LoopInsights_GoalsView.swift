//
//  LoopInsights_GoalsView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Combined Goals, Pattern Discovery, and Reflections view.
/// Light/Dark mode agnostic — adapts to the system appearance.
/// Presented as sheet from Dashboard.
struct LoopInsights_GoalsView: View {

    let coordinator: LoopInsights_Coordinator
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = GoalsViewModel()

    var body: some View {
        List {
            goalsSection
            patternsSection
            reflectionsSection
        }
        .navigationTitle(NSLocalizedString("Goals & Patterns", comment: "LoopInsights goals view title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { viewModel.generateReport(coordinator: coordinator) }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.isGeneratingReport)
            }
        }
        .onAppear {
            viewModel.loadData(coordinator: coordinator)
        }
        .sheet(isPresented: $viewModel.showingShareSheet) {
            if let url = viewModel.reportURL {
                LoopInsights_ActivityViewRepresentable(activityItems: [url])
            }
        }
        .sheet(isPresented: $viewModel.showingAddGoal) {
            NavigationView {
                addGoalSheet
            }
        }
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        Section(header: HStack {
            Image(systemName: "target")
            Text(NSLocalizedString("Goals", comment: "LoopInsights goals section header"))
            Spacer()
            Button(action: { viewModel.showingAddGoal = true }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }) {
            if viewModel.goals.isEmpty {
                emptyGoalsPlaceholder
            } else {
                ForEach(viewModel.goals) { goal in
                    goalRow(goal)
                }
            }
        }
    }

    private var emptyGoalsPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text(NSLocalizedString("No goals set yet", comment: "LoopInsights goals empty placeholder"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(NSLocalizedString("Tap + to set a clinical goal like TIR > 80%", comment: "LoopInsights goals empty hint"))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func goalRow(_ goal: LoopInsightsGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: goal.type.icon)
                    .foregroundColor(goal.achieved ? .green : .accentColor)
                    .frame(width: 20)

                Text(goal.displayLabel)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if goal.achieved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Text("\(String(format: "%.1f", goal.currentValue))\(goal.type.unit)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }

                Button(action: { viewModel.deleteGoal(id: goal.id) }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(goal.achieved ? Color.green : Color.accentColor)
                        .frame(width: geo.size.width * goal.progress, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(NSLocalizedString("Target:", comment: "LoopInsights goal target label"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if goal.type.lowerIsBetter {
                    Text("\u{2264} \(String(format: "%.1f", goal.targetValue))\(goal.type.unit)")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("\u{2265} \(String(format: "%.1f", goal.targetValue))\(goal.type.unit)")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let tip = viewModel.goalTips[goal.id] {
                    Text(tip)
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Patterns Section

    private var patternsSection: some View {
        Section(header: HStack {
            Image(systemName: "waveform.path.ecg")
            Text(NSLocalizedString("Pattern Discovery", comment: "LoopInsights patterns section header"))
            Spacer()
            Button(action: { viewModel.refreshPatterns(coordinator: coordinator) }) {
                if viewModel.isLoadingPatterns {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoadingPatterns)
        }) {
            if viewModel.isLoadingPatterns && viewModel.patterns.isEmpty {
                loadingRow(NSLocalizedString("Discovering patterns...", comment: "LoopInsights patterns loading"))
            } else if viewModel.patterns.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(NSLocalizedString("Tap refresh to discover patterns", comment: "LoopInsights patterns empty"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(viewModel.patterns) { pattern in
                    patternRow(pattern)
                }
            }

            if let error = viewModel.patternError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func patternRow(_ pattern: LoopInsightsCachedPattern) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pattern.type)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(pattern.severity.capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(severityColor(pattern.severity))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(severityColor(pattern.severity).opacity(0.15))
                    .cornerRadius(6)
            }

            Text(pattern.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Reflections Section

    private var reflectionsSection: some View {
        Section(header: HStack {
            Image(systemName: "note.text")
            Text(NSLocalizedString("Reflections", comment: "LoopInsights reflections section header"))
        }) {
            // Add reflection input
            addReflectionRow

            // Recent reflections
            ForEach(viewModel.reflections.prefix(10)) { reflection in
                reflectionRow(reflection)
            }
        }
    }

    private var addReflectionRow: some View {
        VStack(spacing: 10) {
            TextField(
                NSLocalizedString("How's your day going?", comment: "LoopInsights reflection placeholder"),
                text: $viewModel.reflectionText
            )
            .font(.subheadline)

            HStack(spacing: 8) {
                // Mood picker
                ForEach(LoopInsightsMoodTag.allCases) { mood in
                    Button(action: { viewModel.selectedMood = mood }) {
                        Text(mood.emoji)
                            .font(.title3)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(viewModel.selectedMood == mood
                                        ? Color.accentColor.opacity(0.3)
                                        : Color.secondary.opacity(0.1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: { viewModel.addReflection() }) {
                    Text(NSLocalizedString("Add", comment: "LoopInsights add reflection button"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(viewModel.reflectionText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.accentColor.opacity(0.4)
                                    : Color.accentColor
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.reflectionText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func reflectionRow(_ reflection: LoopInsightsReflection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(reflection.mood.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(reflection.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(Self.reflectionDateFormatter.string(from: reflection.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(reflection.mood.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(moodColor(reflection.mood))
                }
            }

            Spacer()

            Button(action: { viewModel.deleteReflection(id: reflection.id) }) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Add Goal Sheet

    private var addGoalSheet: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("Add Goal", comment: "LoopInsights add goal title"))
                .font(.headline)

            Picker(NSLocalizedString("Goal Type", comment: "LoopInsights goal type picker"), selection: $viewModel.newGoalType) {
                ForEach(LoopInsightsGoalType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.newGoalType) { newType in
                viewModel.newGoalTarget = newType.defaultTarget
            }

            if viewModel.newGoalType == .custom {
                TextField(
                    NSLocalizedString("Goal name", comment: "LoopInsights custom goal name"),
                    text: $viewModel.newGoalCustomLabel
                )
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text(NSLocalizedString("Target:", comment: "LoopInsights goal target"))
                    .foregroundColor(.secondary)
                TextField(
                    "",
                    value: $viewModel.newGoalTarget,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 100)
                Text(viewModel.newGoalType.unit)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button(NSLocalizedString("Cancel", comment: "Cancel")) {
                    viewModel.showingAddGoal = false
                }
                Spacer()
                Button(NSLocalizedString("Save", comment: "Save goal")) {
                    viewModel.saveNewGoal()
                }
                .disabled(viewModel.newGoalTarget <= 0)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
        .navigationTitle(NSLocalizedString("New Goal", comment: "LoopInsights new goal nav title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Shared Components

    private func loadingRow(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(1.1)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Color Helpers

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .yellow
        }
    }

    private func moodColor(_ mood: LoopInsightsMoodTag) -> Color {
        switch mood {
        case .great: return .green
        case .good: return .blue
        case .okay: return .orange
        case .tough: return .red
        }
    }

    // MARK: - Formatters

    private static let reflectionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Goals ViewModel

private final class GoalsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var goals: [LoopInsightsGoal] = []
    @Published var patterns: [LoopInsightsCachedPattern] = []
    @Published var reflections: [LoopInsightsReflection] = []

    @Published var goalTips: [UUID: String] = [:]

    @Published var isLoadingPatterns = false
    @Published var patternError: String?

    @Published var reflectionText = ""
    @Published var selectedMood: LoopInsightsMoodTag = .good

    @Published var showingAddGoal = false
    @Published var newGoalType: LoopInsightsGoalType = .tirTarget
    @Published var newGoalTarget: Double = 80
    @Published var newGoalCustomLabel = ""

    @Published var showingShareSheet = false
    @Published var isGeneratingReport = false
    @Published var reportURL: URL?

    private let goalStore = LoopInsights_GoalStore.shared

    // MARK: - Load

    func loadData(coordinator: LoopInsights_Coordinator) {
        goals = goalStore.allGoals
        reflections = goalStore.allReflections
        patterns = goalStore.validPatterns
        goalStore.pruneExpiredPatterns()

        // Update goal current values from live data
        updateGoalCurrentValues(coordinator: coordinator)
    }

    private func updateGoalCurrentValues(coordinator: LoopInsights_Coordinator) {
        Task { @MainActor in
            let stats: LoopInsightsAggregatedStats
            do {
                stats = try await coordinator.dataAggregator.aggregateData(
                    period: LoopInsights_FeatureFlags.analysisPeriod
                )
            } catch {
                LoopInsights_FeatureFlags.log.error("Goals: failed to aggregate data for goal updates: \(error)")
                return
            }

            for goal in goals {
                let current: Double
                switch goal.type {
                case .tirTarget:
                    current = stats.glucoseStats.timeInRange
                case .a1cTarget:
                    current = stats.glucoseStats.gmi
                case .hypoReduction:
                    current = stats.glucoseStats.timeBelowRange
                case .custom:
                    continue
                }
                goalStore.updateGoal(id: goal.id, currentValue: current)
            }
            goals = goalStore.allGoals
        }
    }

    // MARK: - Goals Actions

    func saveNewGoal() {
        let target: Double
        if newGoalType == .custom {
            target = newGoalTarget
        } else {
            target = newGoalTarget > 0 ? newGoalTarget : newGoalType.defaultTarget
        }
        goalStore.addGoal(
            type: newGoalType,
            targetValue: target,
            customLabel: newGoalType == .custom ? newGoalCustomLabel : nil
        )
        goals = goalStore.allGoals
        showingAddGoal = false
        // Reset form
        newGoalType = .tirTarget
        newGoalTarget = 80
        newGoalCustomLabel = ""
    }

    func deleteGoal(id: UUID) {
        goalStore.deleteGoal(id: id)
        goals = goalStore.allGoals
        goalTips.removeValue(forKey: id)
    }

    // MARK: - Pattern Discovery

    func refreshPatterns(coordinator: LoopInsights_Coordinator) {
        guard !isLoadingPatterns else { return }
        isLoadingPatterns = true
        patternError = nil

        Task { @MainActor in
            do {
                let stats = try await coordinator.dataAggregator.aggregateData(period: .thirtyDays)
                var snapshot: LoopInsightsTherapySnapshot?
                do { snapshot = try coordinator.captureCurrentSnapshot() }
                catch { LoopInsights_FeatureFlags.log.error("Goals: failed to capture snapshot for patterns: \(error)") }
                let context = LoopInsights_ChatViewModel.buildTherapyContext(
                    snapshot: snapshot,
                    stats: stats
                )

                let goalsContext = buildGoalsContext()
                let systemPrompt = buildPatternSystemPrompt()
                let userPrompt = buildPatternUserPrompt(therapyContext: context, goalsContext: goalsContext)

                let response = try await LoopInsights_AIServiceAdapter.shared.sendPrompt(
                    systemPrompt,
                    userPrompt: userPrompt
                )

                let parsed = parsePatternResponse(response)
                goalStore.cachePatterns(parsed.patterns)
                patterns = parsed.patterns
                goalTips = parsed.tips

                isLoadingPatterns = false
            } catch {
                patternError = error.localizedDescription
                isLoadingPatterns = false
            }
        }
    }

    // MARK: - Reflections Actions

    func addReflection() {
        let text = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        goalStore.addReflection(text: text, mood: selectedMood)
        reflections = goalStore.allReflections
        reflectionText = ""
        selectedMood = .good
    }

    func deleteReflection(id: UUID) {
        goalStore.deleteReflection(id: id)
        reflections = goalStore.allReflections
    }

    // MARK: - Report Generation

    func generateReport(coordinator: LoopInsights_Coordinator) {
        guard !isGeneratingReport else { return }
        isGeneratingReport = true

        Task { @MainActor in
            var stats: LoopInsightsAggregatedStats?
            do { stats = try await coordinator.dataAggregator.aggregateData(period: LoopInsights_FeatureFlags.analysisPeriod) }
            catch { LoopInsights_FeatureFlags.log.error("Goals: failed to aggregate data for report: \(error)") }

            let html = LoopInsights_ReportGenerator.generateHTML(
                stats: stats,
                goals: goals,
                patterns: patterns,
                reflections: reflections
            )

            if let url = await LoopInsights_ReportGenerator.generatePDF(from: html) {
                reportURL = url
                showingShareSheet = true
            }
            isGeneratingReport = false
        }
    }

    // MARK: - Prompt Building

    private func buildPatternSystemPrompt() -> String {
        let personality = LoopInsights_FeatureFlags.aiPersonality

        return """
        You are an expert diabetes advisor analyzing 30 days of Loop AID data to discover patterns. \
        \(personality.promptInstruction)

        RESPONSE FORMAT — you MUST use exactly this structure:

        PATTERNS:
        [TYPE] Pattern title
        Description of the pattern (1-2 sentences). Include specific numbers.
        SEVERITY: high/medium/low

        [TYPE] Another pattern title
        Description.
        SEVERITY: high/medium/low

        (List 3-6 patterns. Types can be: Overnight, Dawn, Post-Meal, Exercise, Weekend, Weekday, \
        Sick Day, Negative Basal, Variability, Insulin Resistance, or any descriptive type.)

        TIPS:
        GOAL_INDEX:0 One-line actionable tip for the first goal
        GOAL_INDEX:1 One-line actionable tip for the second goal
        (One tip per active goal. Skip if no goals.)

        SPECIAL PATTERN DETECTION:
        - Sick day flags: Look for sustained glucose >250 mg/dL for 6+ hours with unusually high \
        insulin requirements. If hourly averages show extended periods well above 250, flag it.
        - Negative basal: Periods where basal delivery is near-zero or suspended for extended periods \
        indicating overcorrection. Check if basal % is unusually low or insulin stats suggest \
        frequent suspensions.
        - Weekend vs weekday: Compare timing patterns in carb data and glucose patterns.
        - Exercise correlation: Look for post-activity lows followed by rebounds.
        - Goal-aware tips: Reference the user's active goals in suggestions.
        """
    }

    private func buildPatternUserPrompt(therapyContext: String, goalsContext: String) -> String {
        return """
        Analyze this 30-day data for patterns and provide actionable insights:

        \(therapyContext)

        \(goalsContext)
        """
    }

    private func buildGoalsContext() -> String {
        guard !goals.isEmpty else { return "" }

        var context = "USER'S ACTIVE GOALS:\n"
        for (index, goal) in goals.enumerated() {
            let status = goal.achieved ? "ACHIEVED" : "In Progress"
            context += "  Goal \(index): \(goal.displayLabel) — Target: \(String(format: "%.1f", goal.targetValue))\(goal.type.unit), Current: \(String(format: "%.1f", goal.currentValue))\(goal.type.unit) [\(status)]\n"
        }
        return context
    }

    // MARK: - Response Parsing

    private func parsePatternResponse(_ response: String) -> (patterns: [LoopInsightsCachedPattern], tips: [UUID: String]) {
        var patterns: [LoopInsightsCachedPattern] = []
        var tips: [UUID: String] = [:]

        let lines = response.components(separatedBy: "\n")
        var section: String?
        var currentType: String?
        var currentDesc = ""
        var currentSeverity = "medium"

        func flushPattern() {
            if let type = currentType, !currentDesc.isEmpty {
                patterns.append(LoopInsightsCachedPattern(
                    type: type,
                    description: currentDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                    severity: currentSeverity
                ))
            }
            currentType = nil
            currentDesc = ""
            currentSeverity = "medium"
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.uppercased().hasPrefix("PATTERNS") {
                section = "patterns"
                continue
            }
            if trimmed.uppercased().hasPrefix("TIPS") {
                flushPattern()
                section = "tips"
                continue
            }

            if section == "patterns" {
                // Check for [TYPE] pattern
                if trimmed.hasPrefix("[") {
                    flushPattern()
                    if let endBracket = trimmed.firstIndex(of: "]") {
                        let type = String(trimmed[trimmed.index(after: trimmed.startIndex)..<endBracket])
                        let title = String(trimmed[trimmed.index(after: endBracket)...]).trimmingCharacters(in: .whitespaces)
                        currentType = title.isEmpty ? type : title
                    }
                } else if trimmed.uppercased().hasPrefix("SEVERITY:") {
                    currentSeverity = trimmed.replacingOccurrences(of: "SEVERITY:", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespaces).lowercased()
                } else if !trimmed.isEmpty, currentType != nil {
                    if !currentDesc.isEmpty { currentDesc += " " }
                    currentDesc += trimmed
                }
            }

            if section == "tips" {
                if trimmed.hasPrefix("GOAL_INDEX:") {
                    let rest = trimmed.replacingOccurrences(of: "GOAL_INDEX:", with: "")
                    if let spaceIndex = rest.firstIndex(of: " ") {
                        let indexStr = String(rest[rest.startIndex..<spaceIndex])
                        let tip = String(rest[rest.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespaces)
                        if let goalIndex = Int(indexStr), goalIndex < goals.count, !tip.isEmpty {
                            tips[goals[goalIndex].id] = tip
                        }
                    }
                }
            }
        }
        flushPattern()

        // Fallback: if parsing failed entirely, create a single pattern from the response
        if patterns.isEmpty && !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            patterns.append(LoopInsightsCachedPattern(
                type: "Analysis",
                description: String(response.prefix(300)),
                severity: "medium"
            ))
        }

        return (patterns, tips)
    }
}
