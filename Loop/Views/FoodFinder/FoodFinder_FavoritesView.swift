//
//  FoodFinder_FavoritesView.swift
//  Loop
//
//  FoodFinder — Enhanced favorites list with thumbnail support.
//  This wraps/enhances the existing FavoriteFoodsView without modifying LoopKit.
//

import SwiftUI
import UIKit
import LoopKit
import LoopKitUI

/// Provides FoodFinder thumbnail loading for the existing FavoriteFoodsView.
/// Instead of modifying LoopKit's FavoriteFoodListRow, this helper supplies
/// thumbnails that the host view can pass through.
enum FoodFinder_FavoritesHelper {

    /// Load the stored thumbnail for a favorite food, if one exists.
    static func thumbnail(for food: StoredFavoriteFood) -> UIImage? {
        let map = UserDefaults.standard.favoriteFoodImageIDs
        guard let id = map[food.id] else { return nil }
        return FavoriteFoodImageStore.loadThumbnail(id: id)
    }
}
