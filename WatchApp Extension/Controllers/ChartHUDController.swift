//
//  ChartHUDController.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/26/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import WatchKit
import WatchConnectivity
import CGMBLEKit
import LoopKit
import HealthKit
import SpriteKit
import os.log

final class ChartHUDController: HUDInterfaceController, WKCrownDelegate {
    private enum TableRow: Int, CaseIterable {
        case iob
        case cob
        case netBasal
        case reservoirVolume

        var title: String {
            switch self {
            case .iob:
                return NSLocalizedString("Active Insulin", comment: "HUD row title for IOB")
            case .cob:
                return NSLocalizedString("Active Carbs", comment: "HUD row title for COB")
            case .netBasal:
                return NSLocalizedString("Net Basal Rate", comment: "HUD row title for Net Basal Rate")
            case .reservoirVolume:
                return NSLocalizedString("Reservoir Volume", comment: "HUD row title for remaining reservoir volume")
            }
        }

        var isLast: Bool {
            return self == TableRow.allCases.last
        }
    }

    @IBOutlet private weak var table: WKInterfaceTable!

    @IBOutlet private weak var glucoseScene: WKInterfaceSKScene!
    @IBAction private func setChartWindow1Hour() {
        scene.visibleDuration = .hours(2)
    }
    @IBAction private func setChartWindow2Hours() {
        scene.visibleDuration = .hours(4)
    }
    @IBAction private func setChartWindow3Hours() {
        scene.visibleDuration = .hours(6)
    }
    private let scene = GlucoseChartScene()
    private var timer: Timer? {
        didSet {
            oldValue?.invalidate()
        }
    }
    private let log = OSLog(category: "ChartHUDController")
    private var hasInitialActivation = false

    private var observers: [Any] = [] {
        didSet {
            for observer in oldValue {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    override init() {
        super.init()

        glucoseScene.presentScene(scene)
    }

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        table.setNumberOfRows(TableRow.allCases.count, withRowType: HUDRowController.className)
    }

    override func didAppear() {
        super.didAppear()

        if glucoseScene.isPaused {
            log.default("didAppear() unpausing")
            glucoseScene.isPaused = false
        } else {
            log.default("didAppear() not paused")
            glucoseScene.isPaused = false
        }

        // Force an update when our pixels need to move
        let pixelsWide = scene.size.width * WKInterfaceDevice.current().screenScale
        let pixelInterval = scene.visibleDuration / TimeInterval(pixelsWide)

        timer = Timer.scheduledTimer(withTimeInterval: pixelInterval, repeats: true) { [weak self] _ in
            self?.log.default("Timer fired, triggering update")
            self?.scene.setNeedsUpdate()
        }

        if #available(watchOSApplicationExtension 5.0, *) {
            scene.textInsets.left = max(scene.textInsets.left, systemMinimumLayoutMargins.leading)
            scene.textInsets.right = max(scene.textInsets.right, systemMinimumLayoutMargins.trailing)
        }
    }

    override func willDisappear() {
        super.willDisappear()

        log.default("willDisappear")

        timer = nil
    }

    override func willActivate() {
        super.willActivate()

        observers = [
            NotificationCenter.default.addObserver(forName: GlucoseStore.glucoseSamplesDidChange, object: loopManager.glucoseStore, queue: nil) { [weak self] (note) in
                self?.log.default("Received GlucoseSamplesDidChange notification: %{public}@. Updating chart", String(describing: note.userInfo ?? [:]))

                DispatchQueue.main.async {
                    self?.updateGlucoseChart()
                }
            }
        ]

        if glucoseScene.isPaused {
            log.default("willActivate() unpausing")
            glucoseScene.isPaused = false
        } else {
            log.default("willActivate()")
        }

        if !hasInitialActivation && UserDefaults.standard.startOnChartPage {
            log.default("Switching to startOnChartPage")
            becomeCurrentPage()
        }

        hasInitialActivation = true

        loopManager.requestGlucoseBackfillIfNecessary()
    }

    override func didDeactivate() {
        super.didDeactivate()

        observers = []

        log.default("didDeactivate() pausing")
        glucoseScene.isPaused = true
    }

    override func update() {
        super.update()

        guard let activeContext = loopManager.activeContext else {
            return
        }

        for row in TableRow.allCases {
            let cell = table.rowController(at: row.rawValue) as! HUDRowController
            cell.setTitle(row.title)
            cell.setIsLastRow(row.isLast)
            if #available(watchOSApplicationExtension 5.0, *) {
                cell.setContentInset(systemMinimumLayoutMargins)
            }

            switch row {
            case .iob:
                cell.setActiveInsulin(activeContext.activeInsulin)
            case .cob:
                cell.setActiveCarbohydrates(activeContext.activeCarbohydrates)
            case .netBasal:
                cell.setNetTempBasalDose(activeContext.lastNetTempBasalDose)
            case .reservoirVolume:
                cell.setReservoirVolume(activeContext.reservoirVolume)
            }
        }

        if glucoseScene.isPaused {
            log.default("update() unpausing")
            glucoseScene.isPaused = false
        }

        updateGlucoseChart()
    }

    private func updateGlucoseChart() {
        loopManager.generateChartData { chartData in
            DispatchQueue.main.async {
                self.scene.data = chartData
                self.scene.setNeedsUpdate()
            }
        }
    }

    override func table(_ table: WKInterfaceTable, didSelectRowAt rowIndex: Int) {
        guard table == self.table, case .cob? = TableRow(rawValue: rowIndex) else {
            return
        }

        presentController(withName: CarbEntryListController.className, context: nil)
    }
}
