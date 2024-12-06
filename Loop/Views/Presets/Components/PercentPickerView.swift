//
//  PercentPickerView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct PercentPickerView: View {
    
    @Binding var value: Int
    
    let range: ClosedRange<Int>
    let stepCount: Int
    let disabled: Bool
    
    let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        return formatter
    }()
    
    init(value: Binding<Int>, range: ClosedRange<Int> = 0...300, stepCount: Int = 5) {
        self._value = value
        self.range = range
        self.stepCount = stepCount
        self.disabled = false
    }
    
    init(value: Int, range: ClosedRange<Int> = 0...300, stepCount: Int = 5) {
        self._value = .constant(value)
        self.range = range
        self.stepCount = stepCount
        self.disabled = true
    }
    
    var downButton: some View {
        Button {
            withAnimation {
                if value - stepCount <= range.lowerBound {
                    value = range.lowerBound
                } else {
                    value = value - stepCount
                }
            }
        } label: {
            Text(Image(systemName: "minus.circle.fill").symbolRenderingMode(.hierarchical)).font(.system(size: UIFontMetrics.default.scaledValue(for: 40), weight: .semibold))
        }
        .buttonStyle(PickerButtonStyle(disabled: disabled))
    }
    
    var valueText: some View {
        Text("\(numberFormatter.string(from: Double(value)) ?? "100")%")
            .font(.system(size: UIFontMetrics.default.scaledValue(for: 50), weight: .semibold).monospacedDigit())
            .contentTransition(.numericText())
    }
    
    var upButton: some View {
        Button {
            withAnimation {
                if value + stepCount >= range.upperBound {
                    value = range.upperBound
                } else {
                    value = value + stepCount
                }
            }
        } label: {
            Text(Image(systemName: "plus.circle.fill").symbolRenderingMode(.hierarchical)).font(.system(size: UIFontMetrics.default.scaledValue(for: 40), weight: .semibold))
        }
        .buttonStyle(PickerButtonStyle(disabled: disabled))
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(UIColor.secondarySystemBackground), lineWidth: 1)
                .frame(maxWidth: .infinity)
            
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    downButton
                    
                    valueText
                    
                    upButton
                }
                
                VStack(spacing: 0) {
                    valueText
                    
                    HStack(spacing: 32) {
                        downButton
                        
                        upButton
                    }
                }
            }
            .foregroundColor(.accentColor)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
    }
}

private struct PickerButtonStyle: ButtonStyle {
    let disabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !disabled ? 1.15 : 1)
    }
}
