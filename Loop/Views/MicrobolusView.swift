//
//  MicrobolusView.swift
//  Loop
//
//  Created by Ivan Valkou on 31.10.2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine
import LoopCore
import LoopKit
import HealthKit

struct MicrobolusView: View {
    final class ViewModel: ObservableObject {
        @Published var microbolusesWithCOB: Bool
        @Published var withCOBValue: Double
        @Published var microbolusesWithoutCOB: Bool
        @Published var withoutCOBValue: Double
        @Published var partialApplication: Double
        @Published var safeMode: Microbolus.SafeMode
        @Published var microbolusesMinimumBolusSize: Double
        @Published var openBolusScreen: Bool
        @Published var disableByOverride: Bool
        @Published var lowerBound: String

        @Published fileprivate var pickerWithCOBIndex: Int
        @Published fileprivate var pickerWithoutCOBIndex: Int
        @Published fileprivate var pickerMinimumBolusSizeIndex: Int
        @Published fileprivate var partialApplicationIndex: Int

        fileprivate let values = stride(from: 30, to: 301, by: 5).map { $0 } + [1440] // + 1 day
        // @ToDo: Should be able to get the to limit from the settings but for now defult to a low value
        fileprivate let minimumBolusSizeValues = stride(from: 0.0, to: 0.51, by: 0.05).map { $0 }
        fileprivate let partialApplicationValues = stride(from: 0.1, to: 1.01, by: 0.05).map { $0 }

        private var cancellable: AnyCancellable!
        fileprivate let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }()

        fileprivate let unit: HKUnit

        init(settings: Microbolus.Settings, glucoseUnit: HKUnit) {
            self.microbolusesWithCOB = settings.enabled
            self.withCOBValue = settings.size
            self.microbolusesWithoutCOB = settings.enabledWithoutCarbs
            self.withoutCOBValue = settings.sizeWithoutCarbs
            self.partialApplication = settings.partialApplication
            self.safeMode = settings.safeMode
            self.microbolusesMinimumBolusSize = settings.minimumBolusSize
            self.openBolusScreen = settings.shouldOpenBolusScreen
            self.disableByOverride = settings.disableByOverride
            self.lowerBound = formatter.string(from: settings.overrideLowerBound) ?? ""
            self.unit = glucoseUnit

            pickerWithCOBIndex = values.firstIndex(of: Int(settings.size)) ?? 0
            pickerWithoutCOBIndex = values.firstIndex(of: Int(settings.sizeWithoutCarbs)) ?? 0
            pickerMinimumBolusSizeIndex = minimumBolusSizeValues.firstIndex(of: Double(settings.minimumBolusSize)) ?? 0
            partialApplicationIndex = partialApplicationValues.firstIndex(of: Double(settings.partialApplication)) ?? 0

            let withCOBCancellable = $pickerWithCOBIndex
                .map { Double(self.values[$0]) }
                .sink { self.withCOBValue = $0 }

            let withoutCOBCancellable = $pickerWithoutCOBIndex
                .map { Double(self.values[$0]) }
                .sink { self.withoutCOBValue = $0 }


            let microbolusesMinimumBolusSizeCancellable = $pickerMinimumBolusSizeIndex
            .map { Double(self.minimumBolusSizeValues[$0]) }
            .sink { self.microbolusesMinimumBolusSize = $0 }

            let partialApplicationCancellable = $partialApplicationIndex
            .map { Double(self.partialApplicationValues[$0]) }
            .sink { self.partialApplication = $0 }

            cancellable = AnyCancellable {
                withCOBCancellable.cancel()
                withoutCOBCancellable.cancel()
                microbolusesMinimumBolusSizeCancellable.cancel()
                partialApplicationCancellable.cancel()
            }
        }

