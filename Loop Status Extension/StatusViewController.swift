//
//  StatusViewController.swift
//  Loop Status Extension
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import CoreData
import HealthKit
import LoopKit
import LoopUI
import NotificationCenter
import UIKit
import SwiftCharts

class StatusViewController: UIViewController, NCWidgetProviding {

    @IBOutlet weak var hudView: HUDView! {
        didSet {
            hudView.loopCompletionHUD.stateColors = .loopStatus
            hudView.glucoseHUD.stateColors = .cgmStatus
            hudView.glucoseHUD.tintColor = .glucoseTintColor
            hudView.basalRateHUD.tintColor = .doseTintColor
            hudView.reservoirVolumeHUD.stateColors = .pumpStatus
            hudView.batteryHUD.stateColors = .pumpStatus
        }
    }
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var insulinLabel: UILabel!
    @IBOutlet weak var glucoseChartContentView: LoopUI.ChartContainerView!

    private lazy var charts: StatusChartsManager = {
        let charts = StatusChartsManager(
            colors: ChartColorPalette(
                axisLine: .axisLineColor,
                axisLabel: .axisLabelColor,
                grid: .gridColor,
                glucoseTint: .glucoseTintColor,
                doseTint: .doseTintColor
            ),
            settings: {
                var settings = ChartSettings()
                settings.top = 4
                settings.bottom = 8
                settings.trailing = 8
                settings.axisTitleLabelsToLabelsSpacing = 0
                settings.labelsToAxisSpacingX = 6
                settings.clipInnerFrame = false
                return settings
            }()
        )

        charts.glucoseDisplayRange = (
            min: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 100),
            max: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 175)
        )

        return charts
    }()

    var statusExtensionContext: StatusExtensionContext?

    lazy var defaults = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)

    private var observers: [Any] = []

    lazy var healthStore = HKHealthStore()

    lazy var cacheStore = PersistenceController.controllerInAppGroupDirectory()

    lazy var glucoseStore = GlucoseStore(
        healthStore: healthStore,
        cacheStore: cacheStore,
        observationEnabled: false
    )

    lazy var doseStore = DoseStore(
        healthStore: healthStore,
        cacheStore: cacheStore,
        observationEnabled: false,
        insulinModel: defaults?.insulinModelSettings?.model,
        basalProfile: defaults?.basalRateSchedule,
        insulinSensitivitySchedule: defaults?.insulinSensitivitySchedule
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        subtitleLabel.isHidden = true
        subtitleLabel.textColor = .subtitleLabelColor
        insulinLabel.isHidden = true
        insulinLabel.textColor = .subtitleLabelColor

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openLoopApp(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)

        self.charts.prerender()
        glucoseChartContentView.chartGenerator = { [weak self] (frame) in
            return self?.charts.glucoseChartWithFrame(frame)?.view
        }

        extensionContext?.widgetLargestAvailableDisplayMode = .expanded

        switch extensionContext?.widgetActiveDisplayMode ?? .compact {
        case .compact:
            glucoseChartContentView.isHidden = true
        case .expanded:
            glucoseChartContentView.isHidden = false
        }

        observers = [
            // TODO: Observe cross-process notifications of Loop status updating
        ]
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        let compactHeight = hudView.systemLayoutSizeFitting(maxSize).height + subtitleLabel.systemLayoutSizeFitting(maxSize).height

        switch activeDisplayMode {
        case .compact:
            preferredContentSize = CGSize(width: maxSize.width, height: compactHeight)
        case .expanded:
            preferredContentSize = CGSize(width: maxSize.width, height: compactHeight + 100)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: {
            (UIViewControllerTransitionCoordinatorContext) -> Void in
            self.glucoseChartContentView.isHidden = self.extensionContext?.widgetActiveDisplayMode != .expanded
        })
    }
    
    @objc private func openLoopApp(_: Any) {
        if let url = Bundle.main.mainAppUrl {
            self.extensionContext?.open(url)
        }
    }

    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        let result = update()
        completionHandler(result)
    }
    
    @discardableResult
    func update() -> NCUpdateResult {
        subtitleLabel.isHidden = true
        insulinLabel.isHidden = true

        let group = DispatchGroup()

        var activeInsulin: Double?
        var lastReservoirValue: ReservoirValue?
        var glucose: [StoredGlucoseSample] = []

        group.enter()
        doseStore.insulinOnBoard(at: Date()) { (result) in
            switch result {
            case .success(let iobValue):
                activeInsulin = iobValue.value
            case .failure:
                activeInsulin = nil
            }
            group.leave()
        }

        group.enter()
        doseStore.getReservoirValues(since: .distantPast, limit: 1) { (result) in
            switch result {
            case .success(let values):
                lastReservoirValue = values.first
            case .failure:
                lastReservoirValue = nil
            }
            group.leave()
        }

        charts.startDate = Calendar.current.nextDate(after: Date(timeIntervalSinceNow: .minutes(-5)), matching: DateComponents(minute: 0), matchingPolicy: .strict, direction: .backward) ?? Date()

        // Showing the whole history plus full prediction in the glucose plot
        // is a little crowded, so limit it to three hours in the future:
        charts.maxEndDate = charts.startDate.addingTimeInterval(TimeInterval(hours: 3))

        group.enter()
        glucoseStore.getCachedGlucoseSamples(start: charts.startDate) { (result) in
            glucose = result
            group.leave()
        }

        group.notify(queue: .main) {
            guard let defaults = self.defaults, let context = defaults.statusExtensionContext else {
                return
            }

            if let batteryPercentage = context.batteryPercentage {
                self.hudView.batteryHUD.batteryLevel = Double(batteryPercentage)
            }

            if let reservoir = lastReservoirValue, let capacity = context.reservoirCapacity {
                self.hudView.reservoirVolumeHUD.reservoirLevel = min(1, max(0, Double(reservoir.unitVolume / capacity)))
                self.hudView.reservoirVolumeHUD.setReservoirVolume(volume: reservoir.unitVolume, at: reservoir.startDate)
            }

            if let netBasal = context.netBasal {
                self.hudView.basalRateHUD.setNetBasalRate(netBasal.rate, percent: netBasal.percentage, at: netBasal.start)
            }

            self.hudView.loopCompletionHUD.dosingEnabled = defaults.loopSettings?.dosingEnabled ?? false

            if let lastCompleted = context.lastLoopCompleted {
                self.hudView.loopCompletionHUD.lastLoopCompleted = lastCompleted
            }

            if let activeInsulin = activeInsulin {
                let insulinFormatter: NumberFormatter = {
                    let numberFormatter = NumberFormatter()

                    numberFormatter.numberStyle = .decimal
                    numberFormatter.minimumFractionDigits = 1
                    numberFormatter.maximumFractionDigits = 1

                    return numberFormatter
                }()

                if let valueStr = insulinFormatter.string(from: activeInsulin) {
                    self.insulinLabel.text = String(format: NSLocalizedString("IOB %1$@ U",
                        comment: "The subtitle format describing units of active insulin. (1: localized insulin value description)"),
                        valueStr
                    )
                    self.insulinLabel.isHidden = false
                }
            }

            guard let unit = context.predictedGlucose?.unit else {
                return
            }

            if let lastGlucose = glucose.last {
                self.hudView.glucoseHUD.setGlucoseQuantity(
                    lastGlucose.quantity.doubleValue(for: unit),
                    at: lastGlucose.startDate,
                    unit: unit,
                    sensor: context.sensor
                )
            }

            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: unit)

            let dateFormatter: DateFormatter = {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .none
                dateFormatter.timeStyle = .short

                return dateFormatter
            }()

            self.charts.glucoseUnit = unit
            self.charts.glucosePoints = glucose.map {
                ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: unit), unitString: unit.localizedShortUnitString, formatter: glucoseFormatter)
                )
            }

            if let predictedGlucose = context.predictedGlucose?.samples {
                self.charts.predictedGlucosePoints = predictedGlucose.map {
                    ChartPoint(
                        x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                        y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: unit), unitString: unit.localizedShortUnitString, formatter: glucoseFormatter)
                    )
                }

                if let eventualGlucose = predictedGlucose.last {
                    if let eventualGlucoseNumberString = glucoseFormatter.string(from: eventualGlucose.quantity.doubleValue(for: unit)) {
                        self.subtitleLabel.text = String(
                            format: NSLocalizedString(
                                "Eventually %1$@ %2$@",
                                comment: "The subtitle format describing eventual glucose.  (1: localized glucose value description) (2: localized glucose units description)"
                            ),
                            eventualGlucoseNumberString,
                            unit.localizedShortUnitString
                        )
                        self.subtitleLabel.isHidden = false
                    }
                }
            }

            self.charts.targetGlucoseSchedule = defaults.loopSettings?.glucoseTargetRangeSchedule

            self.charts.prerender()
            self.glucoseChartContentView.reloadChart()
        }

        switch extensionContext?.widgetActiveDisplayMode ?? .compact {
        case .compact:
            glucoseChartContentView.isHidden = true
        case .expanded:
            glucoseChartContentView.isHidden = false
        }

        // Right now we always act as if there's new data.
        // TODO: keep track of data changes and return .noData if necessary
        return NCUpdateResult.newData
    }
}
