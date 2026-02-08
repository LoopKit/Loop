//
//  FoodFinder_FavoriteDetailView.swift
//  Loop
//
//  FoodFinder — Enhanced favorite food detail with thumbnail display.
//  Provides a thumbnail section that can be inserted into the existing
//  FavoriteFoodDetailView via a single call site.
//

import SwiftUI
import UIKit
import LoopKit

/// A standalone thumbnail header view for use in the favorite food detail screen.
/// The host detail view embeds this conditionally when FoodFinder is enabled.
struct FoodFinder_FavoriteThumbnail: View {
    let food: StoredFavoriteFood

    var body: some View {
        if let thumb = FoodFinder_FavoritesHelper.thumbnail(for: food) {
            Section {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))
        }
    }
}

/// A small inline thumbnail for the food type row in the detail view.
struct FoodFinder_FoodTypeThumbnail: View {
    let food: StoredFavoriteFood

    var body: some View {
        if let thumb = FoodFinder_FavoritesHelper.thumbnail(for: food) {
            Image(uiImage: thumb)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
        }
    }
}
