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

        var title: String {
            switch self {
            case .all: return NSLocalizedString("All", comment: "Logbook filter chip: show every entry")
            case .bolus: return NSLocalizedString("Bolus", comment: "Logbook filter chip: show only boluses")
            case .basal: return NSLocalizedString("Basal", comment: "Logbook filter chip: show only basal changes")
            case .carbs: return NSLocalizedString("Carbs", comment: "Logbook filter chip: show only carb entries")
            case .loop: return NSLocalizedString("Loop", comment: "Logbook filter chip: show only what Loop did automatically (Loop is the app's name)")
            }
        }
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
                var parts = [bolus.automatic ? sourceLoop : sourceManual]
                if !bolus.automatic, let meal = carbsToday.first(where: { abs($0.date.timeIntervalSince(bolus.date)) <= 15 * 60 }) {
                    parts.append(LoopFormat.grams(meal.grams))
                }
                if let glucose { parts.append(glucose) }
                if bolus.manuallyEntered { parts.append(NSLocalizedString("logged", comment: "Logbook bolus row detail: the dose was logged by hand rather than delivered by the pump")) }
                entries.append(LogEntry(
                    id: "bolus-\(bolus.id)", date: bolus.date,
                    title: bolus.automatic
                        ? NSLocalizedString("Automatic bolus", comment: "Logbook row title: a bolus Loop delivered automatically")
                        : NSLocalizedString("Bolus", comment: "Logbook row title: a bolus"),
                    subtitle: joined(parts),
                    amount: LoopFormat.doseUnits(bolus.units), amountColor: P.insulinInk,
                    detail: LoopFormat.time(bolus.date),
                    icon: "plus", iconFill: P.insulin,
                    filters: bolus.automatic ? [.bolus, .loop] : [.bolus],
                    delete: canDelete && bolus.manuallyEntered ? bolus.dose.map { .deleteDose($0) } : nil))
            }

            for carb in carbsToday {
                var parts = [carb.createdByLoop ? sourceManual : NSLocalizedString("Health", comment: "Logbook carb row detail: the entry came from Apple Health")]
                if let food = carb.foodType, !food.isEmpty { parts.append(food) }
                if let hours = carb.absorptionHours { parts.append(String(format: NSLocalizedString("absorbs over %1$@ h", comment: "Logbook carb row detail: carb absorption time in hours. (1: hours, e.g. 3 or 2.5)"), hours.formatted(.number.precision(.fractionLength(0...1))))) }
                let editable = carb.createdByLoop && provider.allowsCarbEditing ? carb.entry : nil
                entries.append(LogEntry(
                    id: "carbs-\(carb.id)", date: carb.date,
                    title: NSLocalizedString("Carbs", comment: "Logbook row title: a carb entry"), subtitle: joined(parts),
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
                    title: NSLocalizedString("Basal adjustments", comment: "Logbook row title summarising the temp basals Loop set in a day"),
                    subtitle: String.localizedStringWithFormat(NSLocalizedString("Loop · %lld changes · tap to list", comment: "Logbook basal adjustments row subtitle: how many temp basals Loop set in the day; tapping lists them. (1: number of changes)"), count),
                    amount: String(format: NSLocalizedString("%1$@ U", comment: "Format string for an amount of insulin in units. (1: amount)"), LoopFormat.signed(net, decimals: 1)), amountColor: P.insulinInk,
                    detail: NSLocalizedString("vs plan", comment: "Logbook basal adjustments row: the insulin amount is the difference from the scheduled basal"),
                    icon: "waveform.path.ecg", iconFill: P.basalEdge, filters: [.basal, .loop],
                    basalChanges: automaticTemps.reversed()))
            }
            for temp in segments where temp.kind == .temp && !temp.automatic {
                entries.append(LogEntry(
                    id: "temp-\(temp.start.timeIntervalSince1970)", date: temp.start,
                    title: NSLocalizedString("Temp basal", comment: "Logbook row title: a temporary basal rate"),
                    subtitle: String(format: NSLocalizedString("Manual · %1$@", comment: "Logbook temp basal row subtitle: set by hand, then the rate and how long. (1: description, e.g. 0.50 U/h for 30m (scheduled 0.80))"), describe(temp)),
                    amount: LoopFormat.rate(temp.rate), amountColor: P.insulinInk,
                    detail: LoopFormat.time(temp.start),
                    icon: "waveform.path.ecg", iconFill: P.basalEdge, filters: [.basal]))
            }
            for suspend in segments where suspend.kind == .suspended {
                var parts = [suspend.automatic ? sourceLoop : sourceManual, LoopFormat.duration(suspend.end.timeIntervalSince(suspend.start))]
                if let glucose = glucoseContext(at: suspend.start, history.glucose, unit: unit, withTrend: false) { parts.append(glucose) }
                entries.append(LogEntry(
                    id: "suspend-\(suspend.start.timeIntervalSince1970)", date: suspend.start,
                    title: NSLocalizedString("Basal suspended", comment: "Logbook row title: insulin delivery was suspended"), subtitle: joined(parts),
                    amount: String(format: NSLocalizedString("%1$@ U/h", comment: "Format string for an insulin rate in units per hour. (1: rate)"), LoopFormat.number(0, decimals: 0)), amountColor: P.ink,
                    detail: LoopFormat.time(suspend.start),
                    icon: "pause.fill", iconFill: P.statusWarning,
                    filters: suspend.automatic ? [.basal, .loop] : [.basal]))
            }

            for event in pumpEvents where inDay(event.date) {
                let title: String
                switch event.kind {
                // Site change and alarm names come from the pump plugin as it reports them.
                case .siteChange(let name): title = name
                case .alarm(let name): title = name
                case .resume: title = NSLocalizedString("Basal resumed", comment: "Logbook row title: insulin delivery resumed after a suspend")
                }
                entries.append(LogEntry(
                    id: "pump-\(event.id)", date: event.date,
                    title: title, subtitle: NSLocalizedString("Pump", comment: "Logbook row subtitle: the event was reported by the insulin pump"),
                    amount: "", amountColor: P.ink,
                    detail: LoopFormat.time(event.date),
                    icon: "circle.dashed", iconFill: P.inkMuted.opacity(0.5), filters: []))
            }

            let insulin = segments.reduce(0) { $0 + $1.units } + history.boluses.filter { inDay($0.date) }.reduce(0) { $0 + $1.units }
            return LogDay(day: day.start, entries: entries.sorted { $0.date > $1.date }, insulin: insulin,
                          carbs: carbsToday.reduce(0) { $0 + $1.grams })
        }
    }

    private static var sourceLoop: String {
        NSLocalizedString("Loop", comment: "Logbook row detail: Loop made this change automatically (Loop is the app's name)")
    }

    private static var sourceManual: String {
        NSLocalizedString("Manual", comment: "Logbook row detail: the user made this entry or change by hand")
    }

    /// Row details are a list of independent facts ("Manual", "45 g", "glucose 7.5"), shown with a middle-dot separator.
    private static func joined(_ parts: [String]) -> String {
        parts.joined(separator: " · ")
    }

    static func describe(_ segment: BasalSegment) -> String {
        let rate = LoopFormat.rate(segment.rate)
        let duration = LoopFormat.duration(segment.end.timeIntervalSince(segment.start))
        if let scheduled = segment.scheduledRate {
            return String(format: NSLocalizedString("%1$@ for %2$@ (scheduled %3$@)", comment: "A temp basal: its rate, how long it ran and the scheduled rate it replaced. (1: rate, e.g. 0.50 U/h; 2: duration, e.g. 30m; 3: scheduled rate number, e.g. 0.80)"), rate, duration, LoopFormat.number(scheduled, decimals: 2))
        }
        return String(format: NSLocalizedString("%1$@ for %2$@", comment: "A temp basal: its rate and how long it ran. (1: rate, e.g. 0.50 U/h; 2: duration, e.g. 30m)"), rate, duration)
    }

    /// "glucose 7.5", or "glucose 11.0 rising" for Loop's own doses.
    private static func glucoseContext(at date: Date, _ readings: [GlucosePoint], unit: GlucoseUnitStyle, withTrend: Bool) -> String? {
        guard let reading = readings.last(where: { $0.date <= date.addingTimeInterval(60) }), date.timeIntervalSince(reading.date) <= 10 * 60 else {
            return nil
        }
        let value = unit.format(reading.mgdl)
        if withTrend, let earlier = readings.last(where: { $0.date <= reading.date.addingTimeInterval(-14 * 60) }),
           reading.date.timeIntervalSince(earlier.date) <= 20 * 60 {
            let perFifteen = (reading.mgdl - earlier.mgdl) / reading.date.timeIntervalSince(earlier.date) * 900
            if perFifteen > 10 {
                return String(format: NSLocalizedString("glucose %1$@ rising", comment: "Logbook row detail: glucose when the dose was given, and rising. (1: glucose value, e.g. 11.0)"), value)
            } else if perFifteen < -10 {
                return String(format: NSLocalizedString("glucose %1$@ falling", comment: "Logbook row detail: glucose when the dose was given, and falling. (1: glucose value, e.g. 11.0)"), value)
            }
        }
        return String(format: NSLocalizedString("glucose %1$@", comment: "Logbook row detail: glucose when the dose was given. (1: glucose value, e.g. 7.5)"), value)
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
                    Text(String(format: NSLocalizedString("Couldn't load Logbook: %1$@", comment: "Logbook error when its history can't be read. (1: system error description)"), error)).foregroundStyle(P.criticalInk)
                    Button(NSLocalizedString("Retry", comment: "Button to try loading the Logbook again")) { model.reload() }
                } else if model.loaded && model.days.allSatisfy({ $0.entries.isEmpty }) {
                    Text(NSLocalizedString("Nothing logged in the last 7 days.", comment: "Logbook empty state when there are no entries at all"))
                        .foregroundStyle(P.inkMuted)
                }
                ForEach(visibleDays) { day in
                    Section {
                        if day.entries.isEmpty {
                            Text(model.filter != .all
                                 ? NSLocalizedString("Nothing to show for this filter", comment: "Logbook day with no entries matching the selected filter")
                                 : day.insulin > 0
                                 ? NSLocalizedString("Scheduled basal only", comment: "Logbook day where only the scheduled basal ran, with nothing else logged")
                                 : NSLocalizedString("Nothing logged", comment: "Logbook day with no entries"))
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
                    Text(NSLocalizedString("Loop keeps the last 7 days on this phone. Older doses and carbs are in Apple Health and on the Trends tab.", comment: "Logbook footer explaining why only 7 days are listed"))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(P.surface)
            .navigationTitle(NSLocalizedString("Logbook", comment: "Title of the Logbook tab"))
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
        .alert(NSLocalizedString("Couldn't delete", comment: "Alert title when deleting a Logbook entry fails"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(NSLocalizedString("OK", comment: "Button to dismiss the Logbook delete error alert"), role: .cancel) {}
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
                        Text(filter.title)
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
        let date = LoopFormat.weekdayDay(day.day)
        let title = calendar.isDateInToday(day.day)
            ? String(format: NSLocalizedString("Today · %1$@", comment: "Logbook day header for today. (1: weekday and date, e.g. Sun 25 Oct)"), date)
            : calendar.isDateInYesterday(day.day)
            ? String(format: NSLocalizedString("Yesterday · %1$@", comment: "Logbook day header for yesterday. (1: weekday and date, e.g. Sat 24 Oct)"), date)
            : date
        return HStack(alignment: .firstTextBaseline) {
            Text(title)
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
                        Button(role: .destructive) { model.perform(action) } label: { Label(NSLocalizedString("Delete", comment: "Swipe action to delete a Logbook entry"), systemImage: "trash") }
                    }
                    if let carb = entry.edit, model.carbEditingAllowed {
                        Button {
                            guard model.provider.allowsCarbEditing else { return }
                            path.append(.editCarbs(CarbEditRoute(entry: carb)))
                        } label: { Label(NSLocalizedString("Edit", comment: "Swipe action to edit a Logbook carb entry"), systemImage: "pencil") }
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
        _viewModel = StateObject(wrappedValue: CarbEntryViewModel(delegate: deviceManager, originalCarbEntry: entry))
        self.deviceManager = deviceManager
        self.provider = provider
        self.dismiss = dismiss
    }

    var body: some View {
        CarbEntryView(viewModel: viewModel)
            .environmentObject(deviceManager.displayGlucosePreference)
            .environment(\.dismissAction, dismiss)
            .navigationTitle(NSLocalizedString("Edit Carb Entry", comment: "Title of the screen for editing a carb entry from the Logbook"))
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
                Text(String(format: NSLocalizedString("%1$@ U", comment: "Format string for an amount of insulin in units. (1: amount)"), LoopFormat.signed(change.netUnits)))
                    .font(LoopDesign.Typeface.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(P.insulinInk)
            }
            .accessibilityElement(children: .combine)
        }
        .navigationTitle(NSLocalizedString("Basal adjustments", comment: "Title of the list of every temp basal Loop set in a day"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
