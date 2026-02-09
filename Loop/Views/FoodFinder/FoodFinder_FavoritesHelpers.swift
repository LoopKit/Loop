//
//  FoodFinder_FavoritesHelpers.swift
//  Loop
//
//  FoodFinder — Consolidated favorites helpers: name processing,
//  emoji/thumbnail resolution, and enhanced favorites list support.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import UIKit
import LoopKit
import LoopKitUI

// MARK: - FoodFinder_FavoritesViewModel

/// Core favorites logic: name processing, emoji resolution, thumbnail persistence.
enum FoodFinder_FavoritesViewModel {

    // MARK: Name Processing

    /// Truncates `name` to the first five whitespace-separated words.
    static func processNameForSave(_ name: String) -> String {
        let words = name.split { $0.isWhitespace }
        if words.count <= 5 { return name.trimmingCharacters(in: .whitespacesAndNewlines) }
        return words.prefix(5).joined(separator: " ")
    }

    // MARK: Emoji / Food-Type Resolution

    /// Given the food name and its current `foodType`, resolves the food type to
    /// a single emoji when the name or food type matches a known simple food.
    static func resolveFoodType(name: String, foodType: String) -> String {
        let candidateNames = [name, foodType].compactMap { $0 }
        let matchedNameForEmoji = candidateNames.first { EmojiThumbnailProvider.emoji(for: $0) != nil }
        let resolvedEmoji: String? = matchedNameForEmoji.flatMap { EmojiThumbnailProvider.emoji(for: $0) }
        let finalFoodType = resolvedEmoji ?? foodType
        return finalFoodType
    }

    // MARK: Thumbnail Persistence

    /// Saves an emoji-based thumbnail for `food` when one of the `candidateNames`
    /// matches a known simple food. Updates `UserDefaults.favoriteFoodImageIDs`.
    static func saveThumbnailIfNeeded(for food: StoredFavoriteFood, candidateNames: [String]) {
        let matchedNameForEmoji = candidateNames.first { EmojiThumbnailProvider.emoji(for: $0) != nil }
        if let match = matchedNameForEmoji, let image = EmojiThumbnailProvider.image(for: match) {
            if let id = FavoriteFoodImageStore.saveThumbnail(from: image) {
                var map = UserDefaults.standard.favoriteFoodImageIDs
                map[food.id] = id
                UserDefaults.standard.favoriteFoodImageIDs = map
            }
        }
    }

    /// Removes the stored thumbnail for `food` and cleans up the image-ID map.
    static func deleteThumbnail(for food: StoredFavoriteFood) {
        var map = UserDefaults.standard.favoriteFoodImageIDs
        if let id = map[food.id] {
            FavoriteFoodImageStore.deleteThumbnail(id: id)
            map.removeValue(forKey: food.id)
            UserDefaults.standard.favoriteFoodImageIDs = map
        }
    }

    // MARK: Thumbnail Loading

    /// Loads the thumbnail `UIImage` previously saved for `food`, if any.
    static func thumbnailForFood(_ food: StoredFavoriteFood) -> UIImage? {
        let map = UserDefaults.standard.favoriteFoodImageIDs
        guard let id = map[food.id] else { return nil }
        return FavoriteFoodImageStore.loadThumbnail(id: id)
    }

    // MARK: - AddEditFavoriteFoodViewModel Helpers

    /// Maximum character length for a favourite-food name.
    static let maxNameLength = 30

    /// Truncates `raw` to `maxNameLength` characters after trimming whitespace.
    static func truncatedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed
        guard clean.count > maxNameLength else { return clean }
        let endIndex = clean.index(clean.startIndex, offsetBy: maxNameLength)
        return String(clean[..<endIndex])
    }

    /// Resolves the food type by preferring an emoji match from the initial value
    /// or any of the additional candidates.
    static func resolvedFoodType(initial: String, additionalCandidates: [String?]) -> String {
        let trimmedInitial = initial.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraCandidates = additionalCandidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmptyExtras = extraCandidates.filter { !$0.isEmpty }

        let lookupCandidates = ([trimmedInitial] + nonEmptyExtras).filter { !$0.isEmpty }
        if let emoji = lookupCandidates.compactMap({ EmojiThumbnailProvider.emoji(for: $0) }).first {
            return emoji
        }

        if !trimmedInitial.isEmpty {
            return trimmedInitial
        }
        return nonEmptyExtras.first ?? trimmedInitial
    }
}

// MARK: - FoodFinder_FavoriteEditHelper

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

// MARK: - FoodFinder_FavoritesHelper

/// Provides FoodFinder thumbnail loading for the existing FavoriteFoodsView.
enum FoodFinder_FavoritesHelper {

    /// Load the stored thumbnail for a favorite food, if one exists.
    static func thumbnail(for food: StoredFavoriteFood) -> UIImage? {
        let map = UserDefaults.standard.favoriteFoodImageIDs
        guard let id = map[food.id] else { return nil }
        return FavoriteFoodImageStore.loadThumbnail(id: id)
    }
}

// MARK: - Favorite Thumbnail Views

/// A standalone thumbnail header view for use in the favorite food detail screen.
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
