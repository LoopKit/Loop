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
    typealias Result = (microbolusesWithCOB: Bool, withCOBValue: Double, microbolusesWithoutCOB: Bool, withoutCOBValue: Double, safeMode: Microbolus.SafeMode)

    final class ViewModel: ObservableObject {
        @Published var microbolusesWithCOB: Bool
        @Published var withCOBValue: Double
        @Published var microbolusesWithoutCOB: Bool
        @Published var withoutCOBValue: Double
        @Published var safeMode: Microbolus.SafeMode

        @Published fileprivate var pickerWithCOBIndex: Int
        @Published fileprivate var pickerWithoutCOBIndex: Int

        fileprivate let values = stride(from: 30, to: 301, by: 5).map { $0 }

        private var cancellable: AnyCancellable!

        init(microbolusesWithCOB: Bool, withCOBValue: Double, microbolusesWithoutCOB: Bool, withoutCOBValue: Double, safeMode: Microbolus.SafeMode) {
            self.microbolusesWithCOB = microbolusesWithCOB
            self.withCOBValue = withCOBValue
            self.microbolusesWithoutCOB = microbolusesWithoutCOB
            self.withoutCOBValue = withoutCOBValue
            self.safeMode = safeMode

            pickerWithCOBIndex = values.firstIndex(of: Int(withCOBValue)) ?? 0
            pickerWithoutCOBIndex = values.firstIndex(of: Int(withoutCOBValue)) ?? 0

            let withCOBCancellable = $pickerWithCOBIndex
                .map { Double(self.values[$0]) }
                .sink { self.withCOBValue = $0 }

            let withoutCOBCancellable = $pickerWithoutCOBIndex
                .map { Double(self.values[$0]) }
                .sink { self.withoutCOBValue = $0 }

            cancellable = AnyCancellable {
                withCOBCancellable.cancel()
                withoutCOBCancellable.cancel()
            }
        }

        func changes() -> AnyPublisher<Result, Never> {
            // Publishers.CombineLatest5
            Publishers.CombineLatest(
                Publishers.CombineLatest4(
                    $microbolusesWithCOB,
                    $withCOBValue,
                    $microbolusesWithoutCOB,
                    $withoutCOBValue
                ),
                $safeMode
            )
            .map { ($0.0.0, $0.0.1, $0.0.2, $0.0.3, $0.1) }
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

                    Text("Caution! Microboluses has the potential to reduce the safety effects of other mitigations, like max temp basal rate. Please be careful!\nThe actual size of the microbolus is always limited to half the recommended bolus.")
                        .font(.caption)
                }

            }
            Section(footer:
                Text("This is the maximum minutes of basal that can be delivered as a single Microbolus with uncovered COB. This gives the ability to make Microboluses more aggressive if you choose. It is recommended that the value is set to start at 30, in line with the default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes.")
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

            if viewModel.microbolusesWithCOB {
                Section(footer:
                    Text("This is the maximum minutes of basal that can be delivered as a single Microbolus without COB.")
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
                    Text("• If Enabled and the predicted glucose after 15 minutes is less than the current glucose, Microboluses is not allowed.\n• If Limited and the predicted glucose after 15 minutes is less than the current glucose, the Maximum Microbolus Size is limited to 30 basal minutes.\n• If Disabled, there are no restrictions.")
                ) {
                    Picker(selection: $viewModel.safeMode, label: Text("Safe Mode")) {
                        ForEach(Microbolus.SafeMode.allCases, id: \.self) { value in
                            Text("\(value.displayName)").tag(value)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
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
            safeMode: .enabled
            )
        )
            .environment(\.colorScheme, .dark)
    }
}
