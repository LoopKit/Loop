//
//  FoodFinder_FavoritesViewModel.swift
//  Loop
//
//  FoodFinder — helper that encapsulates the FoodFinder-specific
//  emoji/thumbnail logic originally added to FavoriteFoodsViewModel
//  and AddEditFavoriteFoodViewModel.
//
//  Call sites in the host ViewModels delegate to these static methods
//  so that all FoodFinder behaviour can be toggled from one place.
//

import Foundation
import UIKit
import LoopKit

// MARK: - FoodFinder_FavoritesViewModel

enum FoodFinder_FavoritesViewModel {

    // MARK: Name Processing (from FavoriteFoodsViewModel)

    /// Truncates `name` to the first five whitespace-separated words.
    /// Copied verbatim from `FavoriteFoodsViewModel.firstFiveWords(of:)`.
    static func processNameForSave(_ name: String) -> String {
        let words = name.split { $0.isWhitespace }
        if words.count <= 5 { return name.trimmingCharacters(in: .whitespacesAndNewlines) }
        return words.prefix(5).joined(separator: " ")
    }

    // MARK: Emoji / Food-Type Resolution (from FavoriteFoodsViewModel.onFoodSave)

    /// Given the food name and its current `foodType`, resolves the food type to
    /// a single emoji when the name or food type matches a known simple food.
    /// Mirrors the candidate-lookup block inside `onFoodSave`.
    static func resolveFoodType(name: String, foodType: String) -> String {
        let candidateNames = [name, foodType].compactMap { $0 }
        let matchedNameForEmoji = candidateNames.first { EmojiThumbnailProvider.emoji(for: $0) != nil }
        let resolvedEmoji: String? = matchedNameForEmoji.flatMap { EmojiThumbnailProvider.emoji(for: $0) }
        let finalFoodType = resolvedEmoji ?? foodType
        return finalFoodType
    }

    // MARK: Thumbnail Persistence (from FavoriteFoodsViewModel.onFoodSave)

    /// Saves an emoji-based thumbnail for `food` when one of the `candidateNames`
    /// matches a known simple food.  Updates `UserDefaults.favoriteFoodImageIDs`.
    /// Copied from both the "add" and "edit" branches of `onFoodSave`.
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

    // MARK: Thumbnail Deletion (from FavoriteFoodsViewModel.onFoodDelete)

    /// Removes the stored thumbnail for `food` and cleans up the image-ID map.
    /// Copied from `onFoodDelete`.
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
    /// Copied from `AddEditFavoriteFoodViewModel.maxNameLength`.
    static let maxNameLength = 30

    /// Truncates `raw` to `maxNameLength` characters after trimming whitespace.
    /// Copied verbatim from `AddEditFavoriteFoodViewModel.truncatedName(_:)`.
    static func truncatedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed
        guard clean.count > maxNameLength else { return clean }
        let endIndex = clean.index(clean.startIndex, offsetBy: maxNameLength)
        return String(clean[..<endIndex])
    }

    /// Resolves the food type by preferring an emoji match from the initial value
    /// or any of the additional candidates.
    /// Copied verbatim from `AddEditFavoriteFoodViewModel.resolvedFoodType(initial:additionalCandidates:)`.
    static func resolvedFoodType(initial: String, additionalCandidates: [String?]) -> String {
        let trimmedInitial = initial.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraCandidates = additionalCandidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmptyExtras = extraCandidates.filter { !$0.isEmpty }

        // Prefer any mapped emoji for known simple foods using the provided candidates.
        let lookupCandidates = ([trimmedInitial] + nonEmptyExtras).filter { !$0.isEmpty }
        if let emoji = lookupCandidates.compactMap({ EmojiThumbnailProvider.emoji(for: $0) }).first {
            return emoji
        }

        // If no emoji mapping, fall back to the first non-empty candidate (initial or provided name).
        if !trimmedInitial.isEmpty {
            return trimmedInitial
        }
        return nonEmptyExtras.first ?? trimmedInitial
    }
}
