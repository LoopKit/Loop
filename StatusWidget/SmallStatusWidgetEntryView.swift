//
//  SmallStatusWidgetEntryView.swift
//  Loop
//
//  Created by Pete Schwamb on 11/23/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

import SwiftUI
import LoopUI

struct SmallStatusWidgetEntryView : View {
    var entry: StatusWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(alignment: .center) {
                LoopCircleView(entry: entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // There is a SwiftUI bug which causes view not to be padded correctly when using .border
                // Added padding to counteract the width of the border
                    .padding(.leading, 8)

                GlucoseView(entry: entry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(5)
            .background(
                ContainerRelativeShape()
                    .fill(Color("WidgetSecondaryBackground"))
            )

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

            }.frame(maxWidth: .infinity, alignment: .center)

            .frame(maxHeight: .infinity, alignment: .center)
            .padding(5)
            .background(
                ContainerRelativeShape()
                    .fill(Color("WidgetSecondaryBackground"))
            )
        }
        .foregroundColor(entry.contextIsStale ? Color(UIColor.systemGray3) : nil)
        .padding(5)
        .background(Color("WidgetBackground"))
    }
}
