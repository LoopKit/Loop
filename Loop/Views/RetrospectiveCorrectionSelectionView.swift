//
//  RetrospectiveCorrectionSelectionView.swift
//  Loop
//
//  Created by Dragan Maksimovic on 9/18/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopCore
import LoopKitUI

public struct RetrospectiveCorrectionSelectionView: View {
    
    @Binding private var retrospectiveCorrection: RetrospectiveCorrectionOptions
    
    @State private var internalRetrospectiveCorrection: RetrospectiveCorrectionOptions
    
    public init(retrospectiveCorrection: Binding<RetrospectiveCorrectionOptions>) {
        self._retrospectiveCorrection = retrospectiveCorrection
        self._internalRetrospectiveCorrection = State(initialValue: retrospectiveCorrection.wrappedValue)
    }
    
    public var body: some View {
        List {
            Section {
                options
            }
            .buttonStyle(PlainButtonStyle()) // Disable row highlighting on selection
        }
        .insetGroupedListStyle()
    }

    public var options: some View {
        ForEach(RetrospectiveCorrectionOptions.allCases, id: \.self) { rcOption in
            CheckmarkListItem(
                title: Text(rcOption.title),
                description: Text(rcOption.informationalText),
                isSelected: Binding(
                    get: { self.retrospectiveCorrection == rcOption },
                    set: { isSelected in
                        if isSelected {
                            self.retrospectiveCorrection = rcOption
                            self.internalRetrospectiveCorrection = rcOption // Hack to force update. :(
                        }
                    }
                )
            )
            .padding(.vertical, 4)
        }
    }
}

extension RetrospectiveCorrectionOptions {
    var informationalText: String {
        switch self {
        case .standardRetrospectiveCorrection:
            return NSLocalizedString("Correcton to glucose forecast based on the most recent 30 min comparison of glucose prediction vs actual, continued with decay over 60 min.", comment: "Description string for standard retrospective correction")
        case .integralRetrospectiveCorrection:
            return NSLocalizedString("Correction to glucose forecast based on the most recent and past 30 min discrepancies between glucose prediction vs actual. Compared to standard retrospective correction, integral retrospective correction results in increased insulin corrections when glucose persistently drops slower than expected, and in reduced insulin delivery when glucose persistently drops faster than expected.", comment: "Description string for integral retrospective correction")
        }
    }

}

struct RetrospectiveCorrectionSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        RetrospectiveCorrectionSelectionView(retrospectiveCorrection: .constant(.standardRetrospectiveCorrection))
    }
}
