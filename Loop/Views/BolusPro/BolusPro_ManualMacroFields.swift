//
//  BolusPro_ManualMacroFields.swift
//  Loop
//
//  BolusPro — Two-field input row for fat (g) and protein (g), shown
//  when the BolusPro toggle is ON and no FoodFinder macros are present.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct BolusPro_ManualMacroFields: View {

    @Binding var fatGrams: Double
    @Binding var proteinGrams: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                macroField(
                    label: "Fat",
                    glyph: "🥑",
                    value: $fatGrams
                )
                Divider().frame(height: 32)
                macroField(
                    label: "Protein",
                    glyph: "🍗",
                    value: $proteinGrams
                )
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func macroField(label: String, glyph: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(glyph).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
                HStack(spacing: 2) {
                    TextField("0", value: value, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 36)
                    Text("g").font(.footnote).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
