//
//  LoopCircleView.swift
//  Loop
//
//  Created by Noah Brauner on 8/15/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopCore

struct LoopCircleView: View {
    var entry: StatusWidgetEntry

    var body: some View {
        let closeLoop = entry.closeLoop
        let lastLoopCompleted = entry.lastLoopCompleted ?? Date().addingTimeInterval(.minutes(16))
        let age = abs(min(0, lastLoopCompleted.timeIntervalSinceNow))
        let freshness = LoopCompletionFreshness(age: age)
        
        let loopColor = getLoopColor(freshness: freshness)
        
        Circle()
            .trim(from: closeLoop ? 0 : 0.2, to: 1)
            .stroke(entry.contextIsStale ? Color(UIColor.systemGray3) : loopColor, lineWidth: 8)
            .rotationEffect(Angle(degrees: -126))
            .frame(width: 36, height: 36)
    }
    
    func getLoopColor(freshness: LoopCompletionFreshness) -> Color {
        switch freshness {
        case .fresh:
            return Color("fresh")
        case .aging:
            return Color("warning")
        case .stale:
            return Color.red
        }
    }

    static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .short

        return formatter
    }()
}
