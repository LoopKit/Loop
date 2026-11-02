//
//  TherapySettingsExampleView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

struct TherapySettingsExampleView: View {
    
    enum Component: Hashable {
        case basalRate(Double)
        case carbRatio(Double)
        case isf(Double)
        case correctionRange(ClosedRange<Double>)
        case bolusRecommendation(starting: Double, ending: Double, action: String)
        
        var title: Text? {
            switch self {
            case .basalRate: Text("Basal Rate")
            case .carbRatio: Text("Carb Ratio")
            case .isf: Text("ISF")
            case .correctionRange: Text("Correction Range")
            case .bolusRecommendation: nil
            }
        }
    }
    
    enum Style: Hashable {
        case `default`
        case adjusted
    }
    
    @EnvironmentObject var displayGlucosePreference: DisplayGlucosePreference
    
    let title: String
    let components: [Component]
    let style: Style
    
    init(title: String, components: [Component], style: Style = .default) {
        self.title = title
        self.components = components
        self.style = style
    }
    
    init(title: String, component: Component, style: Style = .default) {
        self.title = title
        self.components = [component]
        self.style = style
    }
    
    let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    
    private let basalRateFormatter = QuantityFormatter(for: .internationalUnitsPerHour)
    private let bolusFormatter = QuantityFormatter(for: .internationalUnit)
    
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Text(title)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            
            ViewThatFits {
                HStack(spacing: 0) {
                    ForEach(components, id: \.self) { component in
                        VStack(alignment: .leading, spacing: 4) {
                            value(for: component)
                                .foregroundStyle(Color.accentColor)
                            
                            if let title = component.title {
                                title
                            }
                        }
                        
                        if component != components.last {
                            Spacer(minLength: 16)
                        }
                    }
                }
                
                VStack(spacing: 8) {
                    ForEach(components, id: \.self) { component in
                        VStack(alignment: .leading, spacing: 4) {
                            value(for: component)
                                .foregroundStyle(Color.accentColor)
                            
                            if let title = component.title {
                                title
                            }
                        }
                    }
                }
            }
        }
        .inContainer(style: style)
    }
    
    @ViewBuilder
    func value(for component: Component) -> some View {
        switch component {
        case .basalRate(let double):
            if let basalRateValue = basalRateFormatter.string(from: LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: double), includeUnit: false) {
                Text(basalRateValue).bold() + Text("\u{00a0}\(LoopUnit.internationalUnitsPerHour.shortLocalizedUnitString())")
            }
        case .carbRatio(let double):
            Text("\(numberFormatter.string(from: double) ?? "0")").bold() + Text("\u{00a0}\(LoopUnit.gramsPerUnit.shortLocalizedUnitString())")
        case .isf(let double):
            Text(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: double), includeUnit: false)).bold() + Text("\u{00a0}\(displayGlucosePreference.unitRate.shortLocalizedUnitString())")
        case .correctionRange(let closedRange):
            Text("\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: closedRange.lowerBound), includeUnit: false))").bold() + Text("\u{00a0}-\u{00a0}") + Text("\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: closedRange.upperBound), includeUnit: false))").bold() + Text("\u{00a0}\(displayGlucosePreference.unit.shortLocalizedUnitString())")
        case .bolusRecommendation(let starting, let ending, let action):
            ZStack(alignment: .top) {
                HStack(alignment: .top, spacing: 0) {
                    if let startingValue = bolusFormatter.string(from: LoopQuantity(unit: .internationalUnit, doubleValue: starting)), let endingValue = bolusFormatter.string(from: LoopQuantity(unit: .internationalUnit, doubleValue: ending)) {
                        VStack(spacing: 6) {
                            Text(startingValue)
                                .font(.title2.bold())
                                .foregroundStyle(Color.accentColor)
                            
                            Text("Before")
                                .font(.subheadline)
                                .foregroundStyle(Color.primary)
                        }
                        .containerRelativeFrame(.horizontal, count: 2, spacing: 80, alignment: .center)
                        
                        VStack(spacing: 6) {
                            Text(endingValue)
                                .font(.title2.bold())
                                .foregroundStyle(Color.accentColor)
                            
                            Text(action)
                                .font(.subheadline)
                                .foregroundStyle(Color.primary)
                        }
                        .containerRelativeFrame(.horizontal, count: 2, spacing: 80, alignment: .center)
                    }
                }
                
                Image(systemName: "arrow.forward")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Color.primary)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func inContainer(style: TherapySettingsExampleView.Style) -> some View {
        switch style {
        case .default:
            InsetContent {
                self
            }
        case .adjusted:
            self
                .padding(16)
                .background(
                    Color(UIColor.secondarySystemBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                )
        }
    }
}

extension DisplayGlucosePreference {
    var unitRate: LoopUnit {
        unit.unitDivided(by: .internationalUnit)
    }
}
