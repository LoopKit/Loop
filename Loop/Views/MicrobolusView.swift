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

struct MicrobolusView: View {
    final class ViewModel: ObservableObject {
        @Published var microbolusesWithCOB: Bool
        @Published var withCOBValue: Double
        @Published var microbolusesWithoutCOB: Bool
        @Published var withoutCOBValue: Double
        @Published var safeMode: Microbolus.SafeMode
        @Published var microbolusesMinimumBolusSize: Double
        @Published var openBolusScreen: Bool

        @Published fileprivate var pickerWithCOBIndex: Int
        @Published fileprivate var pickerWithoutCOBIndex: Int
        @Published fileprivate var pickerMinimumBolusSizeIndex: Int

        fileprivate let values = stride(from: 30, to: 301, by: 5).map { $0 }
        // @ToDo: Should be able to get the to limit from the settings but for now defult to a low value
        fileprivate let minimumBolusSizeValues = stride(from: 0.0, to: 0.51, by: 0.05).map { $0 }

        private var cancellable: AnyCancellable!

        init(microbolusesWithCOB: Bool, withCOBValue: Double, microbolusesWithoutCOB: Bool, withoutCOBValue: Double, safeMode: Microbolus.SafeMode, microbolusesMinimumBolusSize: Double, openBolusScreen: Bool) {
            self.microbolusesWithCOB = microbolusesWithCOB
            self.withCOBValue = withCOBValue
            self.microbolusesWithoutCOB = microbolusesWithoutCOB
            self.withoutCOBValue = withoutCOBValue
            self.safeMode = safeMode
            self.microbolusesMinimumBolusSize = microbolusesMinimumBolusSize
            self.openBolusScreen = openBolusScreen

            pickerWithCOBIndex = values.firstIndex(of: Int(withCOBValue)) ?? 0
            pickerWithoutCOBIndex = values.firstIndex(of: Int(withoutCOBValue)) ?? 0
            pickerMinimumBolusSizeIndex = minimumBolusSizeValues.firstIndex(of: Double(microbolusesMinimumBolusSize)) ?? 0

            let withCOBCancellable = $pickerWithCOBIndex
                .map { Double(self.values[$0]) }
                .sink { self.withCOBValue = $0 }

            let withoutCOBCancellable = $pickerWithoutCOBIndex
                .map { Double(self.values[$0]) }
                .sink { self.withoutCOBValue = $0 }

            let microbolusesMinimumBolusSizeCancellable = $pickerMinimumBolusSizeIndex
                .map { Double(self.minimumBolusSizeValues[$0]) }
                .sink { self.microbolusesMinimumBolusSize = $0 }

            cancellable = AnyCancellable {
                withCOBCancellable.cancel()
                withoutCOBCancellable.cancel()
                microbolusesMinimumBolusSizeCancellable.cancel()
            }
        }

        func changes() -> AnyPublisher<Microbolus.Settings, Never> {
            Publishers.CombineLatest4(
                Publishers.CombineLatest4(
                    $microbolusesWithCOB,
                    $withCOBValue,
                    $microbolusesWithoutCOB,
                    $withoutCOBValue
                ),
                $safeMode,
                $microbolusesMinimumBolusSize,
                $openBolusScreen
            )
                .map {
                    Microbolus.Settings(
                        enabled: $0.0.0,
                        size: $0.0.1,
                        enabledWithoutCarbs: $0.0.2,
                        sizeWithoutCarb: $0.0.3,
                        safeMode: $0.1,
                        minimumBolusSize: $0.2,
                        shouldOpenBolusScreen: $0.3
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
            Section {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .padding(.trailing)

                    Text("Caution! Microboluses have potential to reduce the safety effects of other mitigations like max temp basal rate. Please be careful!\nThe actual size of a microbolus is always limited to half the recommended bolus.")
                        .font(.caption)
                }

            }
            Section(footer:
                Text("This is the maximum minutes of basal that can be delivered as a single microbolus with uncovered COB. This allows you to make microboluses behave more aggressively. It is recommended that this value is set to start at 30, in line with default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes.")
            ) {
                Toggle (isOn: $viewModel.microbolusesWithCOB) {
                    Text("Enable With Carbs")
                }

                Picker(selection: $viewModel.pickerWithCOBIndex, label: Text("Maximum Size")) {
                    ForEach(0 ..< viewModel.values.count) { index in
                        Text("\(self.viewModel.values[index])").tag(index)
                    }
                }
            }

            Section(footer:
                Text("This is the maximum minutes of basal that can be delivered as a single microbolus without COB.")
            ) {
                Toggle (isOn: $viewModel.microbolusesWithoutCOB) {
                    Text("Enable Without Carbs")
                }
                Picker(selection: $viewModel.pickerWithoutCOBIndex, label: Text("Maximum Size")) {
                    ForEach(0 ..< viewModel.values.count) { index in
                        Text("\(self.viewModel.values[index])").tag(index)
                    }
                }
            }

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
        .navigationBarTitle("Microboluses")
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
            microbolusesWithCOB: true,
            withCOBValue: 30,
            microbolusesWithoutCOB: false,
            withoutCOBValue: 30,
            safeMode: .enabled,
            microbolusesMinimumBolusSize: 0.0,
            openBolusScreen: false
            )
        )
            .environment(\.colorScheme, .dark)
            .previewLayout(.sizeThatFits)
    }
}
