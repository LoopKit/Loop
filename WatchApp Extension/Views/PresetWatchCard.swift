//
//  PresetWatchCard.swift
//  Loop
//
//  Created by Pete Schwamb on 9/9/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import SwiftUI
import LoopKit
import LoopCore

extension Color {
    init(presetSymbolTint: PresetSymbol.SymbolTint?) {
        guard let presetSymbolTint else {
            self = .primary
            return
        }

        switch presetSymbolTint {
        case .preMeal:
            self = Color.carbs
        }
    }
}

struct PresetSymbolView: View {

    let symbol: PresetSymbol
    let iconSize: Double

    init(_ symbol: PresetSymbol, iconSize: Double = 17) {
        self.symbol = symbol
        self.iconSize = iconSize
    }

    var body: some View {
        Group {
            switch symbol.symbolType {
            case .emoji:
                Text(symbol.value)
                    .font(.system(size: UIFontMetrics.default.scaledValue(for: iconSize - 2)))
            case .image:
                Text(Image(symbol.value))
                    .foregroundStyle(Color(presetSymbolTint: symbol.tint))
                    .font(.system(size: UIFontMetrics.default.scaledValue(for: iconSize)))
            case .systemImage:
                Text(Image(systemName: symbol.value))
                    .foregroundStyle(Color(presetSymbolTint: symbol.tint))
                    .font(.system(size: UIFontMetrics.default.scaledValue(for: iconSize)))
            }
        }
        .fontDesign(.monospaced)
    }
}


struct PresetWatchCard: View {

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.glucoseDisplayUnit) private var glucoseDisplayUnit

    let presetId: String
    let icon: PresetSymbol?
    let presetName: String
    let duration: PresetDuration
    let insulinMultiplier: Double?
    let correctionRange: ClosedRange<LoopQuantity>?
    let isScheduled: Bool

    init(presetId: String, icon: PresetSymbol?, presetName: String, duration: PresetDuration, insulinMultiplier: Double?, correctionRange: ClosedRange<LoopQuantity>?, isScheduled: Bool) {
        self.presetId = presetId
        self.icon = icon
        self.presetName = presetName
        self.duration = duration
        self.insulinMultiplier = insulinMultiplier
        self.correctionRange = correctionRange
        self.isScheduled = isScheduled

        print("preset \(presetName), icon = \(icon)")
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
    }

    private var glucoseFormatter: QuantityFormatter {
        return QuantityFormatter(for: glucoseDisplayUnit)
    }


    var presetTitle: some View {
        HStack(spacing: 6) {
            if let icon, !icon.isEmpty {
                PresetSymbolView(icon)
            }
            Text(presetName)
                .accessibilityIdentifier("text_Preset\(presetName)")
        }
    }

    var presetDuration: some View {
        Group { Text(Image(systemName: "timer")) + Text(" \(duration.localizedTitle)") }
            .font(.footnote)
            .foregroundColor(.secondary)
            .accessibilityLabel(Text(duration.accessibilityLabel))
    }

    var descriptionText: Text {
        let percent = numberFormatter.string(from: insulinMultiplier ?? 1)!
        var text = Text(percent).bold()

        if let correctionRange {
            text = text + Text(" • ")
            text = text + (Text(glucoseFormatter.string(from: correctionRange.lowerBound, includeUnit: false)!) +
                           Text("-") +
                           Text(glucoseFormatter.string(from: correctionRange.upperBound, includeUnit: false)!)).bold()
            text = text + Text(" " + glucoseDisplayUnit.localizedShortUnitString)
                .foregroundStyle(.secondary)
        }
        return text.font(.footnote)

    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
            VStack(alignment: .leading, spacing: 10) {
                presetTitle
                descriptionText
            }
            .padding(10)
        }
    }
}

extension PresetWatchCard {
    init (_ preset: SelectablePreset) {
        self.init(
            presetId: preset.id,
            icon: preset.icon,
            presetName: preset.name,
            duration: preset.duration,
            insulinMultiplier: preset.insulinNeedsScaleFactor,
            correctionRange: preset.correctionRange,
            isScheduled: preset.isScheduled
        )
    }
}
