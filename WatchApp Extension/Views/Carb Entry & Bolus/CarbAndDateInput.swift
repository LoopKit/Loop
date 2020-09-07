//
//  CarbAndDateInput.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct CarbAndDateInput: View {
    @Binding var lastEntryDate: Date
    @Binding var amount: Int
    @Binding var date: Date
    var initialDate: Date
    @Binding var inputMode: CarbEntryInputMode

    private let carbIncrement = 5
    private let validCarbAmountRange = 0...100
    private let dateIncrement = TimeInterval(minutes: 15)
    private let validDateDeltaRange = TimeInterval(hours: -8)...TimeInterval(hours: 4)
    private var validDateRange: ClosedRange<Date> {
        initialDate.addingTimeInterval(validDateDeltaRange.lowerBound)...initialDate.addingTimeInterval(validDateDeltaRange.upperBound)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var digitalCrownRotation: Binding<Int> {
        switch inputMode {
        case .carbs:
            return Binding(
                get: { self.amount },
                set: {
                    if $0 != self.amount {
                        self.lastEntryDate = Date()
                        self.amount = $0
                    }
                }
            )
        case .date:
            return Binding(
                get: { Int(self.date.timeIntervalSince(self.initialDate).minutes) },
                set: {
                    let date = self.initialDate.addingTimeInterval(.minutes(Double($0)))
                    if date != self.date {
                        self.lastEntryDate = Date()
                        self.date = date
                    }
                }
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CarbAmountInput(amount: $amount, increment: increment, decrement: decrement)
            dateLabel
        }.onTapGesture {
            self.inputMode.toggle()
        }
        .focusable()
        .digitalCrownRotation(digitalCrownRotation, over: digitalCrownRange, rotationsPerIncrement: 1/24)
    }

    var digitalCrownRange: ClosedRange<Int> {
        switch inputMode {
        case .carbs:
            return validCarbAmountRange
        case .date:
            return Int(validDateDeltaRange.lowerBound.minutes)...Int(validDateDeltaRange.upperBound.minutes)
        }
    }

    var dateLabel: some View {
        Text("\(date, formatter: Self.dateFormatter)")
            .font(Font.footnote)
            .foregroundColor(inputMode == .date ? .carbs : Color(.lightGray))
    }

    private func increment() {
        self.lastEntryDate = Date()

        switch self.inputMode {
        case .carbs:
            self.amount = (self.amount + carbIncrement).clamped(to: validCarbAmountRange)
        case .date:
            self.date = self.date.addingTimeInterval(dateIncrement).clamped(to: validDateRange)
        }

        WKInterfaceDevice.current().play(.directionUp)
    }

    private func decrement() {
        self.lastEntryDate = Date()

        switch self.inputMode {
        case .carbs:
            self.amount = (self.amount - carbIncrement).clamped(to: validCarbAmountRange)
        case .date:
            self.date = self.date.addingTimeInterval(-dateIncrement).clamped(to: validDateRange)
        }

        WKInterfaceDevice.current().play(.directionDown)
    }
}
