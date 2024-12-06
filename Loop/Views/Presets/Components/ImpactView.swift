//
//  ImpactView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/24/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI

public struct ImpactView<Content: View>: View {
    
    @ViewBuilder let content: () -> Content
    
    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    Text(Image(systemName: "exclamationmark.circle.fill"))
                        .foregroundColor(.accentColor) +
                    Text(" Consider the Impact", comment: "Impact title")
                }
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text("Consider the Impact", comment: "Impact title accessibility label"))
                
                content()
                    .font(.subheadline)
            }
        }
    }
}
