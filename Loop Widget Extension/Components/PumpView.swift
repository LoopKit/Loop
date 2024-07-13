//
//  PumpView.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct PumpView: View {
    
    var entry: StatusWidgetTimelineProvider.Entry
    
    var body: some View {
        HStack(alignment: .center) {
            if let pumpHighlight = entry.pumpHighlight {
                HStack {
                    Image(systemName: pumpHighlight.imageName)
                        .foregroundColor(pumpHighlight.state == .critical ? .critical : .warning)
                    Text(pumpHighlight.localizedMessage)
                        .fontWeight(.heavy)
                }
            }
            else if let netBasal = entry.netBasal {
                BasalView(netBasal: netBasal, isOld: entry.contextIsStale)
                
                if let eventualGlucose = entry.eventualGlucose {
                    let glucoseFormatter = NumberFormatter.glucoseFormatter(for: eventualGlucose.unit)
                    if let glucoseString = glucoseFormatter.string(from: eventualGlucose.quantity.doubleValue(for: eventualGlucose.unit)) {
                        VStack {
                            Text("Eventual")
                                .font(.footnote)
                                .foregroundColor(entry.contextIsStale ? Color(UIColor.systemGray3) : Color(UIColor.secondaryLabel))
                            
                            Text("\(glucoseString)")
                                .font(.subheadline)
                                .fontWeight(.heavy)
                            
                            Text(eventualGlucose.unit.shortLocalizedUnitString())
                                .font(.footnote)
                                .foregroundColor(entry.contextIsStale ? Color(UIColor.systemGray3) : Color(UIColor.secondaryLabel))
                        }
                    }
                }
            }
            
        }
    }
}
