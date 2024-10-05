//
//  FavoriteFoodInsightsCardView.swift
//  Loop
//
//  Created by Noah Brauner on 8/7/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct FavoriteFoodInsightsCardView: View {
    @Binding var showFavoriteFoodInsights: Bool
    let foodName: String?
    let lastEatenDate: Date?
    let relativeDateFormatter: RelativeDateTimeFormatter
    var presentInSection: Bool = false
    
    var body: some View {
        if presentInSection {
            Section {
                content
                    .overlay(border)
                    .contentShape(Rectangle())
                    .listRowInsets(EdgeInsets())
                    .buttonStyle(PlainButtonStyle())
            }
        }
        else {
            content
                .background(CardBackground())
                .overlay(border)
                .padding(.horizontal)
                .contentShape(Rectangle())
        }
    }
    
    private var border: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 2)
    }
    
    private var content: some View {
        Button(action: {
            showFavoriteFoodInsights = true
        }) {
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")

                    Text("Favorite Food Insights")
                }
                .font(.headline)
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if let foodName, let lastEatenDate {
                    let relativeTime = relativeDateFormatter.localizedString(for: lastEatenDate, relativeTo: Date())
                    let attributedFoodDescription = attributedFoodInsightsDescription(for: foodName, timeAgo: relativeTime)
                    
                    Text(attributedFoodDescription)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
        }
    }
    
    private func attributedFoodInsightsDescription(for food: String, timeAgo: String) -> AttributedString {
        var attributedString = AttributedString("You last ate ")
        
        var foodString = AttributedString(food)
        foodString.inlinePresentationIntent = .stronglyEmphasized
        
        attributedString.append(foodString)
        attributedString.append(AttributedString(" \(timeAgo)\n Tap to see more"))
        
        return attributedString
    }
}