        func changes() -> AnyPublisher<Microbolus.Settings, Never> {
            let lowerBoundPublisher = $lowerBound
                .map { value -> Double in self.formatter.number(from: value)?.doubleValue ?? 0 }

            return Publishers.CombineLatest4(
                Publishers.CombineLatest4(
                    $microbolusesWithCOB,
                    $withCOBValue,
                    $microbolusesWithoutCOB,
                    $withoutCOBValue
                ),
                Publishers.CombineLatest4(
                    $partialApplication,
                    $safeMode,
                    $microbolusesMinimumBolusSize,
                    $openBolusScreen
                ),
                $disableByOverride,
                lowerBoundPublisher
            )
                .map {
                    Microbolus.Settings(
                        enabled: $0.0.0,
                        size: $0.0.1,
                        enabledWithoutCarbs: $0.0.2,
                        sizeWithoutCarb: $0.0.3,
                        partialApplication: $0.1.0,
                        safeMode: $0.1.1,
                        minimumBolusSize: $0.1.2,
                        shouldOpenBolusScreen: $0.1.3,
                        disableByOverride: $0.2,
                        overrideLowerBound: $0.3
                    )
                }
                .eraseToAnyPublisher()
        }
    }

    @ObservedObject var viewModel: ViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            topSection
            partialApplicationSection
            withCobSection
            withoutCobSection
            safeModeSection
            temporaryOverridesSection
            otherOptionsSection
        }
        .navigationBarTitle("Microboluses")
        .modifier(AdaptsToSoftwareKeyboard())
    }

    private var topSection: some View {
        Section {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .padding(.trailing)

                Text("Caution! Microboluses have potential to reduce the safety effects of other mitigations like max temp basal rate. Please be careful!\nThe actual size of a microbolus is always limited to the partial application of recommended bolus.")
                    .font(.caption)
            }

        }
    }

    private var withCobSection: some View {
        Section(footer:
            Text("This is the maximum minutes of basal that can be delivered as a single microbolus with uncovered COB. This allows you to make microboluses behave more aggressively. It is recommended that this value is set to start at 30, in line with default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes.")
        ) {
            Toggle (isOn: $viewModel.microbolusesWithCOB) {
                Text("Enable With Carbs")
            }

            Picker(selection: $viewModel.pickerWithCOBIndex, label: Text("Maximum Size")) {
                ForEach(0 ..< viewModel.values.count) { index in
                    if index == self.viewModel.values.count - 1 {
                        Text("Not limited").tag(index)
                    } else {
                        Text("\(self.viewModel.values[index])").tag(index)
                    }
                }
            }
        }
    }

    private var withoutCobSection: some View {
        Section(footer:
            Text("This is the maximum minutes of basal that can be delivered as a single microbolus without COB.")
        ) {
            Toggle (isOn: $viewModel.microbolusesWithoutCOB) {
                Text("Enable Without Carbs")
            }
            Picker(selection: $viewModel.pickerWithoutCOBIndex, label: Text("Maximum Size")) {
                ForEach(0 ..< viewModel.values.count) { index in
                    if index == self.viewModel.values.count - 1 {
                        Text("Not limited").tag(index)
                    } else {
                        Text("\(self.viewModel.values[index])").tag(index)
                    }
                }
            }
        }
    }

    private var partialApplicationSection: some View {
        Section(footer:
            Text("What part of the recommended bolus will be applied automatically.")
        ) {
            Picker(selection: $viewModel.partialApplicationIndex, label: Text("Partial Application")) {
                ForEach(0 ..< viewModel.partialApplicationValues.count) { index in
                    Text(String(format: "%.0f %%", self.viewModel.partialApplicationValues[index] * 100)).tag(index)
                }
            }
        }
    }

    private var safeModeSection: some View {
        Section(header: Text("Safe Mode").font(.headline), footer:
            Text("• If Enabled and predicted glucose in 15 minutes is lower than current glucose, microboluses are not allowed.\n• If Limited and the predicted glucose in 15 minutes is lower than current glucose, the maximum microbolus size is limited to 30 basal minutes.\n• If Disabled, there are no restrictions.")
        ) {
            Picker(selection: $viewModel.safeMode, label: Text("Safe Mode")) {
                ForEach(Microbolus.SafeMode.allCases, id: \.self) { value in
                    Text("\(value.displayName)").tag(value)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }


    private var temporaryOverridesSection: some View {
        Section(header: Text("Temporary overrides").font(.headline)) {
            Toggle (isOn: $viewModel.disableByOverride) {
                Text("Disable MB by enabling temporary override")
            }

            VStack(alignment: .leading) {
                Text("If the override's target range starts at the given value or more").font(.caption)
                HStack {
                    TextField("0", text: $viewModel.lowerBound)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)

                    Text(viewModel.unit.localizedShortUnitString)
                }
            }
        }
    }

    private var otherOptionsSection: some View {
        Section(header: Text("Other Options").font(.headline), footer:
            Text("This is the minimum microbolus size in units that will be delivered. Only if the microbolus calculated is equal to or greater than this number of units will a bolus be delivered.")
        ) {
            Toggle (isOn: $viewModel.openBolusScreen) {
                Text("Open Bolus screen after Carbs")
            }

            Picker(selection: $viewModel.pickerMinimumBolusSizeIndex, label: Text("Minimum Bolus Size")) {
                ForEach(0 ..< viewModel.minimumBolusSizeValues.count) { index in Text(String(format: "%.2f U", self.viewModel.minimumBolusSizeValues[index])).tag(index)
                }
            }
        }
    }
}

private extension Microbolus.SafeMode {
    var displayName: String {
        switch self {
        case .enabled:
            return "Enabled"
        case .limited:
            return "Limited"
        case .disabled:
            return "Disabled"
        }
    }
}

struct MicrobolusView_Previews: PreviewProvider {
    static var previews: some View {
        MicrobolusView(viewModel: .init(
            settings: Microbolus.Settings(),
            glucoseUnit: HKUnit(from: "mmol/L")
            )
        )
            .environment(\.colorScheme, .dark)
            .previewLayout(.fixed(width: 375, height: 1300))
    }
}

// MARK: - Helpers

struct AdaptsToSoftwareKeyboard: ViewModifier {
    @State var currentHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, currentHeight).animation(.easeOut(duration: 0.25))
            .edgesIgnoringSafeArea(currentHeight == 0 ? Edge.Set() : .bottom)
            .onAppear(perform: subscribeToKeyboardChanges)
    }

    private let keyboardHeightOnOpening = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillShowNotification)
        .map { $0.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! CGRect }
        .map { $0.height }


    private let keyboardHeightOnHiding = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillHideNotification)
        .map {_ in return CGFloat(0) }

    private func subscribeToKeyboardChanges() {
        _ = Publishers.Merge(keyboardHeightOnOpening, keyboardHeightOnHiding)
            .subscribe(on: DispatchQueue.main)
            .sink { height in
                if self.currentHeight == 0 || height == 0 {
                    self.currentHeight = height
                }
        }
    }
}
