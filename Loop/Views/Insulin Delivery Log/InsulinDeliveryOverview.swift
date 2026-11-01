//
//  InsulinDeliveryOverview.swift
//  Loop
//
//  Created by Cameron Ingham on 3/26/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI
import LoopCore

struct DatedQuantity: Hashable {
    let date: Date
    let quantity: LoopQuantity
}

struct InsulinDeliveryOverview: View {
    enum State: Hashable {
        enum AutomatedBasalStatus: Hashable {
            case scheduled
            case increased
            case decreased
        }
        
        case automationOn(basalStatus: AutomatedBasalStatus, preset: SelectablePreset?)

        case automationOff
        
        enum ErrorStatus: Hashable {
            case noDelivery
            case suspended
        }
        
        case error(status: ErrorStatus)
    }
    
    @Environment(\.colorPalette) private var colorPalette
    
    @ScaledMetric private var iconSize: Double = 26
    
    private let rateFormatter = QuantityFormatter(for: .internationalUnitsPerHour)
    private let bolusFormatter = QuantityFormatter(for: .internationalUnit)

    private let state: State
    private let time: Date
    private let currentBasalRate: DatedQuantity
    private let lastAutoBolus: DatedQuantity?
    
    init(state: State, time: Date, currentBasalRate: DatedQuantity, lastAutoBolus: DatedQuantity?) {
        self.state = state
        self.time = time
        self.currentBasalRate = currentBasalRate
        self.lastAutoBolus = lastAutoBolus
    }

    @ViewBuilder
    var icon: some View {
        VStack {
            switch state {
            case .automationOn(let basalStatus, _):
                VStack {
                    switch basalStatus {
                    case .scheduled:
                        Text(Image(systemName: "arrow.right.square.fill"))
                    case .increased:
                        Text(Image(systemName: "arrow.up.square.fill"))
                    case .decreased:
                        Text(Image(systemName: "arrow.down.square.fill"))
                    }
                }
                .foregroundStyle(Color.accentColor)
            case .automationOff:
                Text(Image(systemName: "arrow.right.square.fill"))
                    .foregroundStyle(Color.accentColor)
            case .error(let status):
                VStack {
                    switch status {
                    case .noDelivery:
                        Text(Image(systemName: "xmark.circle.fill"))
                            .foregroundStyle(colorPalette.guidanceColors.critical)
                    case .suspended:
                        Text(Image(systemName: "pause.circle.fill"))
                            .foregroundStyle(colorPalette.guidanceColors.warning)
                    }
                }
            }
        }
        .font(.system(size: iconSize))
    }
    
    var statusTitle: Text {
        switch state {
        case .automationOn(let basalStatus, let preset):
            switch basalStatus {
            case .scheduled:
                if let preset, preset.insulinNeedsScaleFactor != 1.0 {
                    Text("Preset Delivery")
                } else {
                    Text("Scheduled Basal")
                }
            case .increased:
                Text("Increased Delivery")
            case .decreased:
                Text("Decreased Delivery")
            }
        case .automationOff:
            Text("Scheduled basal")
        case .error(let status):
            switch status {
            case .noDelivery:
                Text("No Delivery")
            case .suspended:
                Text("Insulin Suspended")
            }
        }
    }
    
    var statusSubtitle: Text? {
        switch state {
        case .automationOn(let basalStatus, let preset):
            if let preset, preset.insulinNeedsScaleFactor != 1.0 {
                switch basalStatus {
                case .scheduled:
                    Text("A preset with \(preset.insulinNeedsScaleFactor.formatted(.percent)) overall insulin is on. This is your new preset baseline and it overrides your Scheduled Basal.")
                case .increased:
                    Text("A preset with \(preset.insulinNeedsScaleFactor.formatted(.percent)) overall insulin is on. The system is currently delivering more than your preset baseline.")
                case .decreased:
                    Text("A preset with \(preset.insulinNeedsScaleFactor.formatted(.percent)) overall insulin is on. The system is currently delivering less than your preset baseline.")
                }
            } else if basalStatus == .increased {
                Text("Includes basal and automated boluses")
            } else {
                nil
            }
        default:
            nil
        }
    }
    
    private var errorAdjustedBasalRate: LoopQuantity {
        if case .error = state {
            return LoopQuantity(unit: currentBasalRate.quantity.unit, doubleValue: 0)
        } else {
            return currentBasalRate.quantity
        }
    }
    
    private var currentBasalRateForegroundColor: Color {
        switch state {
        case .error:
            return .secondary
        default:
            return .primary
        }
    }
    
    var currentBasalRateSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Current Basal Rate")
            
            Group {
                Text(rateFormatter.string(from: errorAdjustedBasalRate, includeUnit: false) ?? "Unknown").fontWeight(.semibold) + Text(" ") + Text(errorAdjustedBasalRate.unit.localizedUnitString(in: .short) ?? "U/hr")
            }
            .font(.title2)
            
            Text("since \(currentBasalRate.date.formatted(date: .omitted, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(currentBasalRateForegroundColor)
    }
    
    private var lastAutoBolusForegroundColor: Color {
        guard lastAutoBolus != nil else {
            return .secondary
        }
        
        switch state {
        case .automationOff, .error:
            return .secondary
        default:
            return .primary
        }
    }
    
