//
//  DosingStrategySelectionView.swift
//  Loop
//
//  Created by Pete Schwamb on 1/16/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopCore
import LoopKitUI

public struct DosingStrategySelectionView: View {
    
    @Binding private var dosingStrategy: DosingStrategy
    
    public init(dosingStrategy: Binding<DosingStrategy>) {
        self._dosingStrategy = dosingStrategy
    }
    
    public var body: some View {
        List {
            Section {
                Text(dosingStrategy.title)
            }
            Section {
                options
            }
            .buttonStyle(PlainButtonStyle()) // Disable row highlighting on selection
        }
        .insetGroupedListStyle()
    }

    public var options: some View {
        ForEach(DosingStrategy.allCases, id: \.self) { strategy in
            CheckmarkListItem(
                title: Text(strategy.title),
                description: Text(strategy.subtitle),
                isSelected: Binding(
                    get: { self.dosingStrategy == strategy },
                    set: { isSelected in
                        if isSelected {
                            withAnimation {
                                self.dosingStrategy = strategy
                            }
                        }
                    }
                )
            )
            .padding(.vertical, 4)
        }
    }
}

struct DosingStrategySelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DosingStrategySelectionView(dosingStrategy: .constant(.automaticBolus))
    }
}
