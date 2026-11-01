//
//  CarbEntryScreen.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import Charts

private typealias P = LoopDesign.Palette

/// Adding or editing carbs in the redesign. It drives the same CarbEntryViewModel as CarbEntryView, so validation,
/// favourite foods and the hand-off to the bolus screen are unchanged; only the layout is new.
///
/// The top of the screen is a preview of the meal as Loop will model it: the amount, over Loop's absorption curve
/// drawn on a real time axis. The amount sets the curve's height, the speed its length, and when it was eaten where
/// it sits against now, so every choice below shows its effect there.
struct CarbEntryScreen: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var viewModel: CarbEntryViewModel

    @State private var amountText: String
    @State private var eatenChoice: Int?
    @State private var showHowAbsorptionTimeWorks = false
    @State private var showAddFavoriteFood = false
    /// Other was tapped, so it stays chosen even while its food and time still match a preset.
    @State private var otherChosen = false
    @FocusState private var amountFocused: Bool
    @FocusState private var foodTypeFocused: Bool
    @Namespace private var thumbs

    private let isNewEntry: Bool

    /// Minutes before now offered as one-tap times.
    private static let eatenChoices = [0, 15, 30, 60]

    init(viewModel: CarbEntryViewModel) {
        self.viewModel = viewModel
        isNewEntry = viewModel.originalCarbEntry == nil
        _amountText = State(initialValue: viewModel.carbsQuantity.flatMap { $0 > 0 ? Self.amountFormatter.string(from: NSNumber(value: $0)) : nil } ?? "")
        _eatenChoice = State(initialValue: viewModel.originalCarbEntry == nil && abs(viewModel.time.timeIntervalSinceNow) < 60 ? 0 : nil)
    }

    var body: some View {
        if isNewEntry {
            NavigationStack {
                content
                    .navigationTitle(NSLocalizedString("Add carbs", comment: "Button on the Now screen that opens carb entry"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(NSLocalizedString("Cancel", comment: "Button label for cancel"), action: dismiss)
                        }
                    }
            }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let override = viewModel.currentOverride {
                    ActivePresetBanner(override: override)
                }
                ForEach(Array(viewModel.warnings).sorted { $0.priority < $1.priority }) { warning in
                    warningView(warning)
                }
                mealPreview
                if isNewEntry, FeatureFlags.allowExperimentalFeatures {
                    favourites
                }
                absorption
                eaten
            }
            .padding(.horizontal, LoopDesign.Space.s4)
            .padding(.top, LoopDesign.Space.s2)
            .padding(.bottom, LoopDesign.Space.s6)
        }
        // Any scroll puts the keyboard away: at large text sizes it otherwise covers the rest of the form for good.
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            if amountFocused || foodTypeFocused {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        amountFocused = false
                        foodTypeFocused = false
                    }
                }
            }
        }
        .background(P.surface)
        .safeAreaInset(edge: .bottom) { continueBar }
        .onAppear {
            // As FoodTypeRow does: a new entry starts as the medium food, so the entry carries its emoji.
            if isNewEntry && !viewModel.usesCustomFoodType && viewModel.selectedDefaultAbsorptionTimeEmoji.isEmpty {
                viewModel.selectedDefaultAbsorptionTimeEmoji = Speed.medium.emoji
            }
        }
        .task {
            // Focus set while the sheet is still presenting is dropped, so wait for it to settle.
            guard viewModel.shouldBeginEditingQuantity else { return }
            try? await Task.sleep(for: .milliseconds(450))
            amountFocused = true
        }
        .onChange(of: viewModel.carbsQuantity) { _, quantity in
            // A favourite fills the amount in; keep the field in step unless the person is typing it.
            guard !amountFocused else { return }
            amountText = quantity.flatMap { $0 > 0 ? Self.amountFormatter.string(from: NSNumber(value: $0)) : nil } ?? ""
        }
        .navigationDestination(isPresented: Binding(get: { viewModel.bolusViewModel != nil }, set: { if !$0 { viewModel.bolusViewModel = nil } })) {
            if let bolusViewModel = viewModel.bolusViewModel {
                BolusEntryView(viewModel: bolusViewModel)
                    .environmentObject(displayGlucosePreference)
                    .environment(\.dismissAction, dismiss)
                    .environment(\.guidanceColors, guidanceColors)
            }
        }
        .alert(item: $viewModel.alert, content: alert(for:))
        .sheet(isPresented: $showHowAbsorptionTimeWorks) {
            HowAbsorptionTimeWorksView()
        }
        .sheet(isPresented: $showAddFavoriteFood) {
            FavoriteFoodAddEditView(carbsQuantity: viewModel.carbsQuantity,
                                    foodType: viewModel.usesCustomFoodType ? viewModel.foodType : viewModel.selectedDefaultAbsorptionTimeEmoji,
                                    absorptionTime: viewModel.absorptionTime) { food in
                showAddFavoriteFood = false
                viewModel.onFavoriteFoodSave(food)
            }
        }
    }

    private func animated(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.snappy(duration: 0.3), change)
        }
    }

    // MARK: Meal preview

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    private var mealPreview: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s1) {
                TextField(text: $amountText, prompt: Text(verbatim: "0").foregroundStyle(P.inkMuted.opacity(0.45))) {
                    Text(NSLocalizedString("Amount Consumed", comment: "Label for carb quantity entry row on carb entry screen"))
                }
                .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(P.carbsInk)
                .tint(P.carbsInk)
                .keyboardType(.decimalPad)
                .accessibilityLabel(NSLocalizedString("Amount Consumed", comment: "Label for carb quantity entry row on carb entry screen"))
                .accessibilityIdentifier("textField_CarbsAmount")
                .fixedSize()
                .focused($amountFocused)
                .onChange(of: amountText) { _, text in
                    viewModel.carbsQuantity = Self.amountFormatter.number(from: text)?.doubleValue
                }
                Text(NSLocalizedString("g", comment: "Abbreviation for grams"))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(P.inkMuted)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = true }

            TimelineView(.everyMinute) { context in
                MealAbsorptionChart(grams: viewModel.carbsQuantity ?? 0,
                                    absorptionTime: viewModel.absorptionTime,
                                    eaten: viewModel.time,
                                    now: context.date,
                                    axisLength: max(viewModel.defaultAbsorptionTimes.slow, viewModel.absorptionTime))
            }
        }
        .padding(.horizontal, LoopDesign.Space.s4)
        .padding(.top, LoopDesign.Space.s1)
        .padding(.bottom, LoopDesign.Space.s4)
        .background(P.surfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Favourites

    @ViewBuilder
    private var favourites: some View {
        if !viewModel.favoriteFoods.isEmpty || !viewModel.saveFavoriteFoodButtonDisabled {
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                sectionTitle(NSLocalizedString("Favorite Foods", comment: "The section title for Carb entry screen where Favorite Foods can be selected"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LoopDesign.Space.s2) {
                        ForEach(Array(viewModel.favoriteFoods.enumerated()), id: \.element.id) { index, food in
                            let selected = viewModel.selectedFavoriteFoodIndex == index
                            Button {
                                amountFocused = false
                                // A favourite brings its own food and time, so the speed shown follows it rather than an earlier Other.
                                otherChosen = false
                                animated { viewModel.selectedFavoriteFoodIndex = selected ? -1 : index }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(food.foodType)
                                    Text(food.name).foregroundStyle(P.ink)
                                    Text(LoopFormat.grams(food.carbsQuantity.doubleValue(for: .gram)))
                                        .monospacedDigit()
                                        .foregroundStyle(selected ? P.carbsInk : P.inkMuted)
                                }
                                .font(LoopDesign.Typeface.subhead.weight(.medium))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .background(selected ? P.carbs.opacity(0.18) : P.surfaceRaised, in: Capsule())
                                .overlay(Capsule().strokeBorder(selected ? P.carbs : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                        if viewModel.selectedFavoriteFood == nil {
                            Button {
                                showAddFavoriteFood = true
                            } label: {
                                Label(NSLocalizedString("Save as favorite food", comment: "Button on the carb entry screen to save the entry as a favourite food"), systemImage: "star")
                                    .font(LoopDesign.Typeface.subhead.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 40)
                                    .overlay(Capsule().strokeBorder(P.separator.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(P.accentInk)
                            .disabled(viewModel.saveFavoriteFoodButtonDisabled)
                            .opacity(viewModel.saveFavoriteFoodButtonDisabled ? 0.4 : 1)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: Eaten

    private func eatenTitle(_ minutes: Int) -> String {
        minutes == 0
            ? NSLocalizedString("Now", comment: "Carb entry time choice: eaten now")
            : String(format: NSLocalizedString("%1$@ ago", comment: "Carb entry time choice: eaten this long before now. (1: duration, e.g. 15m or 1h)"), LoopFormat.duration(Double(minutes) * 60))
    }

    private var eaten: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
            let header = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: LoopDesign.Space.s2))
                : AnyLayout(HStackLayout(alignment: .center))
            header {
                sectionTitle(NSLocalizedString("Eaten", comment: "Carb entry section title: when the food was eaten"))
                if !typeSize.isAccessibilitySize { Spacer() }
                DatePicker(selection: Binding(get: { viewModel.time }, set: { viewModel.time = $0; eatenChoice = nil }),
                           in: viewModel.minimumDate...viewModel.maximumDate, displayedComponents: [.date, .hourAndMinute]) {
                    Text(NSLocalizedString("Time", comment: "Carb entry row label: the exact time the food was eaten"))
                }
                .labelsHidden()
                .tint(P.carbsInk)
            }
            ChoiceTrack(choices: Self.eatenChoices, selection: eatenChoice, thumb: "eaten", namespace: thumbs) { minutes in
                amountFocused = false
                let date = Date().addingTimeInterval(-Double(minutes) * 60)
                animated {
                    eatenChoice = minutes
                    viewModel.time = min(max(date, viewModel.minimumDate), viewModel.maximumDate)
                }
            } label: { minutes, selected in
                Text(eatenTitle(minutes))
                    .font(LoopDesign.Typeface.subhead.weight(selected ? .semibold : .medium).monospacedDigit())
                    .foregroundStyle(selected ? P.carbsInk : P.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.vertical, LoopDesign.Space.s2)
            }
        }
    }

    // MARK: Absorption

    enum Speed: CaseIterable {
        case fast, medium, slow, other

        /// The emoji FoodTypeRow uses for each default absorption time; the entry stores it as its food type.
        var emoji: String {
            switch self {
            case .fast: return "🍭"
            case .medium: return "🌮"
            case .slow: return "🍕"
            case .other: return "🍽️"
            }
        }

        var title: String {
            switch self {
            case .fast: return NSLocalizedString("Fast", comment: "Carb entry absorption choice: food that absorbs quickly, such as sweets")
            case .medium: return NSLocalizedString("Medium", comment: "Carb entry absorption choice: a typical mixed meal")
            case .slow: return NSLocalizedString("Slow", comment: "Carb entry absorption choice: food that absorbs slowly, such as pizza")
            case .other: return NSLocalizedString("Other", comment: "Carb entry absorption choice: set your own food and absorption time")
            }
        }
    }

    private func hours(_ speed: Speed) -> TimeInterval {
        switch speed {
        case .fast: return viewModel.defaultAbsorptionTimes.fast
        case .medium: return viewModel.defaultAbsorptionTimes.medium
        case .slow: return viewModel.defaultAbsorptionTimes.slow
        case .other: return viewModel.absorptionTime
        }
    }

    private var selectedSpeed: Speed {
        let presets = Speed.allCases.filter { $0 != .other }
        if viewModel.usesCustomFoodType {
            if otherChosen { return .other }
            // A saved entry comes back as a custom food; one that is exactly a preset's emoji and time shows as that preset.
            return presets.first { $0.emoji == viewModel.foodType && hours($0) == viewModel.absorptionTime } ?? .other
        }
        return presets.first { $0.emoji == viewModel.selectedDefaultAbsorptionTimeEmoji } ?? .medium
    }

    private var absorption: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
            HStack {
                sectionTitle(NSLocalizedString("How fast it absorbs", comment: "Carb entry section title: choose how quickly the food's carbs absorb"))
                Spacer()
                Button {
                    showHowAbsorptionTimeWorks = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(LoopDesign.Typeface.subhead.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 28, alignment: .trailing)
                }
                .foregroundStyle(P.accentInk)
                .accessibilityLabel(NSLocalizedString("Absorption Time", comment: "Accessibility label for the button that explains carb absorption time"))
            }
            ChoiceTrack(choices: Speed.allCases, selection: selectedSpeed, thumb: "speed", namespace: thumbs) { speed in
                animated { choose(speed) }
            } label: { speed, selected in
                VStack(spacing: 2) {
                    Text(speed.title)
                        .font(LoopDesign.Typeface.subhead.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? P.carbsInk : P.ink)
                    HStack(spacing: 3) {
                        // The food the entry is saved with; Other shows the one typed in.
                        Text(speed == .other && selected && !viewModel.foodType.isEmpty ? viewModel.foodType : speed.emoji)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        Text(durationLabel(speed, selected: selected))
                            .foregroundStyle(selected ? P.carbsInk : P.inkMuted)
                    }
                    .font(LoopDesign.Typeface.footnote.monospacedDigit())
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(speed.title), \(durationLabel(speed, selected: selected))")
            }
            if selectedSpeed == .other {
                otherFood
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func durationLabel(_ speed: Speed, selected: Bool) -> String {
        speed == .other && !selected
            ? NSLocalizedString("Custom", comment: "Carb entry absorption choice Other, before it is chosen: you set the food and absorption time yourself")
            : LoopFormat.duration(hours(speed))
    }

    private var otherFood: some View {
        VStack(spacing: 0) {
            HStack {
                Text(NSLocalizedString("Food Type", comment: "Label for the food type row on the carb entry screen"))
                    .font(LoopDesign.Typeface.body)
                Spacer()
                TextField(Speed.other.emoji, text: $viewModel.foodType)
                    .multilineTextAlignment(.trailing)
                    .font(.title3)
                    .focused($foodTypeFocused)
                    .frame(maxWidth: 120)
            }
            .padding(.vertical, 10)
            Divider()
            Stepper(value: Binding(get: { viewModel.absorptionTime }, set: { newValue in animated { viewModel.absorptionTime = newValue } }),
                    in: viewModel.absorptionRimesRange, step: 30 * 60) {
                HStack {
                    Text(NSLocalizedString("Absorption Time", comment: "Accessibility label for the button that explains carb absorption time"))
                        .font(LoopDesign.Typeface.body)
                    Spacer()
                    Text(LoopFormat.duration(viewModel.absorptionTime))
                        .font(LoopDesign.Typeface.body.monospacedDigit())
                        .foregroundStyle(P.carbsInk)
                }
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, LoopDesign.Space.s4)
        .background(P.surfaceRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func choose(_ speed: Speed) {
        amountFocused = false
        // Re-choosing the shown speed changes nothing, so an unedited entry stays unedited.
        guard speed != selectedSpeed else { return }
        // A favourite sets its own food and absorption; choosing a speed instead lets it go but keeps the amount.
        if viewModel.selectedFavoriteFood != nil {
            let quantity = viewModel.carbsQuantity
            viewModel.selectedFavoriteFoodIndex = -1
            viewModel.carbsQuantity = quantity
        }
        otherChosen = speed == .other
        if speed == .other {
            viewModel.usesCustomFoodType = true
            foodTypeFocused = true
        } else {
            viewModel.usesCustomFoodType = false
            viewModel.foodType = ""
            viewModel.selectedDefaultAbsorptionTimeEmoji = speed.emoji
            viewModel.absorptionTime = hours(speed)
        }
    }

    // MARK: Continue

    private var continueBar: some View {
        Button(action: viewModel.continueToBolus) {
            Text(NSLocalizedString("Continue", comment: "Button label for continue"))
                .font(LoopDesign.Typeface.headline)
                .foregroundStyle(viewModel.continueButtonDisabled ? P.inkMuted : P.onFill)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(viewModel.continueButtonDisabled ? P.surfaceRaised : P.carbs,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.continueButtonDisabled)
        .accessibilityIdentifier("button_Continue")
        .padding(.horizontal, LoopDesign.Space.s4)
        .padding(.top, LoopDesign.Space.s2)
        .padding(.bottom, LoopDesign.Space.s1)
        .background(P.surface)
    }

    // MARK: Pieces

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(LoopDesign.Typeface.subhead.weight(.semibold))
            .foregroundStyle(P.inkMuted)
            .accessibilityAddTraits(.isHeader)
    }

    private func warningView(_ warning: CarbEntryViewModel.Warning) -> some View {
        HStack(alignment: .top, spacing: LoopDesign.Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(P.criticalInk)
                .accessibilityHidden(true)
            Text(warningText(warning))
                .font(LoopDesign.Typeface.subhead)
                .foregroundStyle(P.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LoopDesign.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(P.statusCritical.opacity(0.16), in: RoundedRectangle(cornerRadius: LoopDesign.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LoopDesign.Radius.lg, style: .continuous).strokeBorder(P.statusCritical.opacity(0.45), lineWidth: 1))
    }

    private func warningText(_ warning: CarbEntryViewModel.Warning) -> String {
        switch warning {
        case .entryIsMissedMeal:
            return NSLocalizedString("Loop has detected an missed meal and estimated its size. Edit the carb amount to match the amount of any carbs you may have eaten.", comment: "Warning displayed when user is adding a meal from an missed meal notification")
        case .glucoseRisingRapidly:
            return NSLocalizedString("Your glucose is rapidly rising. Check that any carbs you've eaten were logged. If you logged carbs, check that the time you entered lines up with when you started eating.", comment: "Warning to ensure the carb entry is accurate")
        }
    }

    private func alert(for alert: CarbEntryViewModel.Alert) -> SwiftUI.Alert {
        switch alert {
        case .maxQuantityExceded:
            let message = String(
                format: NSLocalizedString("The maximum allowed amount is %@ grams.", comment: "Alert body displayed for quantity greater than max (1: maximum quantity in grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: viewModel.maxCarbEntryQuantity.doubleValue(for: viewModel.preferredCarbUnit)), number: .none)
            )
            let okMessage = NSLocalizedString("com.loudnate.LoopKit.errorAlertActionTitle", value: "OK", comment: "The title of the action used to dismiss an error alert")
            return SwiftUI.Alert(
                title: Text("Large Meal Entered", comment: "Title of the warning shown when a large meal was entered"),
                message: Text(message),
                dismissButton: .cancel(Text(okMessage), action: viewModel.clearAlert)
            )
        case .warningQuantityValidation:
            let message = String(
                format: NSLocalizedString("Did you intend to enter %1$@ grams as the amount of carbohydrates for this meal?", comment: "Alert body when entered carbohydrates is greater than threshold (1: entered quantity in grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: viewModel.carbsQuantity ?? 0), number: .none)
            )
            return SwiftUI.Alert(
                title: Text("Large Meal Entered", comment: "Title of the warning shown when a large meal was entered"),
                message: Text(message),
                primaryButton: .default(Text("No, edit amount", comment: "The title of the action used when rejecting the the amount of carbohydrates entered."), action: viewModel.clearAlert),
                secondaryButton: .cancel(Text("Yes", comment: "The title of the action used when confirming entered amount of carbohydrates."), action: viewModel.clearAlertAndContinueToBolus)
            )
        }
    }
}

/// A row of choices sharing one track, with a thumb that slides to the chosen one. Two by two at accessibility text sizes.
private struct ChoiceTrack<Choice: Hashable, Label: View>: View {
    let choices: [Choice]
    let selection: Choice?
    let thumb: String
    let namespace: Namespace.ID
    let action: (Choice) -> Void
    @ViewBuilder let label: (Choice, Bool) -> Label

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: typeSize.isAccessibilitySize ? 2 : choices.count)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(choices, id: \.self) { choice in
                let selected = choice == selection
                Button {
                    action(choice)
                } label: {
                    label(choice, selected)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(P.carbs.opacity(0.18))
                                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(P.carbs, lineWidth: 1.5))
                                    .matchedGeometryEffect(id: thumb, in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(P.surfaceRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

/// The meal's carbs absorbing over time, drawn the way the day page draws carbs on board: a soft fill under a line,
/// solid up to now and dashed after, over hour gridlines. Touch and hold to read how much is left at any time.
private struct MealAbsorptionChart: View {
    let grams: Double
    let absorptionTime: TimeInterval
    let eaten: Date
    let now: Date
    /// The longest absorption on offer, so a faster food draws a visibly shorter curve.
    let axisLength: TimeInterval

    @State private var selection: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 120
    private static let nowLabelHeight: CGFloat = 20

    private var absorbed: Date { eaten.addingTimeInterval(absorptionTime) }

    private var window: DateInterval {
        let start = min(eaten, now)
        return DateInterval(start: start, end: max(eaten.addingTimeInterval(axisLength), now.addingTimeInterval(15 * 60)))
    }

    /// Loop's absorption rate as a share of its peak (PiecewiseLinearAbsorption in LoopAlgorithm): rising to the
    /// peak at 15% of the absorption time, steady until half way, then falling to nothing.
    private static func shape(_ t: Double) -> Double {
        switch t {
        case ..<0: return 0
        case ..<0.15: return t / 0.15
        case ..<0.5: return 1
        case ..<1: return (1 - t) / 0.5
        default: return 0
        }
    }

    /// The share of the carbs absorbed by `t`: the area under `shape` so far, over its whole area of 0.675.
    private static func absorbedShare(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        let area: Double
        if t < 0.15 {
            area = t * t / 0.3
        } else if t < 0.5 {
            area = 0.075 + (t - 0.15)
        } else {
            area = 0.425 + ((t - 0.5) - (t * t - 0.25) / 2) / 0.5
        }
        return min(1, area / 0.675)
    }

    /// The plotted height of the peak. Its area stands for the grams, so the peak is the rate, grams over
    /// 0.675 × the absorption time; a square root keeps a small snack visible beside a large fast one.
    private var peak: Double {
        guard grams > 0, absorptionTime > 0 else { return 0.42 }
        let gramsPerHour = grams / (0.675 * absorptionTime / 3600)
        return min(1, max(0.14, (gramsPerHour / 150).squareRoot()))
    }

    private struct Sample: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// The curve's corners, plus the point where it crosses now, so the solid and dashed parts meet exactly.
    private var samples: [Sample] {
        var shares = [0, 0.15, 0.5, 1.0]
        let nowShare = now.timeIntervalSince(eaten) / max(absorptionTime, 1)
        if nowShare > 0 && nowShare < 1 { shares.append(nowShare) }
        return shares.sorted().map { Sample(date: eaten.addingTimeInterval($0 * absorptionTime), value: Self.shape($0) * peak) }
    }

    private var hourMarks: [Date] {
        stride(from: 3600.0, to: window.duration, by: 3600).map { eaten.addingTimeInterval($0) }.filter { window.contains($0) }
    }

    var body: some View {
        let samples = samples
        let past = samples.filter { $0.date <= now }
        let future = samples.filter { $0.date >= now }
        VStack(spacing: 6) {
            Chart {
                ForEach(samples) { sample in
                    AreaMark(x: .value("Time", sample.date), yStart: .value("Base", 0), yEnd: .value("Rate", sample.value), series: .value("Series", "fill"))
                        .foregroundStyle(P.carbs.opacity(grams > 0 ? 0.16 : 0))
                }
                // Already absorbed: a firmer fill under the solid part.
                ForEach(past) { sample in
                    AreaMark(x: .value("Time", sample.date), yStart: .value("Base", 0), yEnd: .value("Rate", sample.value), series: .value("Series", "past-fill"))
                        .foregroundStyle(P.carbs.opacity(grams > 0 ? 0.22 : 0))
                }
                ForEach(past) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("Rate", sample.value), series: .value("Series", "past"))
                        .foregroundStyle(grams > 0 ? P.carbs : P.inkMuted.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                ForEach(future) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("Rate", sample.value), series: .value("Series", "future"))
                        .foregroundStyle(grams > 0 ? P.carbs : P.inkMuted.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 3]))
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(P.separator)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(P.inkMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
                if let selection {
                    RuleMark(x: .value("Selected", selection)).foregroundStyle(P.ink.opacity(0.6))
                }
            }
            .chartXScale(domain: window.start...window.end)
            .chartYScale(domain: 0...1.0)
            .chartXAxis {
                AxisMarks(values: hourMarks) { _ in
                    AxisGridLine().foregroundStyle(P.grid)
                }
            }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                ZStack(alignment: .topLeading) {
                    ScrubOverlay(proxy: proxy, selection: $selection, clampTo: window)
                    if selection == nil, let nowX = proxy.position(forX: now) {
                        GeometryReader { geometry in
                            // Centred over the line, kept inside the chart.
                            Text(NSLocalizedString("Now", comment: "Carb entry time choice: eaten now"))
                                .font(LoopDesign.Typeface.caption)
                                .foregroundStyle(P.inkMuted)
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .fixedSize()
                                .frame(width: 48)
                                .position(x: min(max(nowX, 24), geometry.size.width - 24), y: -Self.nowLabelHeight / 2)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if let selection {
                    ScrubCallout(rows: scrubRows(at: selection))
                        .offset(y: -Self.nowLabelHeight)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: Self.height)
            .padding(.top, Self.nowLabelHeight)
            .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: grams)
            .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: absorptionTime)
            .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: eaten)

            AxisLabels(start: eaten.timeIntervalSince(window.start) / window.duration, end: absorbed.timeIntervalSince(window.start) / window.duration) {
                Text(LoopFormat.time(eaten))
                    .foregroundStyle(P.ink)
                Text(String(format: NSLocalizedString("Absorbed by %1$@", comment: "Under the end of the carb absorption curve: when the carbs will have absorbed (1: time)"), LoopFormat.time(absorbed)))
                    .foregroundStyle(P.inkMuted)
            }
            .font(LoopDesign.Typeface.footnote.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: NSLocalizedString("Eaten at %1$@, absorbed by %2$@", comment: "Accessibility summary of the carb entry preview chart (1: time eaten, 2: time absorbed)"), LoopFormat.time(eaten), LoopFormat.time(absorbed)))
    }

    private func scrubRows(at date: Date) -> [ScrubCallout.Row] {
        var rows: [ScrubCallout.Row] = [.init(label: nil, value: LoopFormat.time(date), color: P.ink)]
        if grams > 0 {
            let left = grams * (1 - Self.absorbedShare(date.timeIntervalSince(eaten) / max(absorptionTime, 1)))
            rows.append(.init(label: NSLocalizedString("COB", comment: "Abbreviation for carbs on board (active carbohydrate)"), value: LoopFormat.grams(left), color: P.carbsInk))
        }
        return rows
    }
}

/// Two labels on a time axis: the first starts at `start`, the second ends at `end`, pushed apart when they'd meet.
/// When they can't share a line, as at large text sizes, the second goes under the first.
private struct AxisLabels: Layout {
    var start: Double
    var end: Double

    private static let gap: CGFloat = 12

    private func stacked(_ width: CGFloat, _ subviews: Subviews) -> Bool {
        subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(Self.gap, +) > width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard stacked(width, subviews) else {
            return CGSize(width: width, height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
        }
        // Stacked labels wrap to the width rather than run off it.
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.reduce(0, +)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if stacked(bounds.width, subviews) {
            let wrapped = ProposedViewSize(width: bounds.width, height: nil)
            let firstHeight = subviews[0].sizeThatFits(wrapped).height
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: wrapped)
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + firstHeight), proposal: wrapped)
            return
        }
        let first = subviews[0].sizeThatFits(.unspecified)
        let second = subviews[1].sizeThatFits(.unspecified)
        let firstX = min(max(bounds.minX, bounds.minX + bounds.width * start), bounds.maxX - first.width)
        let secondX = min(max(bounds.minX + bounds.width * end - second.width, firstX + first.width + Self.gap), bounds.maxX - second.width)
        subviews[0].place(at: CGPoint(x: firstX, y: bounds.minY), proposal: ProposedViewSize(first))
        subviews[1].place(at: CGPoint(x: secondX, y: bounds.minY), proposal: ProposedViewSize(second))
    }
}
