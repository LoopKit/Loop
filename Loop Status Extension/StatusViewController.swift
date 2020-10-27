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
import LoopKitUI
import LoopCore
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
            }(),
            traitCollection: traitCollection
        )

        charts.predictedGlucose.glucoseDisplayRange = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 100)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 175)

        return charts
    }()

    var statusExtensionContext: StatusExtensionContext?

    lazy var defaults = UserDefaults.appGroup

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
    
    private var pluginManager: PluginManager = {
        let containingAppFrameworksURL = Bundle.main.privateFrameworksURL?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Frameworks")
        return PluginManager(pluginsURL: containingAppFrameworksURL)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        subtitleLabel.isHidden = true
        if #available(iOSApplicationExtension 13.0, iOS 13.0, *) {
            subtitleLabel.textColor = .secondaryLabel
            insulinLabel.textColor = .secondaryLabel
        } else {
            subtitleLabel.textColor = .subtitleLabelColor
            insulinLabel.textColor = .subtitleLabelColor
        }

        insulinLabel.isHidden = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openLoopApp(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)

        self.charts.prerender()
        glucoseChartContentView.chartGenerator = { [weak self] (frame) in
            return self?.charts.chart(atIndex: 0, frame: frame)?.view
        }

        extensionContext?.widgetLargestAvailableDisplayMode = .expanded

        switch extensionContext?.widgetActiveDisplayMode ?? .compact {
        case .expanded:
            glucoseChartContentView.isHidden = false
        case .compact:
            fallthrough
        @unknown default:
            glucoseChartContentView.isHidden = true
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
        case .expanded:
            preferredContentSize = CGSize(width: maxSize.width, height: compactHeight + 100)
        case .compact:
            fallthrough
        @unknown default:
            preferredContentSize = CGSize(width: maxSize.width, height: compactHeight)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: {
            (UIViewControllerTransitionCoordinatorContext) -> Void in
            self.glucoseChartContentView.isHidden = self.extensionContext?.widgetActiveDisplayMode != .expanded
        })
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        charts.traitCollection = traitCollection
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

            let hudViews: [BaseHUDView]

            if let hudViewsContext = context.pumpManagerHUDViewsContext,
                let contextHUDViews = PumpManagerHUDViewsFromRawValue(hudViewsContext.pumpManagerHUDViewsRawValue, pluginManager: self.pluginManager)
            {
                hudViews = contextHUDViews
            } else {
                hudViews = [ReservoirVolumeHUDView.instantiate(), BatteryLevelHUDView.instantiate()]
            }

            self.hudView.removePumpManagerProvidedViews()
            for view in hudViews {
                view.stateColors = .pumpStatus
                self.hudView.addHUDView(view)
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

            if let lastGlucose = glucose.last, let recencyInterval = defaults.loopSettings?.inputDataRecencyInterval {
                self.hudView.glucoseHUD.setGlucoseQuantity(
                    lastGlucose.quantity.doubleValue(for: unit),
                    at: lastGlucose.startDate,
                    unit: unit,
                    staleGlucoseAge: recencyInterval,
                    sensor: context.sensor
                )
            }

            let glucoseFormatter = QuantityFormatter()
            glucoseFormatter.setPreferredNumberFormatter(for: unit)

            self.charts.predictedGlucose.glucoseUnit = unit
            self.charts.predictedGlucose.setGlucoseValues(glucose)

            if let predictedGlucose = context.predictedGlucose?.samples {
                self.charts.predictedGlucose.setPredictedGlucoseValues(predictedGlucose)

                if let eventualGlucose = predictedGlucose.last {
                    if let eventualGlucoseNumberString = glucoseFormatter.string(from: eventualGlucose.quantity, for: unit) {
                        self.subtitleLabel.text = String(
                            format: NSLocalizedString(
                                "Eventually %1$@",
                                comment: "The subtitle format describing eventual glucose.  (1: localized glucose value description)"
                            ),
                            eventualGlucoseNumberString
                        )
                        self.subtitleLabel.isHidden = false
                    }
                }
            }

            self.charts.predictedGlucose.targetGlucoseSchedule = defaults.loopSettings?.glucoseTargetRangeSchedule
            self.charts.invalidateChart(atIndex: 0)
            self.charts.prerender()
            self.glucoseChartContentView.reloadChart()
        }

        switch extensionContext?.widgetActiveDisplayMode ?? .compact {
        case .expanded:
            glucoseChartContentView.isHidden = false
        case .compact:
            fallthrough
        @unknown default:
            glucoseChartContentView.isHidden = true
        }

        // Right now we always act as if there's new data.
        // TODO: keep track of data changes and return .noData if necessary
        return NCUpdateResult.newData
    }
}
