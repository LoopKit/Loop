//
//  LogbookScreen.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

private typealias P = LoopDesign.Palette

/// One row of the logbook.
struct LogEntry: Identifiable {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case bolus = "Bolus"
        case basal = "Basal"
        case carbs = "Carbs"
        case loop = "Loop"
        var id: String { rawValue }
    }

    enum Action {
        case deleteCarbs(StoredCarbEntry)
        case deleteDose(DoseEntry)
    }

    let id: String
    let date: Date
    let title: String
    let subtitle: String
    let amount: String
    let amountColor: Color
    let detail: String
    let icon: String
    let iconFill: Color
    let filters: Set<Filter>
    var basalChanges: [BasalSegment] = []
    var edit: StoredCarbEntry? = nil
    var delete: Action? = nil

    func matches(_ filter: Filter) -> Bool {
        filter == .all || filters.contains(filter)
    }
}

struct LogDay: Identifiable {
    let day: Date
    let entries: [LogEntry]
    let insulin: Double
    let carbs: Double
    var id: Date { day }
}

@MainActor
final class LogbookModel: ObservableObject {
    @Published private(set) var days: [LogDay] = []
    @Published private(set) var loaded = false
    @Published var filter: LogEntry.Filter = .all
    @Published var error: String?
    @Published private(set) var loadError: String?
    @Published private(set) var carbEditingAllowed = false

    let provider: LoopHistoryProvider
    private var loadTask: Task<Void, Never>?

    init(provider: LoopHistoryProvider) {
        self.provider = provider
    }

    func reload() {
        loadTask?.cancel()
        carbEditingAllowed = provider.allowsCarbEditing
        loadError = nil
        loadTask = Task {
            do {
                let result = try await Self.build(provider: provider)
                guard !Task.isCancelled else { return }
                self.days = result
            } catch {
                guard !Task.isCancelled else { return }
                self.days = []
                self.loadError = error.localizedDescription
            }
            self.loaded = true
        }
    }

