//
//  CarbEntryScreen.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

private typealias P = LoopDesign.Palette

/// Adding or editing carbs in the redesign. It drives the same CarbEntryViewModel as CarbEntryView, so validation,
/// favourite foods and the hand-off to the bolus screen are unchanged; only the layout is new.
///
/// The amount is the one large thing on the screen. Absorption speed is chosen from cards that draw Loop's own
/// absorption curve (rise over the first 15%, steady to half way, fall to the end) at each speed's length, so
/// "fast" and "slow" are shown as shapes rather than named.
struct CarbEntryScreen: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors

    @ObservedObject var viewModel: CarbEntryViewModel

    @State private var amountText: String
    @State private var eatenChoice: Int?
    @State private var showHowAbsorptionTimeWorks = false
    @State private var showAddFavoriteFood = false
    /// Other was tapped, so it stays chosen even while its food and time still match a preset.
    @State private var otherChosen = false
    @FocusState private var amountFocused: Bool
    @FocusState private var foodTypeFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Four across, or two by two at accessibility text sizes.
    private var choiceColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: LoopDesign.Space.s2), count: typeSize.isAccessibilitySize ? 2 : 4)
    }

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
            VStack(alignment: .leading, spacing: LoopDesign.Space.s6) {
                if let override = viewModel.currentOverride {
                    ActivePresetBanner(override: override)
                }
                ForEach(Array(viewModel.warnings).sorted { $0.priority < $1.priority }) { warning in
                    warningView(warning)
                }
                amount
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
            if viewModel.shouldBeginEditingQuantity { amountFocused = true }
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

    // MARK: Amount

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    private var amount: some View {
        HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s2) {
            TextField(text: $amountText, prompt: Text(verbatim: "0").foregroundStyle(P.inkMuted.opacity(0.5))) {
                Text(NSLocalizedString("Amount Consumed", comment: "Label for carb quantity entry row on carb entry screen"))
            }
            .font(.system(size: 76, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(P.carbsInk)
            .keyboardType(.decimalPad)
            .accessibilityLabel(NSLocalizedString("Amount Consumed", comment: "Label for carb quantity entry row on carb entry screen"))
            .accessibilityIdentifier("textField_CarbsAmount")
            .multilineTextAlignment(.trailing)
            .fixedSize()
            .focused($amountFocused)
            .onChange(of: amountText) { _, text in
                viewModel.carbsQuantity = Self.amountFormatter.number(from: text)?.doubleValue
            }
            Text(NSLocalizedString("g", comment: "Abbreviation for grams"))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(P.carbsInk.opacity(0.7))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LoopDesign.Space.s3)
        .contentShape(Rectangle())
        .onTapGesture { amountFocused = true }
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
                                viewModel.selectedFavoriteFoodIndex = selected ? -1 : index
                            } label: {
                                HStack(spacing: LoopDesign.Space.s1) {
                                    Text(food.foodType)
                                    Text(food.name).foregroundStyle(P.ink)
                                    Text(LoopFormat.grams(food.carbsQuantity.doubleValue(for: .gram))).foregroundStyle(P.carbsInk)
                                }
                                .font(LoopDesign.Typeface.subhead.weight(.medium))
                                .padding(.horizontal, LoopDesign.Space.s3)
                                .padding(.vertical, LoopDesign.Space.s2)
                                .background(selected ? P.carbs.opacity(0.18) : P.surfaceRaised, in: Capsule())
                                .overlay(Capsule().strokeBorder(selected ? P.carbs : P.separator.opacity(0.4), lineWidth: selected ? 2 : 1))
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
                                    .padding(.horizontal, LoopDesign.Space.s3)
                                    .padding(.vertical, LoopDesign.Space.s2)
                                    .overlay(Capsule().strokeBorder(P.separator.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(P.accentInk)
                            .disabled(viewModel.saveFavoriteFoodButtonDisabled)
                            .opacity(viewModel.saveFavoriteFoodButtonDisabled ? 0.4 : 1)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    // MARK: Eaten

    private var eaten: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
            sectionTitle(NSLocalizedString("Eaten", comment: "Carb entry section title: when the food was eaten"))
            LazyVGrid(columns: choiceColumns, spacing: LoopDesign.Space.s2) {
                ForEach(Self.eatenChoices, id: \.self) { minutes in
                    let selected = eatenChoice == minutes
                    Button {
                        let date = Date().addingTimeInterval(-Double(minutes) * 60)
                        eatenChoice = minutes
                        viewModel.time = min(max(date, viewModel.minimumDate), viewModel.maximumDate)
                    } label: {
                        Text(minutes == 0
                             ? NSLocalizedString("Now", comment: "Carb entry time choice: eaten now")
                             : String(format: NSLocalizedString("%1$@ ago", comment: "Carb entry time choice: eaten this long before now. (1: duration, e.g. 15m or 1h)"), LoopFormat.duration(Double(minutes) * 60)))
                            .font(LoopDesign.Typeface.subhead.weight(selected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(selected ? P.onFill : P.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selected ? P.carbs : P.surfaceRaised, in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            let timeLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: LoopDesign.Space.s2))
                : AnyLayout(HStackLayout())
            timeLayout {
                Text(NSLocalizedString("Time", comment: "Carb entry row label: the exact time the food was eaten"))
                    .font(LoopDesign.Typeface.subhead)
                    .foregroundStyle(P.inkMuted)
                if !typeSize.isAccessibilitySize { Spacer() }
                DatePicker(selection: Binding(get: { viewModel.time }, set: { viewModel.time = $0; eatenChoice = nil }),
                           in: viewModel.minimumDate...viewModel.maximumDate, displayedComponents: [.date, .hourAndMinute]) {
                    Text(NSLocalizedString("Time", comment: "Carb entry row label: the exact time the food was eaten"))
                }
                .labelsHidden()
                .tint(P.carbsInk)
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
                }
                .foregroundStyle(P.accentInk)
                .accessibilityLabel(NSLocalizedString("Absorption Time", comment: "Accessibility label for the button that explains carb absorption time"))
            }
            // All four share one time axis, so a slower food draws a longer, lower curve.
            let axis = max(Speed.allCases.map(hours).max() ?? 1, 1)
            LazyVGrid(columns: choiceColumns, spacing: LoopDesign.Space.s2) {
                ForEach(Speed.allCases, id: \.self) { speed in
                    speedCard(speed, axis: axis)
                }
            }
            if selectedSpeed == .other {
                otherFood
            }
        }
    }

    private func durationLabel(_ speed: Speed, selected: Bool) -> String {
        speed == .other && !selected
            ? NSLocalizedString("Custom", comment: "Carb entry absorption choice Other, before it is chosen: you set the food and absorption time yourself")
            : LoopFormat.duration(hours(speed))
    }

    private func speedCard(_ speed: Speed, axis: TimeInterval) -> some View {
        let selected = selectedSpeed == speed
        let emoji = speed == .other && selectedSpeed == .other && !viewModel.foodType.isEmpty ? viewModel.foodType : speed.emoji
        return Button {
            choose(speed)
        } label: {
            VStack(alignment: .leading, spacing: LoopDesign.Space.s1) {
                Text(emoji).font(.title3).lineLimit(1).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                // Other has no time of its own until it's chosen, so it draws no curve rather than echo a preset's.
                AbsorptionCurve(fraction: hours(speed) / axis)
                    .fill(selected ? P.carbs : P.inkMuted.opacity(0.35))
                    .opacity(speed == .other && !selected ? 0 : 1)
                    .frame(height: 26)
                    .padding(.vertical, 2)
                Text(speed.title)
                    .font(LoopDesign.Typeface.footnote.weight(.semibold))
                    .foregroundStyle(P.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(durationLabel(speed, selected: selected))
                    .font(LoopDesign.Typeface.footnote.monospacedDigit())
                    .foregroundStyle(selected ? P.carbsInk : P.inkMuted)
            }
            .padding(LoopDesign.Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? P.carbs.opacity(0.14) : P.surfaceRaised, in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous).strokeBorder(selected ? P.carbs : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(speed.title), \(durationLabel(speed, selected: selected))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
            .padding(.vertical, LoopDesign.Space.s2)
            Divider()
            Stepper(value: Binding(get: { viewModel.absorptionTime }, set: { viewModel.absorptionTime = $0 }),
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
            .padding(.vertical, LoopDesign.Space.s2)
        }
        .padding(.horizontal, LoopDesign.Space.s3)
        .background(P.surfaceRaised, in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous))
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
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(viewModel.continueButtonDisabled ? P.surfaceSunken : P.carbs,
                            in: RoundedRectangle(cornerRadius: LoopDesign.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.continueButtonDisabled)
        .accessibilityIdentifier("button_Continue")
        .padding(.horizontal, LoopDesign.Space.s4)
        .padding(.vertical, LoopDesign.Space.s2)
        .background(P.surface)
    }

    // MARK: Pieces

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(LoopDesign.Typeface.headline)
            .foregroundStyle(P.ink)
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
        .background(P.statusCritical.opacity(0.12), in: RoundedRectangle(cornerRadius: LoopDesign.Radius.lg, style: .continuous))
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

/// Loop's carb absorption rate over time: rising to its peak at 15% of the absorption time, steady until half way,
/// then falling to nothing (PiecewiseLinearAbsorption in LoopAlgorithm). The area is the same at every length,
/// as the carbs are, so a shorter time draws a taller curve.
struct AbsorptionCurve: Shape {
    /// The absorption time as a share of the axis, 0–1.
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let f = max(0.05, min(1, fraction))
        let width = rect.width * f
        // The trapezoid's area is 0.675 × width × height, so height ∝ 1 / width keeps it equal; capped at the frame.
        let height = min(rect.height, rect.height * 0.3 / f)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.15, y: rect.maxY - height))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.5, y: rect.maxY - height))
        path.addLine(to: CGPoint(x: rect.minX + width, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
