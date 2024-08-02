//
//  FavoriteFoodInsightsChartsView.swift
//  Loop
//
//  Created by Noah Brauner on 7/30/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopAlgorithm
import HealthKit
import Combine

struct FavoriteFoodsInsightsChartsView: View {
    private enum ChartRow: Int, CaseIterable {
        case glucose
        case iob
        case dose
        case carbEffects
        
        var title: String {
            switch self {
            case .glucose: "Glucose"
            case .iob: "Active Insulin"
            case .dose: "Insulin Delivery"
            case .carbEffects: "Glucose Change"
            }
        }
    }
    
    @ObservedObject var viewModel: FavoriteFoodInsightsViewModel
    @Binding var showHowCarbEffectsWorks: Bool

    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    
    @State private var isInteractingWithChart = false
    
    var body: some View {
        VStack(spacing: 10) {
            let charts = ChartRow.allCases
            ForEach(charts, id: \.rawValue) { chart in
                ZStack(alignment: .topLeading) {
                    HStack {
                        Text(chart.title)
                            .font(.subheadline)
                            .bold()
                        
                        if chart == .carbEffects {
                            explainCarbEffectsButton
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isInteractingWithChart ? 0 : 1)
                    
                    Group {
                        switch chart {
                        case .glucose:
                            glucoseChart
                        case .iob:
                            iobChart
                        case .dose:
                            doseChart
                        case .carbEffects:
                            carbEffectsChart
                        }
                    }
                }
            }
        }
    }
    
    private var glucoseChart: some View {
        GlucoseCarbChartView(
            chartManager: viewModel.chartManager,
            glucoseUnit: displayGlucosePreference.unit,
            glucoseValues: viewModel.historicalGlucoseValues,
            carbEntries: viewModel.historicalCarbEntries,
            dateInterval: viewModel.dateInterval,
            isInteractingWithChart: $isInteractingWithChart
        )
        .modifier(ChartModifier(horizontalPadding: 4, fractionOfScreenHeight: 1/4))
    }
    
    private var iobChart: some View {
        IOBChartView(
            chartManager: viewModel.chartManager,
            iobValues: viewModel.historicalIOBValues,
            dateInterval: viewModel.dateInterval,
            isInteractingWithChart: $isInteractingWithChart
        )
        .modifier(ChartModifier())
    }
    
    private var doseChart: some View {
        DoseChartView(
            chartManager: viewModel.chartManager,
            doses: viewModel.historicalDoses,
            dateInterval: viewModel.dateInterval,
            isInteractingWithChart: $isInteractingWithChart
        )
        .modifier(ChartModifier())
    }
    
    private var carbEffectsChart: some View {
        CarbEffectChartView(
            chartManager: viewModel.chartManager,
            glucoseUnit: displayGlucosePreference.unit,
            carbAbsorptionReview: viewModel.historicalCarbAbsorptionReview,
            dateInterval: viewModel.dateInterval,
            isInteractingWithChart: $isInteractingWithChart
        )
        .modifier(ChartModifier())
    }
    
    private var explainCarbEffectsButton: some View {
        Button(action: { showHowCarbEffectsWorks = true }) {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

fileprivate struct ChartModifier: ViewModifier {
    var horizontalPadding: CGFloat = 8
    var fractionOfScreenHeight: CGFloat = 1/6
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, -4)
            .padding(.top, UIFont.preferredFont(forTextStyle: .subheadline).lineHeight + 8)
            .clipped()
            .frame(height: floor(UIScreen.main.bounds.height * fractionOfScreenHeight))
    }
}