    func perform(_ action: LogEntry.Action) {
        Task {
            do {
                switch action {
                case .deleteCarbs(let entry):
                    guard provider.allowsCarbEditing else { return }
                    try await provider.delete(carb: entry)
                case .deleteDose(let dose): try await provider.delete(dose: dose)
                }
                reload()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: Building rows

    private static func build(provider: LoopHistoryProvider, now: Date = Date()) async throws -> [LogDay] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: provider.localHistoryStart.addingTimeInterval(86400))
        let interval = DateInterval(start: start, end: now)
        async let historyFetch = provider.dayHistory(interval, includeOnBoard: false)
        async let pumpFetch = provider.pumpEvents(since: start)
        let history = try await historyFetch
        let pumpEvents = try await pumpFetch
        let unit = provider.unitStyle
        let canDelete = FeatureFlags.entryDeletionEnabled

        return LoopHistoryMath.days(in: interval).reversed().map { day in
            var entries: [LogEntry] = []
            let inDay: (Date) -> Bool = { $0 >= day.start && $0 < day.end }
            let carbsToday = history.carbs.filter { inDay($0.date) }

            for bolus in history.boluses where inDay(bolus.date) {
                let glucose = glucoseContext(at: bolus.date, history.glucose, unit: unit, withTrend: bolus.automatic)
                var parts = [bolus.automatic ? "Loop" : "Manual"]
                if !bolus.automatic, let meal = carbsToday.first(where: { abs($0.date.timeIntervalSince(bolus.date)) <= 15 * 60 }) {
                    parts.append(LoopFormat.grams(meal.grams))
                }
                if let glucose { parts.append(glucose) }
                if bolus.manuallyEntered { parts.append("logged") }
                entries.append(LogEntry(
                    id: "bolus-\(bolus.id)", date: bolus.date,
                    title: bolus.automatic ? "Automatic bolus" : "Bolus",
                    subtitle: parts.joined(separator: " · "),
                    amount: LoopFormat.doseUnits(bolus.units), amountColor: P.insulinInk,
                    detail: LoopFormat.time(bolus.date),
                    icon: "plus", iconFill: P.insulin,
                    filters: bolus.automatic ? [.bolus, .loop] : [.bolus],
                    delete: canDelete && bolus.manuallyEntered ? bolus.dose.map { .deleteDose($0) } : nil))
            }

            for carb in carbsToday {
                var parts = [carb.createdByLoop ? "Manual" : "Health"]
                if let food = carb.foodType, !food.isEmpty { parts.append(food) }
                if let hours = carb.absorptionHours { parts.append("absorbs over \(hours.formatted(.number.precision(.fractionLength(0...1)))) h") }
                let editable = carb.createdByLoop && provider.allowsCarbEditing ? carb.entry : nil
                entries.append(LogEntry(
                    id: "carbs-\(carb.id)", date: carb.date,
                    title: "Carbs", subtitle: parts.joined(separator: " · "),
                    amount: LoopFormat.grams(carb.grams), amountColor: P.carbsInk,
                    detail: LoopFormat.time(carb.date),
                    icon: "fork.knife", iconFill: P.carbs, filters: [.carbs],
                    edit: editable,
                    delete: canDelete ? editable.map { .deleteCarbs($0) } : nil))
            }

            let segments = history.basal.compactMap { $0.clamped(to: day) }
            let automaticTemps = segments.filter { $0.kind == .temp && $0.automatic }
            if let latest = automaticTemps.last {
                let net = automaticTemps.reduce(0) { $0 + $1.netUnits }
                let count = automaticTemps.count
                entries.append(LogEntry(
                    id: "basal-\(day.start.timeIntervalSince1970)", date: latest.start,
                    title: "Basal adjustments",
                    subtitle: "Loop · \(count) change\(count == 1 ? "" : "s") · tap to list",
                    amount: LoopFormat.signed(net, decimals: 1) + " U", amountColor: P.insulinInk,
                    detail: "vs plan",
                    icon: "waveform.path.ecg", iconFill: P.basalEdge, filters: [.basal, .loop],
                    basalChanges: automaticTemps.reversed()))
            }
            for temp in segments where temp.kind == .temp && !temp.automatic {
                entries.append(LogEntry(
                    id: "temp-\(temp.start.timeIntervalSince1970)", date: temp.start,
                    title: "Temp basal",
                    subtitle: "Manual · \(describe(temp))",
                    amount: LoopFormat.rate(temp.rate), amountColor: P.insulinInk,
                    detail: LoopFormat.time(temp.start),
                    icon: "waveform.path.ecg", iconFill: P.basalEdge, filters: [.basal]))
            }
            for suspend in segments where suspend.kind == .suspended {
                var parts = [suspend.automatic ? "Loop" : "Manual", LoopFormat.duration(suspend.end.timeIntervalSince(suspend.start))]
                if let glucose = glucoseContext(at: suspend.start, history.glucose, unit: unit, withTrend: false) { parts.append(glucose) }
                entries.append(LogEntry(
                    id: "suspend-\(suspend.start.timeIntervalSince1970)", date: suspend.start,
                    title: "Basal suspended", subtitle: parts.joined(separator: " · "),
                    amount: "0 U/h", amountColor: P.ink,
                    detail: LoopFormat.time(suspend.start),
                    icon: "pause.fill", iconFill: P.statusWarning,
                    filters: suspend.automatic ? [.basal, .loop] : [.basal]))
            }

            for event in pumpEvents where inDay(event.date) {
                let title: String
                switch event.kind {
                case .siteChange(let name): title = name
                case .alarm(let name): title = name
                case .resume: title = "Basal resumed"
                }
                entries.append(LogEntry(
                    id: "pump-\(event.id)", date: event.date,
                    title: title, subtitle: "Pump",
                    amount: "", amountColor: P.ink,
                    detail: LoopFormat.time(event.date),
                    icon: "circle.dashed", iconFill: P.inkMuted.opacity(0.5), filters: []))
            }

            let insulin = segments.reduce(0) { $0 + $1.units } + history.boluses.filter { inDay($0.date) }.reduce(0) { $0 + $1.units }
            return LogDay(day: day.start, entries: entries.sorted { $0.date > $1.date }, insulin: insulin,
                          carbs: carbsToday.reduce(0) { $0 + $1.grams })
        }
    }

    static func describe(_ segment: BasalSegment) -> String {
        var text = "\(LoopFormat.rate(segment.rate)) for \(LoopFormat.duration(segment.end.timeIntervalSince(segment.start)))"
        if let scheduled = segment.scheduledRate {
            text += String(format: " (scheduled %.2f)", scheduled)
        }
        return text
    }

    /// "glucose 7.5", or "glucose 11.0 rising" for Loop's own doses.
    private static func glucoseContext(at date: Date, _ readings: [GlucosePoint], unit: GlucoseUnitStyle, withTrend: Bool) -> String? {
        guard let reading = readings.last(where: { $0.date <= date.addingTimeInterval(60) }), date.timeIntervalSince(reading.date) <= 10 * 60 else {
            return nil
        }
        var text = "glucose \(unit.format(reading.mgdl))"
        if withTrend, let earlier = readings.last(where: { $0.date <= reading.date.addingTimeInterval(-14 * 60) }),
           reading.date.timeIntervalSince(earlier.date) <= 20 * 60 {
            let perFifteen = (reading.mgdl - earlier.mgdl) / reading.date.timeIntervalSince(earlier.date) * 900
            if perFifteen > 10 { text += " rising" } else if perFifteen < -10 { text += " falling" }
        }
        return text
    }
}

// MARK: - Screen

struct LogbookView: View {
    @StateObject private var model: LogbookModel
    @State private var path: [Route] = []
    private let deviceManager: DeviceDataManager

