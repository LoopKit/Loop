//
//  InsulinDeliveryLogEventRow.swift
//  Loop
//
//  Created by Cameron Ingham on 3/26/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

struct InsulinDeliveryLogEventRow: View {
    
    @Environment(\.colorPalette) private var colorPalette
    
    @ScaledMetric private var dateFontSize: Double = 14
    
    private let rateFormatter = QuantityFormatter(for: .internationalUnitsPerHour)
    private let bolusFormatter = QuantityFormatter(for: .internationalUnit)
    private let carbFormatter = QuantityFormatter(for: .gram)
    
    private let event: InsulinDeliveryLogEvent
    
    init(event: InsulinDeliveryLogEvent) {
        self.event = event
    }
    
    @ViewBuilder
    var icon: some View {
        switch event.type {
        case .pumpEvent(.basal, _):
            Image("basal-delivery-log")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        case .pumpEvent(.bolus(let bolusEventType, _, _), _):
            Group {
                switch bolusEventType {
                case .automated:
                    Image("autobolus-delivery-log")
                        .resizable()
                        .scaledToFit()
                default:
                    Image("bolus-delivery-log")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 24, height: 24)
        case .pumpEvent(.insulin(let insulinEventType), _):
            Group {
                switch insulinEventType {
                case .suspended:
                    Image(systemName: "pause.circle.fill")
                        .resizable()
                        .foregroundStyle(colorPalette.guidanceColors.warning)
                case .resumed:
                    Image(systemName: "play.circle")
                        .resizable()
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 24, height: 24)
        case .automation(let automationEventType):
            Group {
                switch automationEventType {
                case .on:
                    Image("automation-on-delivery-log")
                        .resizable()
                        .scaledToFit()
                case .off(let endDate):
                    if endDate == nil {
                        Image("automation-off-delivery-log")
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image("automation-off-range-delivery-log")
                            .resizable()
                            .scaledToFit()
                    }
                case .unavailable:
                    Image("automation-unavailable-delivery-log")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 24, height: 24)
        case .preset:
            Image("presets")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color.presets)
                .frame(width: 24, height: 24)
        }
    }

    func bolusTitle(deliveryAmount: LoopQuantity, programmedAmount: LoopQuantity) -> some View {
        if deliveryAmount != programmedAmount {
            Text("Bolus: ") + Text(bolusFormatter.string(from: deliveryAmount, includeUnit: false) ?? "Unknown").fontWeight(.medium) + Text(" ") + Text(deliveryAmount.unit.localizedUnitString(in: .short) ?? "U") + Text(" of ") + Text(bolusFormatter.string(from: programmedAmount, includeUnit: false) ?? "Unknown")  + Text(" ") + Text(programmedAmount.unit.localizedUnitString(in: .short) ?? "U")
        } else {
            Text("Bolus: ") + Text(bolusFormatter.string(from: deliveryAmount, includeUnit: false) ?? "Unknown").fontWeight(.medium) + Text(" ") + Text(deliveryAmount.unit.localizedUnitString(in: .short) ?? "U")
        }
    }


    @ViewBuilder
    var title: some View {
        switch event.type {
        case .pumpEvent(let pumpEventType, _):
            switch pumpEventType {
            case .basal(let basalEventType, let rate):
                switch basalEventType {
                case .automationOn(let basalStatus):
                    switch basalStatus {
                    case .scheduled:
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Basal: ") + Text(rateFormatter.string(from: rate, includeUnit: false) ?? "Unknown").fontWeight(.medium) + Text(" ") + Text(rate.unit.localizedUnitString(in: .short) ?? "U/hr")
                                
                                Text("Automated (Scheduled)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(event.date.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: dateFontSize))
                                .foregroundStyle(.secondary)
                        }
                    case .moreThanScheduled:
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Basal: ") + Text(rateFormatter.string(from: rate, includeUnit: false) ?? "Unknown").fontWeight(.medium) + Text(" ") + Text(rate.unit.localizedUnitString(in: .short) ?? "U/hr")
                                
                                Text("Automated (↑ Increase)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(event.date.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: dateFontSize))
                                .foregroundStyle(.secondary)
                        }
                    case .lessThanScheduled:
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Basal: ") + Text(rateFormatter.string(from: rate, includeUnit: false) ?? "Unknown").fontWeight(.medium) + Text(" ") + Text(rate.unit.localizedUnitString(in: .short) ?? "U/hr")
                                
                                Text("Automated (↓ Decrease)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(event.date.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: dateFontSize))
                                .foregroundStyle(.secondary)
                        }
                    }
                case .automationOff:
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Basal: ") + Text(rateFormatter.string(from: rate, includeUnit: false) ?? "Unknown").fontWeight(.medium) + Text(" ") + Text(rate.unit.localizedUnitString(in: .short) ?? "U/hr")
                            
                            Text("Scheduled")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(event.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: dateFontSize))
                            .foregroundStyle(.secondary)
                    }
                case .automatedPresetBasal:
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Basal: ") + Text(rateFormatter.string(from: rate, includeUnit: false) ?? "Unknown").fontWeight(.medium) + Text(" ") + Text(rate.unit.localizedUnitString(in: .short) ?? "U/hr")
                            
                            Text("Automated (Preset Basal Rate)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(event.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: dateFontSize))
                            .foregroundStyle(.secondary)
                    }
                case .manualTempBasal(let endDate):
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Temp Basal: ") + Text(rateFormatter.string(from: rate, includeUnit: false) ?? "Unknown").fontWeight(.medium) + Text(" ") + Text(rate.unit.localizedUnitString(in: .short) ?? "U")
                            
                            Text("Manual")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(event.date.formatted(date: .omitted, time: .shortened)) + Text(" -")
                            Text(endDate.formatted(date: .omitted, time: .shortened))
                        }
                        .font(.system(size: dateFontSize))
                        .foregroundStyle(.secondary)
                    }
                }
            case .bolus(let bolusEventType, let programmedAmount, let deliveryAmount):
                let programmedAmount = programmedAmount ?? deliveryAmount
                
                switch bolusEventType {
                case .automated:
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            bolusTitle(deliveryAmount: deliveryAmount, programmedAmount: programmedAmount)
                            Text("Automated")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(event.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: dateFontSize))
                            .foregroundStyle(.secondary)
                    }
                case .meal(let recommendedAmount as LoopQuantity?, _, _), .correction(let recommendedAmount):
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            bolusTitle(deliveryAmount: deliveryAmount, programmedAmount: programmedAmount)

