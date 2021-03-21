//
//  AbsorptionTimeSelection.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/24/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct AbsorptionTimeSelection: View {
    @Binding var lastEntryDate: Date
    @Binding var selectedAbsorptionTime: CarbAbsorptionTime
    @Binding var expanded: Bool
    var amount: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CarbAbsorptionTime.allCases, id: \.self) { absorptionTime in
                Group {
                    if self.expanded || absorptionTime == self.selectedAbsorptionTime {
                        self.button(for: absorptionTime)
                    }
                }
            }
        }.frame(height: 40)
    }

    private func button(for absorptionTime: CarbAbsorptionTime) -> some View {
        Button(
            action: {
                if self.expanded {
                    self.lastEntryDate = Date()
                    self.selectedAbsorptionTime = absorptionTime
                } else {
                    withAnimation {
                        self.expanded = true
                    }
                }
            },
            label: {
                self.label(for: absorptionTime)
            }
        )
        .buttonStyle(AbsorptionButtonStyle(backgroundColor: self.backgroundColor(for: absorptionTime)))
        .zIndex(absorptionTime == selectedAbsorptionTime ? 1 : 0)
        .frame(maxWidth: 90)
        .transition(self.transition(for: absorptionTime))
    }

    private func label(for absorptionTime: CarbAbsorptionTime) -> some View {
        HStack(spacing: 6) {
            if !expanded && absorptionTime == selectedAbsorptionTime {
                quantityLabel
            }

            Text(absorptionTime.emoji)
                .font(.system(size: 25))
        }
    }

    private var quantityLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            CarbAmountLabel(amount: amount, scale: .small)
            GramLabel(scale: .small)
        }
    }

    private func transition(for absorptionTime: CarbAbsorptionTime) -> AnyTransition {
        let edgeTowardSelectedButton: Edge = absorptionTime.rawValue < selectedAbsorptionTime.rawValue ? .trailing : .leading
        return .moveAndFade(to: edgeTowardSelectedButton)
    }

    private func backgroundColor(for absorptionTime: CarbAbsorptionTime) -> Color {
        if absorptionTime == selectedAbsorptionTime {
            return expanded ? .carbs : .defaultWatchButtonGray
        } else {
            return .darkCarbs
        }
    }
}

private struct AbsorptionButtonStyle: ButtonStyle {
    var backgroundColor: Color

    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
            .overlay(configuration.label)
            .padding(configuration.isPressed ? 1 : 0)
            .overlay(Color.black.opacity(configuration.isPressed ? 0.35 : 0))
    }
}
