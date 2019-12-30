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
        @Published fileprivate var microbolusesWithCOB: Bool
        @Published fileprivate var microbolusesWithoutCOB: Bool
        @Published fileprivate var partialApplication: Double
        @Published fileprivate var microbolusesMinimumBolusSize: Double
        @Published fileprivate var openBolusScreen: Bool
        @Published fileprivate var disableByOverride: Bool
        @Published fileprivate var lowerBound: String
        @Published fileprivate var pickerMinimumBolusSizeIndex: Int
        @Published fileprivate var partialApplicationIndex: Int
        @Published fileprivate var event: String? = nil

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

        init(settings: Microbolus.Settings, glucoseUnit: HKUnit, eventPublisher: AnyPublisher<Microbolus.Event?, Never>? = nil) {
            self.microbolusesWithCOB = settings.enabled
            self.microbolusesWithoutCOB = settings.enabledWithoutCarbs
            self.partialApplication = settings.partialApplication
            self.microbolusesMinimumBolusSize = settings.minimumBolusSize
            self.openBolusScreen = settings.shouldOpenBolusScreen
            self.disableByOverride = settings.disableByOverride
            self.lowerBound = formatter.string(from: settings.overrideLowerBound) ?? ""
            self.unit = glucoseUnit

            pickerMinimumBolusSizeIndex = minimumBolusSizeValues.firstIndex(of: Double(settings.minimumBolusSize)) ?? 0
            partialApplicationIndex = partialApplicationValues.firstIndex(of: Double(settings.partialApplication)) ?? 0

            let microbolusesMinimumBolusSizeCancellable = $pickerMinimumBolusSizeIndex
                .map { Double(self.minimumBolusSizeValues[$0]) }
                .sink { self.microbolusesMinimumBolusSize = $0 }

            let partialApplicationCancellable = $partialApplicationIndex
                .map { Double(self.partialApplicationValues[$0]) }
                .sink { self.partialApplication = $0 }

            let lastEventCancellable = eventPublisher?
                .map { $0?.description }
                .receive(on: DispatchQueue.main)
                .sink { self.event = $0 }


            cancellable = AnyCancellable {
                microbolusesMinimumBolusSizeCancellable.cancel()
                partialApplicationCancellable.cancel()
                lastEventCancellable?.cancel()
            }
        }

        func changes() -> AnyPublisher<Microbolus.Settings, Never> {
            let lowerBoundPublisher = $lowerBound
                .map { value -> Double in self.formatter.number(from: value)?.doubleValue ?? 0 }

            return Publishers.CombineLatest(
                Publishers.CombineLatest4(
                    $microbolusesWithCOB,
                    $microbolusesWithoutCOB,
                    $partialApplication,
                    $microbolusesMinimumBolusSize
                ),
                Publishers.CombineLatest3(
                    $openBolusScreen,
                    $disableByOverride,
                    lowerBoundPublisher
                )
            )
                .map {
                    Microbolus.Settings(
                        enabled: $0.0.0,
                        enabledWithoutCarbs: $0.0.1,
                        partialApplication: $0.0.2,
                        minimumBolusSize: $0.0.3,
                        shouldOpenBolusScreen: $0.1.0,
                        disableByOverride: $0.1.1,
                        overrideLowerBound: $0.1.2
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
            switchSection
            partialApplicationSection
            temporaryOverridesSection
            otherOptionsSection
            if viewModel.event != nil {
                lastEventSection
            }
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

    private var switchSection: some View {
        Section {
            Toggle (isOn: $viewModel.microbolusesWithCOB) {
                Text("Enable With Carbs")
            }

            Toggle (isOn: $viewModel.microbolusesWithoutCOB) {
                Text("Enable Without Carbs")
            }
        }
    }

    private var partialApplicationSection: some View {
        Section(footer:
            Text("What part of the recommended bolus will be applied automatically.")
        ) {
            Picker(selection: $viewModel.partialApplicationIndex, label: Text("Partial Bolus Application")) {
                ForEach(0 ..< viewModel.partialApplicationValues.count) { index in
                    Text(String(format: "%.0f %%", self.viewModel.partialApplicationValues[index] * 100)).tag(index)
                }
            }
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

    private var lastEventSection: some View {
        Section(header: Text("Last Event").font(.headline)) {
            Text(viewModel.event ?? "No event")
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
