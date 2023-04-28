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
    @Binding private var applyLinearRampToBolusApplicationFactor: Bool

    @State private var internalDosingStrategy: AutomaticDosingStrategy
    
    public init(automaticDosingStrategy: Binding<AutomaticDosingStrategy>, applyLinearRampToBolusApplicationFactor: Binding<Bool>) {
        self._automaticDosingStrategy = automaticDosingStrategy
        self._applyLinearRampToBolusApplicationFactor = applyLinearRampToBolusApplicationFactor
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
                ),
                trailingView: strategy.isAutomaticBolus ? linearRampVolusApplicationFactorSection : nil
            )
            .padding(.vertical, 4)
        }
    }
}

extension DosingStrategySelectionView {
    var linearRampVolusApplicationFactorSection: AnyView {
        return AnyView(
            Toggle(isOn: $applyLinearRampToBolusApplicationFactor) {
                VStack(alignment: .leading) {
                    Text("Linear Bolus Ramp", comment: "The title text for the Apply Linear Ramp to Bolus Application Factor toggle")
                        .padding(.vertical, 0.5)
                    Text("Loop will apply a linear ramp to the bolus application factor, gradually increasing the partial bolus factor as glucose levels rise. ", comment: "Description string for Apply Linear Ramp to Bolus Application Factor toggle")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!automaticDosingStrategy.isAutomaticBolus)
        )
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

    var isAutomaticBolus: Bool {
        return self == .automaticBolus
    }
}

struct DosingStrategySelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DosingStrategySelectionView(automaticDosingStrategy: .constant(.automaticBolus), applyLinearRampToBolusApplicationFactor: .constant(false))
    }
}
