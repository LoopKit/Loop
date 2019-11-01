//
//  MicrobolusView.swift
//  Loop
//
//  Created by Ivan Valkou on 31.10.2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine

struct MicrobolusView: View {
    final class ViewModel: ObservableObject {
        @Published var microbolusesWithCOB: Bool
        @Published var withCOBValue: Double
        @Published var microbolusesWithoutCOB: Bool
        @Published var withoutCOBValue: Double

        @Published fileprivate var pickerWithCOBIndex: Int
        @Published fileprivate var pickerWithoutCOBIndex: Int

        fileprivate let values = stride(from: 30, to: 301, by: 5).map { $0 }

        private var cancelable: AnyCancellable!

        init(microbolusesWithCOB: Bool, withCOBValue: Double, microbolusesWithoutCOB: Bool, withoutCOBValue: Double) {
            self.microbolusesWithCOB = microbolusesWithCOB
            self.withCOBValue = withCOBValue
            self.microbolusesWithoutCOB = microbolusesWithoutCOB
            self.withoutCOBValue = withoutCOBValue

            pickerWithCOBIndex = values.firstIndex(of: Int(withCOBValue)) ?? 0
            pickerWithoutCOBIndex = values.firstIndex(of: Int(withoutCOBValue)) ?? 0

            let withCOBCancelable = $pickerWithCOBIndex
                .map { Double(self.values[$0]) }
                .sink { self.withCOBValue = $0 }

            let withoutCOBCancelable = $pickerWithoutCOBIndex
                .map { Double(self.values[$0]) }
                .sink { self.withoutCOBValue = $0 }

            cancelable = AnyCancellable {
                withCOBCancelable.cancel()
                withoutCOBCancelable.cancel()
            }
        }

        func publisher() -> AnyPublisher<(Bool, Double, Bool, Double), Never> {
            Publishers.CombineLatest4($microbolusesWithCOB, $withCOBValue, $microbolusesWithoutCOB, $withoutCOBValue)
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
            }

        }
        .navigationBarTitle("Microboluses")
    }
}

struct MicrobolusView_Previews: PreviewProvider {
    static var previews: some View {
        MicrobolusView(viewModel: .init(
            microbolusesWithCOB: false,
            withCOBValue: 30,
            microbolusesWithoutCOB: false,
            withoutCOBValue: 30)
        )
            .environment(\.colorScheme, .dark)
    }
}
