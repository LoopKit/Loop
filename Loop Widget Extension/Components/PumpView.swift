//
//  PumpView.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct PumpView: View {
    var entry: StatusWidgetTimelimeEntry
    
    var body: some View {
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
        }
    }
}