    private var isAutomationOff: Bool {
        if case .automationOff = state {
            return true
        } else {
            return false
        }
    }
    
    var lastAutoBolusSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Last Auto Bolus")
            
            Group {
                if let lastAutoBolus, !isAutomationOff {
                    Text(bolusFormatter.string(from: lastAutoBolus.quantity, includeUnit: false) ?? "Unknown").fontWeight(.semibold) + Text(" ") + Text(lastAutoBolus.quantity.unit.localizedUnitString(in: .short) ?? "U")
                } else {
                    Text("-.--") + Text(" ") + Text(LoopUnit.internationalUnit.localizedUnitString(in: .short) ?? "U")
                }
            }
            .font(.title2)
            
            Group {
                if state == .automationOff {
                    Text("Automation is off")
                        .italic()
                } else if let lastAutoBolus {
                    Text("at \(lastAutoBolus.date.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("None in last 24 hours")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(lastAutoBolusForegroundColor)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Delivery")
                
                HStack(spacing: 4) {
                    icon
                    
                    statusTitle
                        .font(.title3.weight(.heavy))
                }
            
                if let statusSubtitle {
                    statusSubtitle
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                }
                
                Text("at \(time.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            ViewThatFits {
                HStack(spacing: 0) {
                    currentBasalRateSection
                    
                    Spacer()
                    
                    lastAutoBolusSection
                }
            }
        }
    }
}

let time = Date()
let currentBasalRate = DatedQuantity(date: Date(), quantity: LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: 0.5))
let lastAutoBolus = DatedQuantity(date: Date().addingTimeInterval(-57600), quantity: LoopQuantity(unit: .internationalUnit, doubleValue: 0.05))

let preset = SelectablePreset.custom(TemporaryPreset(symbol: "🏃", name: "Running", settings: .init(targetRange: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)...LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 120), insulinNeedsScaleFactor: 0.5), duration: .indefinite))

#Preview("Automated Delivery (scheduled)", traits: .sizeThatFitsLayout) {
    InsulinDeliveryOverview(
        state: .automationOn(basalStatus: .scheduled, preset: nil),
        time: time,
        currentBasalRate: currentBasalRate,
        lastAutoBolus: lastAutoBolus
    )
    .environment(\.guidanceColors, .default)
    .padding()
}

#Preview("Automated Delivery (less than scheduled)", traits: .sizeThatFitsLayout) {
    InsulinDeliveryOverview(
        state: .automationOn(basalStatus: .decreased, preset: nil),
        time: time,
        currentBasalRate: currentBasalRate,
        lastAutoBolus: lastAutoBolus
    )
    .environment(\.guidanceColors, .default)
    .padding()
}

#Preview("Automated Delivery (more than scheduled)", traits: .sizeThatFitsLayout) {
    InsulinDeliveryOverview(
        state: .automationOn(basalStatus: .increased, preset: nil),
        time: time,
        currentBasalRate: currentBasalRate,
        lastAutoBolus: nil
    )
    .environment(\.guidanceColors, .default)
    .padding()
}

#Preview("Preset (scheduled)", traits: .sizeThatFitsLayout) {
    InsulinDeliveryOverview(
        state: .automationOn(basalStatus: .scheduled, preset: preset),
        time: time,
        currentBasalRate: currentBasalRate,
        lastAutoBolus: lastAutoBolus
    )
    .environment(\.guidanceColors, .default)
    .padding()
}

#Preview("Preset (less than scheduled)", traits: .sizeThatFitsLayout) {
    InsulinDeliveryOverview(
        state: .automationOn(basalStatus: .decreased, preset: preset),
        time: time,
        currentBasalRate: currentBasalRate,
        lastAutoBolus: lastAutoBolus
    )
    .environment(\.guidanceColors, .default)
    .padding()
}

#Preview("Preset (more than scheduled)", traits: .sizeThatFitsLayout) {
    InsulinDeliveryOverview(
        state: .automationOn(basalStatus: .increased, preset: preset),
        time: time,
        currentBasalRate: currentBasalRate,
        lastAutoBolus: lastAutoBolus
    )
    .environment(\.guidanceColors, .default)
    .padding()
}

#Preview("Automation OFF", traits: .sizeThatFitsLayout) {
    InsulinDeliveryOverview(
        state: .automationOff,
        time: time,
        currentBasalRate: currentBasalRate,
        lastAutoBolus: nil
    )
    .environment(\.guidanceColors, .default)
    .padding()
}

#Preview("Error (No Delivery)", traits: .sizeThatFitsLayout) {
    InsulinDeliveryOverview(
        state: .error(status: .noDelivery),
        time: time,
        currentBasalRate: currentBasalRate,
        lastAutoBolus: lastAutoBolus
    )
    .environment(\.guidanceColors, .default)
    .padding()
}

#Preview("Error (Suspended)", traits: .sizeThatFitsLayout) {
    InsulinDeliveryOverview(
        state: .error(status: .suspended),
        time: time,
        currentBasalRate: currentBasalRate,
        lastAutoBolus: lastAutoBolus
    )
    .environment(\.guidanceColors, .default)
    .padding()
}