    enum Route: Hashable {
        case basal(String)
        case editCarbs(CarbEditRoute)
    }

    struct CarbEditRoute: Hashable {
        let id = UUID()
        let entry: StoredCarbEntry

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    init(provider: LoopHistoryProvider, deviceManager: DeviceDataManager) {
        _model = StateObject(wrappedValue: LogbookModel(provider: provider))
        self.deviceManager = deviceManager
    }

    private var visibleDays: [LogDay] {
        model.days.map { day in
            LogDay(day: day.day, entries: day.entries.filter { $0.matches(model.filter) }, insulin: day.insulin, carbs: day.carbs)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    chips
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let error = model.loadError {
                    Text("Couldn't load Logbook: \(error)").foregroundStyle(P.criticalInk)
                    Button("Retry") { model.reload() }
                } else if model.loaded && model.days.allSatisfy({ $0.entries.isEmpty }) {
                    Text("Nothing logged in the last 7 days.")
                        .foregroundStyle(P.inkMuted)
                }
                ForEach(visibleDays) { day in
                    Section {
                        if day.entries.isEmpty {
                            Text(model.filter != .all ? "Nothing to show for this filter" : day.insulin > 0 ? "Scheduled basal only" : "Nothing logged")
                                .font(LoopDesign.Typeface.footnote)
                                .foregroundStyle(P.inkMuted)
                        }
                        ForEach(day.entries) { entry in
                            row(entry)
                        }
                    } header: {
                        dayHeader(day)
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    Text("Loop keeps the last 7 days on this phone. Older doses and carbs are in Apple Health and on the Trends tab.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(P.surface)
            .navigationTitle("Logbook")
            .refreshable { model.reload() }
            .overlay {
                if !model.loaded { ProgressView() }
            }
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
        }
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .LoopDataUpdated).debounce(for: .seconds(2), scheduler: RunLoop.main)) { _ in
            model.reload()
        }
        .alert("Couldn't delete", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LoopDesign.Space.s2) {
                ForEach(LogEntry.Filter.allCases) { filter in
                    Button {
                        model.filter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(LoopDesign.Typeface.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(model.filter == filter ? Color(uiColor: .systemBackground) : P.ink)
                            .background(model.filter == filter ? P.ink : P.surfaceSunken, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.filter == filter ? .isSelected : [])
                }
            }
            .padding(.vertical, LoopDesign.Space.s1)
        }
    }

    private func dayHeader(_ day: LogDay) -> some View {
        let calendar = Calendar.current
        let prefix = calendar.isDateInToday(day.day) ? "Today · " : calendar.isDateInYesterday(day.day) ? "Yesterday · " : ""
        return HStack(alignment: .firstTextBaseline) {
            Text(prefix + LoopFormat.weekdayDay(day.day))
                .font(LoopDesign.Typeface.headline)
                .foregroundStyle(P.ink)
            Spacer()
            Text(LoopFormat.totalUnits(day.insulin)).foregroundStyle(P.insulinInk)
            Text("·").foregroundStyle(P.inkMuted)
            Text(LoopFormat.grams(day.carbs)).foregroundStyle(P.carbsInk)
        }
        .font(LoopDesign.Typeface.footnote)
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func row(_ entry: LogEntry) -> some View {
        let content = HStack(spacing: LoopDesign.Space.s3) {
            IconTile(systemName: entry.icon, fill: entry.iconFill)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(LoopDesign.Typeface.body)
                    .foregroundStyle(P.ink)
                Text(entry.subtitle)
                    .font(LoopDesign.Typeface.footnote)
                    .foregroundStyle(P.inkMuted)
            }
            Spacer(minLength: LoopDesign.Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                if !entry.amount.isEmpty {
                    Text(entry.amount)
                        .font(LoopDesign.Typeface.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(entry.amountColor)
                }
                Text(entry.detail)
                    .font(LoopDesign.Typeface.footnote)
                    .foregroundStyle(P.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)

        if !entry.basalChanges.isEmpty {
            NavigationLink(value: Route.basal(entry.id)) { content }
        } else {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if let action = entry.delete, canPerform(action) {
                        Button(role: .destructive) { model.perform(action) } label: { Label("Delete", systemImage: "trash") }
                    }
                    if let carb = entry.edit, model.carbEditingAllowed {
                        Button {
                            guard model.provider.allowsCarbEditing else { return }
                            path.append(.editCarbs(CarbEditRoute(entry: carb)))
                        } label: { Label("Edit", systemImage: "pencil") }
                            .tint(P.accent)
                    }
                }
        }
    }

    private func canPerform(_ action: LogEntry.Action) -> Bool {
        switch action {
        case .deleteCarbs: return model.carbEditingAllowed
        case .deleteDose: return true
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .basal(let id):
            if let entry = model.days.flatMap(\.entries).first(where: { $0.id == id }) {
                BasalChangesList(changes: entry.basalChanges)
            }
        case .editCarbs(let route):
            LogbookCarbEditor(entry: route.entry, deviceManager: deviceManager, provider: model.provider) {
                path.removeAll()
                model.reload()
            }
        }
    }
}

/// Own the draft independently of rows that refresh while the editor or its bolus screen is open.
private struct LogbookCarbEditor: View {
    @StateObject private var viewModel: CarbEntryViewModel
    let deviceManager: DeviceDataManager
    let provider: LoopHistoryProvider
    let dismiss: () -> Void

    init(entry: StoredCarbEntry, deviceManager: DeviceDataManager, provider: LoopHistoryProvider, dismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: provider.carbEntryViewModel(editing: entry))
        self.deviceManager = deviceManager
        self.provider = provider
        self.dismiss = dismiss
    }

    var body: some View {
        CarbEntryView(viewModel: viewModel)
            .environmentObject(deviceManager.displayGlucosePreference)
            .environment(\.dismissAction, dismiss)
            .navigationTitle("Edit Carb Entry")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if !provider.allowsCarbEditing { dismiss() } }
            // Loop posts this from its data queue; SwiftUI faults on publishers that emit off the main thread.
            .onReceive(NotificationCenter.default.publisher(for: .LoopDataUpdated).receive(on: RunLoop.main)) { _ in
                if !provider.allowsCarbEditing { dismiss() }
            }
    }
}

/// Every basal change Loop made in a day.
struct BasalChangesList: View {
    let changes: [BasalSegment]

    var body: some View {
        List(Array(changes.enumerated()), id: \.offset) { _, change in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LoopFormat.time(change.start))
                        .font(LoopDesign.Typeface.body)
                    Text(LogbookModel.describe(change))
                        .font(LoopDesign.Typeface.footnote)
                        .foregroundStyle(P.inkMuted)
                }
                Spacer()
                Text(LoopFormat.signed(change.netUnits) + " U")
                    .font(LoopDesign.Typeface.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(P.insulinInk)
            }
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("Basal adjustments")
        .navigationBarTitleDisplayMode(.inline)
    }
}
