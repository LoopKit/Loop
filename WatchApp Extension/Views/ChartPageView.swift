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
            LoopHeader()
            chartView

            VStack(spacing: 8) {
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
