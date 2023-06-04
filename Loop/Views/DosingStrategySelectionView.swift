//
//  DosingStrategySelectionView.swift
//  Loop
//
//  Created by Pete Schwamb on 1/16/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopCore
import LoopKit
import LoopKitUI

public struct DosingStrategySelectionView: View {
    
    @Binding private var automaticDosingStrategy: AutomaticDosingStrategy
    
    @State private var internalDosingStrategy: AutomaticDosingStrategy
    
    public init(automaticDosingStrategy: Binding<AutomaticDosingStrategy>) {
        self._automaticDosingStrategy = automaticDosingStrategy
        self._internalDosingStrategy = State(initialValue: automaticDosingStrategy.wrappedValue)
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
        ForEach(AutomaticDosingStrategy.allCases, id: \.self) { strategy in
            CheckmarkListItem(
                title: Text(strategy.title),
                description: Text(strategy.informationalText),
                isSelected: Binding(
                    get: { self.automaticDosingStrategy == strategy },
                    set: { isSelected in
                        if isSelected {
                            self.automaticDosingStrategy = strategy
                            self.internalDosingStrategy = strategy // Hack to force update. :(
                        }
                    }
                )
            )
            .padding(.vertical, 4)
        }
    }
}

extension AutomaticDosingStrategy {
    var informationalText: String {
        switch self {
        case .tempBasalOnly:
            return NSLocalizedString("Loop will set temporary basal rates to increase and decrease insulin delivery.", comment: "Description string for temp basal only dosing strategy")
        case .automaticBolus:
            return NSLocalizedString("Loop will automatically bolus when insulin needs are above scheduled basal, and will use temporary basal rates when needed to reduce insulin delivery below scheduled basal.", comment: "Description string for automatic bolus dosing strategy")
        }
    }

}

struct DosingStrategySelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DosingStrategySelectionView(automaticDosingStrategy: .constant(.automaticBolus))
    }
}
