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

    private func reloadCarbEntries() async {
        let start = min(Calendar.current.startOfDay(for: Date()), Date(timeIntervalSinceNow: -CarbMath.maximumAbsorptionTimeInterval))
        entries = (try? await loopManager.carbStore.getCarbEntries(start: start)) ?? []
    }

    var activeCarbs: String? {
        guard let activeContext = loopManager.displayContext,
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
            }
        }
        .onAppear {
            loopManager.requestCarbBackfill()
            Task {
                await reloadCarbEntries()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: LoopDataManager.didUpdateContextNotification)) { _ in
            loopManager.requestCarbBackfill()
        }
        .onReceive(NotificationCenter.default.publisher(for: CarbStore.carbEntriesDidChange, object: loopManager.carbStore)
            .receive(on: DispatchQueue.main)) { _ in
            Task {
                await reloadCarbEntries()
            }
        }
    }
}
