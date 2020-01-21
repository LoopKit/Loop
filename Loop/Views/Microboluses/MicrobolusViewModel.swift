//
//  MicrobolusViewModel.swift
//  Loop
//
//  Created by Ivan Valkou on 21.01.2020.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Combine
import LoopCore
import LoopKit
import HealthKit

extension MicrobolusView {
    final class ViewModel: ObservableObject {
        @Published var microbolusesWithCOB: Bool
        @Published var microbolusesWithoutCOB: Bool
        @Published var partialApplication: Double
        @Published var microbolusesMinimumBolusSize: Double
        @Published var openBolusScreen: Bool
        @Published var disableByOverride: Bool
        @Published var lowerBound: String
        @Published var pickerMinimumBolusSizeIndex: Int
        @Published var partialApplicationIndex: Int
        @Published var event: String? = nil

        // @ToDo: Should be able to get the to limit from the settings but for now defult to a low value
        let minimumBolusSizeValues = stride(from: 0.0, to: 0.51, by: 0.05).map { $0 }
        let partialApplicationValues = stride(from: 0.1, to: 1.01, by: 0.05).map { $0 }

        private var cancellable: AnyCancellable!
        let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }()

        let unit: HKUnit

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
}
