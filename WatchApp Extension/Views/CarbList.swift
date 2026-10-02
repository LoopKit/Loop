//
//  CarbList.swift
//  Loop
//
//  Created by Pete Schwamb on 9/20/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopAlgorithm

struct CarbList: View {
    @Environment(LoopDataManager.self) var loopManager

    var timeFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return timeFormatter
    }()

    var carbFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .gram)
        formatter.numberFormatter.numberStyle = .none
        return formatter
    }()

    @State var entries: [StoredCarbEntry] = []

    /// Set when a delete could not be journaled — the one case the user must be told about,
    /// because the carb is gone here and still live on the phone.
    @State var warning: String?   // CarbList+PodLoan.swift sets and shows it

    func reloadCarbEntries() async {
        // The same window stock uses: today, or one full absorption interval back, whichever is
        // earlier — so a long-absorbing breakfast is still listed (and deletable) in the afternoon.
        let start = min(Calendar.current.startOfDay(for: Date()), Date(timeIntervalSinceNow: -CarbMath.maximumAbsorptionTimeInterval))
        let store = loanSession?.stack.loopManager.carbStore ?? loopManager.carbStore
        entries = (try? await store.getCarbEntries(start: start)) ?? []
    }

    var activeCarbs: String? {
        guard let activeContext = loopManager.activeContext,
              let activeCarbohydrates = activeContext.activeCarbohydrates
        else {
            return nil
        }

        return carbFormatter.string(from: activeCarbohydrates)
    }

    var totalCarbs: String? {
        let total = entries.reduce(0, { sum, entry in
            return sum + entry.quantity.doubleValue(for: .gram)
        })

        return carbFormatter.string(from: LoopQuantity(unit: .gram, doubleValue: total))
    }

    var body: some View {
        List {
            Section {
                ForEach(entries, id: \.self) { entry in
                    HStack {
                        Text(timeFormatter.string(from: entry.startDate))
                        Spacer()
                        Text(carbFormatter.string(from: entry.quantity) ?? "-")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        podLoanDeleteButton(entry)
                    }
                }
            } header: {
                VStack {
                    HStack {
                        Text("Active Carbs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        Text(activeCarbs ?? "-")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    HStack {
                        Text("Total Carbs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        Text(totalCarbs ?? "-")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    .padding(.bottom, 4)
                }
            } footer: {
                podLoanWarningFooter
            }
        }
        .onAppear {
            Task {
                await reloadCarbEntries()
            }
        }
    }
}