                            if let recommendedAmount {
                                Group {
                                    Text("Recommended: ") + Text(bolusFormatter.string(from: recommendedAmount, includeUnit: false) ?? "Unknown").fontWeight(.medium) + Text(" ") + Text(recommendedAmount.unit.localizedUnitString(in: .short) ?? "U")
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(event.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: dateFontSize))
                            .foregroundStyle(.secondary)
                    }
                case .external:
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            bolusTitle(deliveryAmount: deliveryAmount, programmedAmount: programmedAmount)

                            Text("External Insulin")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(event.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: dateFontSize))
                            .foregroundStyle(.secondary)
                    }
                }
            case .insulin(let insulinEventType):
                switch insulinEventType {
                case .suspended:
                    HStack(spacing: 0) {
                        Text("Insulin Suspended")
                        
                        Spacer()
                        
                        Text(event.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: dateFontSize))
                            .foregroundStyle(.secondary)
                    }
                case .resumed:
                    HStack(spacing: 0) {
                        Text("Insulin Resumed")
                        
                        Spacer()
                        
                        Text(event.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: dateFontSize))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .automation(let automationEventType):
            switch automationEventType {
            case .on:
                HStack(spacing: 0) {
                    Text("Automation ON")
                    
                    Spacer()
                    
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: dateFontSize))
                        .foregroundStyle(.secondary)
                }
            case .off(let endDate):
                HStack(spacing: 0) {
                    Text("Automation OFF")
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(event.date.formatted(date: .omitted, time: .shortened)) + Text(endDate != nil ? " -" : "")
                        
                        if let endDate {
                            Text(endDate.formatted(date: .omitted, time: .shortened))
                        }
                    }
                    .font(.system(size: dateFontSize))
                    .foregroundStyle(.secondary)
                }
            case .unavailable:
                HStack(spacing: 0) {
                    Text("Automation unavailable")
                    
                    Spacer()
                    
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: dateFontSize))
                        .foregroundStyle(.secondary)
                }
            }
        case .preset(let presetEventType, _, _):
            switch presetEventType {
            case .enabled:
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Preset Enabled")
                        
                        Text("Automation")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: dateFontSize))
                        .foregroundStyle(.secondary)
                }
            case .disabled:
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Preset Disabled")
                        
                        Text("Automation")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: dateFontSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    var content: some View {
        switch event.type {
        case .pumpEvent(.basal, _):
            EmptyView()
        case .pumpEvent(.bolus(let bolusEventType, _, _), _):
            switch bolusEventType {
            case .automated, .correction, .external:
                EmptyView()
            case .meal(_, let carbAmount, let emoji):
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.trailing, -20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meal Summary")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Group {
                            Text(carbFormatter.string(from: carbAmount) ?? "Unknown")
                                .foregroundStyle(colorPalette.carbTintColor) +
                            Text(" ") +
                            Text(emoji)
                        }
                        .font(.title2.weight(.semibold))
                    }
                }
            }
        case .pumpEvent(.insulin, _), .automation:
            EmptyView()
        case .preset(_, let icon, let name):
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .padding(.trailing, -20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preset Summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 6) {
                        if let icon, !icon.isEmpty {
                            PresetSymbolView(icon)
                        }

                        Text(name)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8){
            HStack(spacing: 12) {
                icon
                
                title
            }
                
            content
                .padding(.leading, 36)
        }
    }
}

#Preview {
    InsulinDeliveryLogEventRow(event: InsulinDeliveryLogEvent(id: UUID().uuidString, type: .pumpEvent(.bolus(.correction(recommendedAmount: nil), programmedAmount: nil, deliveryAmount: LoopQuantity(unit: .internationalUnit, doubleValue: 5)), nil), date: Date()))
        .environment(\.colorPalette, .default)
}
