//
//  LabelValueRow.swift
//  Loop
//
//  Created by Pete Schwamb on 9/20/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct LabelValueRow<ValueView: View>: View {
    let label: LocalizedStringKey
    let value: ValueView

    init(_ label: LocalizedStringKey, @ViewBuilder value: () -> ValueView) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            value
                .font(.title3)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
