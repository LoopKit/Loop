//
//  CarbEntryListController.swift
//  WatchApp Extension
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit
import os.log
import WatchKit

class CarbEntryListController: WKInterfaceController, IdentifiableClass {
    @IBOutlet private var table: WKInterfaceTable!

    @IBOutlet private var cobLabel: WKInterfaceLabel!

    @IBOutlet var totalLabel: WKInterfaceLabel!

    @IBOutlet var headerGroup: WKInterfaceGroup!

    private let log = OSLog(category: "CarbEntryListController")

    private lazy var loopManager = ExtensionDelegate.shared().loopManager

    private lazy var carbFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter()
        formatter.numberFormatter.numberStyle = .none
        return formatter
    }()

    private var observers: [Any] = [] {
        didSet {
            for observer in oldValue {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    override func awake(withContext context: Any?) {
        table.setNumberOfRows(0, withRowType: TextRowController.className)
        reloadCarbEntries()
        updateActiveCarbs()
    }

    override func willActivate() {
        observers = [
            NotificationCenter.default.addObserver(forName: CarbStore.carbEntriesDidUpdate, object: loopManager.carbStore, queue: nil) { [weak self] (note) in
                self?.log.default("Received CarbEntriesDidUpdate notification: %{public}@. Updating list", String(describing: note.userInfo ?? [:]))

                DispatchQueue.main.async {
                    self?.reloadCarbEntries()
                }
            },
            NotificationCenter.default.addObserver(forName: LoopDataManager.didUpdateContextNotification, object: loopManager, queue: nil) { [weak self] (note) in
                DispatchQueue.main.async {
                    self?.updateActiveCarbs()
                }
            }
        ]
    }

    override func didDeactivate() {
        observers = []
    }
}


extension CarbEntryListController {
    private func updateActiveCarbs() {
        guard let activeCarbohydrates = loopManager.activeContext?.activeCarbohydrates else {
            return
        }

        cobLabel.setText(carbFormatter.string(from: activeCarbohydrates, for: .gram()))
    }

    private func reloadCarbEntries() {
        let start = min(Calendar.current.startOfDay(for: Date()), Date(timeIntervalSinceNow: -loopManager.carbStore.maximumAbsorptionTimeInterval))

        loopManager.carbStore.getCarbEntries(start: start) { (result) in
            switch result {
            case .success(let entries):
                DispatchQueue.main.async {
                    self.setCarbEntries(entries)
                }
            case .failure(let error):
                self.log.error("Failed to fetch carb entries: %{public}@", String(describing: error))
            }
        }
    }

    private func setCarbEntries(_ entries: [StoredCarbEntry]) {
        dispatchPrecondition(condition: .onQueue(.main))

        table.setNumberOfRows(entries.count, withRowType: TextRowController.className)

        var total = 0.0

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let unit = loopManager.carbStore.preferredUnit ?? .gram()

        for (index, entry) in entries.reversed().enumerated() {
            guard let row = table.rowController(at: index) as? TextRowController else {
                continue
            }

            total += entry.quantity.doubleValue(for: unit)

            row.textLabel.setText(timeFormatter.string(from: entry.startDate))
            row.detailTextLabel.setText(carbFormatter.string(from: entry.quantity, for: unit))
        }

        totalLabel.setText(carbFormatter.string(from: HKQuantity(unit: unit, doubleValue: total), for: unit))
    }
}
