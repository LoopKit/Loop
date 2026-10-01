//
//  ChartPageView.swift
//  Loop
//
//  Created by Pete Schwamb on 9/19/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopCore
import LoopAlgorithm
import SpriteKit

struct ChartPageView: View {
    @Environment(\.sizeClass) private var sizeClass

    @Environment(LoopDataManager.self) var loopManager

    @State private var isShowingCarbList: Bool = false

    @ScaledMetric private var iconSize: Double = 26
    
    var presetActive: Bool {
        return loopManager.watchInfo.scheduleOverride?.isActive() == true
    }
    
    var lastSyncString: String? {
        guard loopManager.activeContext?.isClosedLoop == true, let date = loopManager.activeContext?.loopLastRunDate else {
            return nil
        }
        
        let ago = min(abs(min(0, date.timeIntervalSinceNow)), TimeInterval.days(7))

        guard let timeString = ago.truncatedTimeAgoString else {
            return nil
        }
        
        if ago > .hours(1) {
            return String(format: NSLocalizedString(" >%@ ago", comment: "Format string describing the time interval since the last completion date, last cgm or last pump communication. (1: The localized date components"), timeString)
        } else {
            return String(format: NSLocalizedString(" %@ ago", comment: "Format string describing the time interval since the last completion date, last cgm or last pump communication. (1: The localized date components"), timeString)
        }
    }

    private var chartHeight: CGFloat {
        switch sizeClass {
        case .size38mm:
            return 73
        case .size44mm:
            return 111
        case .size45mm:
            return 115
        default:
            return 90
        }
    }

    var chartView: some View {
        SpriteView(scene: loopManager.glucoseChartScene)
            .frame(height: chartHeight)
            .ignoresSafeArea()
            .gesture(
                // Handle double tap
                TapGesture(count: 2)
                    .onEnded {
                        loopManager.glucoseChartScene.increaseVisibleDuration()
                    }
            )
            .gesture(
                // Handle single tap
                TapGesture()
                    .onEnded {
                        loopManager.glucoseChartScene.decreaseVisibleDuration()
                    }
            )
    }
    
    var activeInsulin: String? {
        guard let activeContext = loopManager.activeContext,
            let activeInsulin = activeContext.activeInsulin
        else {
            return nil
        }

        let insulinFormatter: QuantityFormatter = {
            let insulinFormatter = QuantityFormatter(for: .internationalUnit)
            insulinFormatter.numberFormatter.minimumFractionDigits = 1
            insulinFormatter.numberFormatter.maximumFractionDigits = 1

            return insulinFormatter
        }()

        return insulinFormatter.string(from: activeInsulin)
    }

    var activeCarbohydrates: String? {
        guard let activeContext = loopManager.activeContext,
            let activeCarbohydrates = activeContext.activeCarbohydrates
        else {
            return nil
        }

        let carbFormatter = QuantityFormatter(for: .gram)
        carbFormatter.numberFormatter.maximumFractionDigits = 0

        return carbFormatter.string(from: activeCarbohydrates)
    }

    var lastBolus: Text {
        guard let lastBolus = loopManager.activeContext?.lastManualBolus else {
            return Text("-")
        }

        let bolusFormatter = QuantityFormatter(for: .internationalUnit)
        bolusFormatter.numberFormatter.minimumFractionDigits = 1
        bolusFormatter.numberFormatter.maximumFractionDigits = 1


        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .none

        let bolusVolume = bolusFormatter.string(from: LoopQuantity(unit: .internationalUnit, doubleValue: lastBolus.amount))!
        let bolusTime = dateFormatter.string(from: lastBolus.startDate)

        return
            Text("\(bolusVolume)") +
            Text(" at \(bolusTime)").font(.caption).foregroundColor(.secondary)
    }

    var netTempBasalDose: String? {
        guard let activeContext = loopManager.activeContext,
            let tempBasal = activeContext.lastNetTempBasalDose
        else {
            return nil
        }

        let basalFormatter = NumberFormatter()
        basalFormatter.numberStyle = .decimal
        basalFormatter.minimumFractionDigits = 1
        basalFormatter.maximumFractionDigits = 3
        basalFormatter.positivePrefix = basalFormatter.plusSign

        let unit = NSLocalizedString(
            "U/hr",
            comment: "The short unit display string for international units of insulin delivery per hour"
        )

        return basalFormatter.string(from: tempBasal, unit: unit)
    }

