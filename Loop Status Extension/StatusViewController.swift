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

    @IBOutlet weak var hudView: StatusBarHUDView! {
        didSet {
            hudView.loopCompletionHUD.stateColors = .loopStatus
            hudView.cgmStatusHUD.stateColors = .cgmStatus
            hudView.cgmStatusHUD.tintColor = .label
            hudView.pumpStatusHUD.tintColor = .insulinTintColor
            hudView.backgroundColor = .clear
            
            // given the reduced width of the widget, allow for tighter spacing
            hudView.containerView.spacing = 6.0
        }
    }
    @IBOutlet weak var activeCarbsTitleLabel: UILabel!
    @IBOutlet weak var activeCarbsAmountLabel: UILabel!
    @IBOutlet weak var activeInsulinTitleLabel: UILabel!
    @IBOutlet weak var activeInsulinAmountLabel: UILabel!
    @IBOutlet weak var glucoseChartContentView: LoopKitUI.ChartContainerView!

    private lazy var charts: StatusChartsManager = {
        let charts = StatusChartsManager(
            colors: ChartColorPalette(
                axisLine: .axisLineColor,
                axisLabel: .axisLabelColor,
                grid: .gridColor,
                glucoseTint: .glucoseTintColor,
                insulinTint: .insulinTintColor
            ),
            settings: {
                var settings = ChartSettings()
                settings.top = 8
                settings.bottom = 8
                settings.trailing = 8
                settings.axisTitleLabelsToLabelsSpacing = 0
                settings.labelsToAxisSpacingX = 6
                settings.clipInnerFrame = false
                return settings
            }(),
            traitCollection: traitCollection
        )
        
        if FeatureFlags.predictedGlucoseChartClampEnabled {
            charts.predictedGlucose.glucoseDisplayRange = ChartConstants.glucoseChartDefaultDisplayBoundClamped
        } else {
            charts.predictedGlucose.glucoseDisplayRange = ChartConstants.glucoseChartDefaultDisplayBound
        }

        return charts
    }()

    var statusExtensionContext: StatusExtensionContext?

    lazy var defaults = UserDefaults.appGroup

    private var observers: [Any] = []

    lazy var healthStore = HKHealthStore()

    lazy var cacheStore = PersistenceController.controllerInAppGroupDirectory()

    lazy var localCacheDuration = Bundle.main.localCacheDuration

    lazy var settingsStore: SettingsStore =  SettingsStore(
        store: cacheStore,
        expireAfter: localCacheDuration)

    lazy var glucoseStore = GlucoseStore(
        healthStore: healthStore,
        observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitGlucoseSamplesFromOtherApps,
        storeSamplesToHealthKit: false,
        cacheStore: cacheStore,
        observationEnabled: false,
        provenanceIdentifier: HKSource.default().bundleIdentifier
    )

    lazy var doseStore = DoseStore(
        healthStore: healthStore,
        observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitDoseSamplesFromOtherApps,
        storeSamplesToHealthKit: false,
        cacheStore: cacheStore,
        observationEnabled: false,
        insulinModelProvider: PresetInsulinModelProvider(defaultRapidActingModel: settingsStore.latestSettings?.defaultRapidActingModel?.presetForRapidActingInsulin),
        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
        basalProfile: settingsStore.latestSettings?.basalRateSchedule,
        insulinSensitivitySchedule: settingsStore.latestSettings?.insulinSensitivitySchedule,
        provenanceIdentifier: HKSource.default().bundleIdentifier
    )
    
    private var pluginManager: PluginManager = {
        let containingAppFrameworksURL = Bundle.main.privateFrameworksURL?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Frameworks")
        return PluginManager(pluginsURL: containingAppFrameworksURL)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        activeCarbsTitleLabel.text = NSLocalizedString("Active Carbs", comment: "Widget label title describing the active carbs")
        activeInsulinTitleLabel.text = NSLocalizedString("Active Insulin", comment: "Widget label title describing the active insulin")
        activeCarbsTitleLabel.textColor = .secondaryLabel
        activeCarbsAmountLabel.textColor = .label
        activeInsulinTitleLabel.textColor = .secondaryLabel
        activeInsulinAmountLabel.textColor = .label

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
        let compactHeight = hudView.systemLayoutSizeFitting(maxSize).height + activeCarbsTitleLabel.systemLayoutSizeFitting(maxSize).height

        switch activeDisplayMode {
        case .expanded:
            preferredContentSize = CGSize(width: maxSize.width, height: compactHeight + 135)
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
        let group = DispatchGroup()

        var activeInsulin: Double?
        let carbUnit = HKUnit.gram()
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
        glucoseStore.getGlucoseSamples(start: charts.startDate) { (result) in
            switch result {
            case .failure:
                glucose = []
            case .success(let samples):
                glucose = samples
            }
            group.leave()
        }

        group.notify(queue: .main) {
            guard let defaults = self.defaults, let context = defaults.statusExtensionContext else {
                return
            }

            // Pump Status
            let pumpManagerHUDView: BaseHUDView
            if let hudViewContext = context.pumpManagerHUDViewContext,
                let contextHUDView = PumpManagerHUDViewFromRawValue(hudViewContext.pumpManagerHUDViewRawValue, pluginManager: self.pluginManager)
            {
                pumpManagerHUDView = contextHUDView
            } else {
                pumpManagerHUDView = ReservoirVolumeHUDView.instantiate()
            }
            pumpManagerHUDView.stateColors = .pumpStatus
            self.hudView.removePumpManagerProvidedView()
            self.hudView.addPumpManagerProvidedHUDView(pumpManagerHUDView)

            if let netBasal = context.netBasal {
                self.hudView.pumpStatusHUD.basalRateHUD.setNetBasalRate(netBasal.rate, percent: netBasal.percentage, at: netBasal.start)
            }

            if let lastCompleted = context.lastLoopCompleted {
                self.hudView.loopCompletionHUD.lastLoopCompleted = lastCompleted
            }
            
            if let isClosedLoop = context.isClosedLoop {
                self.hudView.loopCompletionHUD.loopIconClosed = isClosedLoop
            }

            let insulinFormatter: NumberFormatter = {
                let numberFormatter = NumberFormatter()

                numberFormatter.numberStyle = .decimal
                numberFormatter.minimumFractionDigits = 2
                numberFormatter.maximumFractionDigits = 2
                
                return numberFormatter
            }()

            if let activeInsulin = activeInsulin,
                let valueStr = insulinFormatter.string(from: activeInsulin)
            {
                self.activeInsulinAmountLabel.text = String(format: NSLocalizedString("%1$@ U", comment: "The subtitle format describing units of active insulin. (1: localized insulin value description)"), valueStr)
            } else {
                self.activeInsulinAmountLabel.text = NSLocalizedString("? U", comment: "Displayed in the widget when the amount of active insulin cannot be determined.")
            }

            self.hudView.pumpStatusHUD.presentStatusHighlight(context.pumpStatusHighlightContext)
            self.hudView.pumpStatusHUD.lifecycleProgress = context.pumpLifecycleProgressContext

            // Active carbs
            let carbsFormatter = QuantityFormatter()
            carbsFormatter.setPreferredNumberFormatter(for: carbUnit)

            if let carbsOnBoard = context.carbsOnBoard,
               let activeCarbsNumberString = carbsFormatter.string(from: HKQuantity(unit: carbUnit, doubleValue: carbsOnBoard), for: carbUnit)
            {
                self.activeCarbsAmountLabel.text = String(format: NSLocalizedString("%1$@", comment: "The subtitle format describing the grams of active carbs.  (1: localized carb value description)"), activeCarbsNumberString)
            } else {
                self.activeCarbsAmountLabel.text = NSLocalizedString("? g", comment: "Displayed in the widget when the amount of active carbs cannot be determined.")
            }

            // CGM Status
            self.hudView.cgmStatusHUD.presentStatusHighlight(context.cgmStatusHighlightContext)
            self.hudView.cgmStatusHUD.lifecycleProgress = context.cgmLifecycleProgressContext
            
            guard let unit = context.predictedGlucose?.unit else {
                return
            }

            if let lastGlucose = glucose.last {
                self.hudView.cgmStatusHUD.setGlucoseQuantity(
                    lastGlucose.quantity.doubleValue(for: unit),
                    at: lastGlucose.startDate,
                    unit: unit,
                    staleGlucoseAge: LoopCoreConstants.inputDataRecencyInterval,
                    glucoseDisplay: context.glucoseDisplay,
                    wasUserEntered: lastGlucose.wasUserEntered,
                    isDisplayOnly: lastGlucose.isDisplayOnly
                )
            }

            // Charts
            let glucoseFormatter = QuantityFormatter()
            glucoseFormatter.setPreferredNumberFormatter(for: unit)

            self.charts.predictedGlucose.glucoseUnit = unit
            self.charts.predictedGlucose.setGlucoseValues(glucose)

            if let predictedGlucose = context.predictedGlucose?.samples, context.isClosedLoop == true {
                self.charts.predictedGlucose.setPredictedGlucoseValues(predictedGlucose)
            } else {
                self.charts.predictedGlucose.setPredictedGlucoseValues([])
            }

            self.charts.predictedGlucose.targetGlucoseSchedule = self.settingsStore.latestSettings?.glucoseTargetRangeSchedule
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
