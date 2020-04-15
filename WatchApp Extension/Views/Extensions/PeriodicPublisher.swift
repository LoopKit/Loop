//
//  PeriodicPublisher.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Combine


/// A publisher which emits a value at a defined interval, which can be delayed via acknowledgment.
final class PeriodicPublisher {
    private let didExecute: AnyPublisher<Void, Never>
    private let _acknowledge: () -> Void

    init(interval: TimeInterval, runLoop: RunLoop = .main, mode: RunLoop.Mode = .common) {
        var lastAcknowledged = Date.distantPast
        _acknowledge = { lastAcknowledged = Date() }
        didExecute = Timer.publish(every: interval, on: runLoop, in: mode)
            .autoconnect()
            .filter { date in
                date.timeIntervalSince(lastAcknowledged) >= interval
            }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func acknowledge() {
        _acknowledge()
    }
}

extension PeriodicPublisher: Publisher {
    typealias Output = Void
    typealias Failure = Never

    func receive<S: Subscriber>(subscriber: S) where S.Failure == Failure, S.Input == Output {
        didExecute.receive(subscriber: subscriber)
    }
}