    var reservoirVolume: String? {
        guard let activeContext = loopManager.activeContext,
            let reservoirVolume = activeContext.reservoirVolume
        else {
            return nil
        }

        let insulinFormatter: QuantityFormatter = {
            let insulinFormatter = QuantityFormatter(for: .internationalUnit)
            insulinFormatter.unitStyle = .long
            insulinFormatter.numberFormatter.minimumFractionDigits = 0
            insulinFormatter.numberFormatter.maximumFractionDigits = 0

            return insulinFormatter
        }()

        return insulinFormatter.string(from: reservoirVolume)
    }

    var body: some View {
        ScrollView(.vertical) {
            TimelineView(.animation) { _ in
                LoopHeader()
                
                chartView
                
                VStack(spacing: 8) {
                    if let lastSyncString {
                        LabelValueRow("Last Loop") {
                            // ⚠️ arrow.triangle.2.circlepath is deprecated -- replace with "arrow.trianglehead.2.clockwise.rotate.90" once watchOS 10 is dropped as a supported platform.
                            Text(Image(systemName: "arrow.triangle.2.circlepath")) +
                            Text(" " + lastSyncString)
                        }
                        Divider()
                    }
                    LabelValueRow("Active Insulin") {
                        Text(activeInsulin ?? "-")
                    }
                    Divider()
                    LabelValueRow("Active Carbs") {
                        Text(activeCarbohydrates ?? "-")
                    }
                    .onTapGesture {
                        isShowingCarbList = true
                    }
                    Divider()
                    LabelValueRow("Last Bolus") {
                        lastBolus
                    }
                    if let currentDelivery = loopManager.activeContext?.insulinDeliveryState {
                        Divider()
                        LabelValueRow("Current Delivery") {
                            Text(currentDelivery.iconImage) +
                            Text(" " + currentDelivery.shortDescription)
                        }
                    }
                    Divider()
                    LabelValueRow("Reservoir Volume") {
                        Text(reservoirVolume ?? "-")
                    }
                }
                .padding(.horizontal)
            }
        }
        .font(.system(size: 14, weight: .light))
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.glucoseDisplayUnit, loopManager.displayGlucoseUnit)
        .onAppear() {
            updateGlucoseChart()
        }
        .onChange(of: loopManager.activeContext?.predictedGlucose) { oldValue, newValue in
            updateGlucoseChart()
        }
        .sheet(isPresented: $isShowingCarbList) {
            // ONE list, loan-aware. During a loan it reads the loan stack's carb store — the
            // authoritative one while the wrist holds the pod — and gains swipe-to-delete, because
            // the phone is not there to edit on. That branch lives inside `CarbList` rather than
            // here: two lists meant two places to keep the presentation right, and this is the
            // screen the user already knows.
            //
            // It also matters that this used `ExtensionDelegate.shared()`, which force-unwraps.
            // `CarbList` reads the session through `sharedIfAvailable()` instead.
            CarbList()
        }
    }

    private func updateGlucoseChart() {
        Task { @MainActor in
            let chartData = await loopManager.generateChartData()
            loopManager.glucoseChartScene.data = chartData
            loopManager.glucoseChartScene.setNeedsUpdate()
        }
    }
}

extension TimeInterval {
    /// Formats a time interval as a truncated "time ago" string (e.g., "1 hr", "2 mins")
    var truncatedTimeAgoString: String? {
        let calendar = Calendar.current
        let now = Date()
        let past = now.addingTimeInterval(-self)

        let components = calendar.dateComponents([.day, .hour, .minute], from: past, to: now)
        if let days = components.day, days > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("%d day", tableName: "LocalizablePlural", bundle: .main, value: "%d day", comment: "Singular/plural day count"),
                days
            )
        } else if let hours = components.hour, hours > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("%d hr", tableName: "LocalizablePlural", bundle: .main, value: "%d hr", comment: "Singular/plural hour count"),
                hours
            )
        } else if let minutes = components.minute {
            return String.localizedStringWithFormat(
                NSLocalizedString("%d min", tableName: "LocalizablePlural", bundle: .main, value: "%d min", comment: "Singular/plural minute count"),
                minutes
            )
        } else {
            return nil
        }
    }
}



