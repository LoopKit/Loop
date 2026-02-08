//
//  FoodFinder_FavoriteEditView.swift
//  Loop
//
//  FoodFinder — Provides the suggestedName enhancement for AddEditFavoriteFoodView.
//  When FoodFinder is enabled and a food product is selected, this helper
//  extracts a suggested name for pre-populating the favorite food form.
//

import Foundation

/// Helpers for enhancing the AddEditFavoriteFoodView with FoodFinder data.
enum FoodFinder_FavoriteEditHelper {

    /// Extract a suggested name from a selected food product's display name.
    /// Returns nil if no product is selected or the name is empty.
    static func suggestedName(from productName: String?) -> String? {
        guard let name = productName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return FoodFinder_FavoritesViewModel.truncatedName(name)
    }
}
