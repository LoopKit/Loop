//
//  FoodSearchResultsView.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code for OpenFoodFacts Integration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit

/// View displaying search results from OpenFoodFacts food database
struct FoodSearchResultsView: View {
    let searchResults: [OpenFoodFactsProduct]
    let isSearching: Bool
    let errorMessage: String?
    let onProductSelected: (OpenFoodFactsProduct) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchingView
                    .onAppear {
                        print("🔍 FoodSearchResultsView: Showing searching state")
                    }
            } else if let errorMessage = errorMessage {
                errorView(message: errorMessage)
                    .onAppear {
                        print("🔍 FoodSearchResultsView: Showing error state - \(errorMessage)")
                    }
            } else if searchResults.isEmpty {
                emptyResultsView
                    .onAppear {
                        print("🔍 FoodSearchResultsView: Showing empty results state")
                    }
            } else {
                resultsListView
                    .onAppear {
                        print("🔍 FoodSearchResultsView: Showing \(searchResults.count) results")
                    }
            }
        }
        .onAppear {
            print("🔍 FoodSearchResultsView body: isSearching=\(isSearching), results=\(searchResults.count), error=\(errorMessage ?? "none")")
        }
    }
    
    // MARK: - Subviews
    
    private var searchingView: some View {
        VStack(spacing: 16) {
            // Animated search icon with pulsing effect
            ZStack {
                // Outer pulsing ring
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                
                // Inner filled circle
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 60, height: 60)
                    .scaleEffect(secondaryPulseScale)
                    .animation(
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                        value: secondaryPulseScale
                    )
                
                // Rotating magnifying glass
                Image(systemName: "magnifyingglass")
                    .font(.title)
                    .foregroundColor(.blue)
                    .rotationEffect(rotationAngle)
                    .animation(
                        .linear(duration: 2.0)
                        .repeatForever(autoreverses: false),
                        value: rotationAngle
                    )
            }
            .onAppear {
                pulseScale = 1.3
                secondaryPulseScale = 1.1
                rotationAngle = .degrees(360)
            }
            
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("Searching foods", comment: "Text shown while searching for foods"))
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // Animated dots
                    HStack(spacing: 2) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                                .scaleEffect(dotScales[index])
                                .animation(
                                    .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                    value: dotScales[index]
                                )
                        }
                    }
                    .onAppear {
                        for i in 0..<3 {
                            dotScales[i] = 1.5
                        }
                    }
                }
                
                Text(NSLocalizedString("Finding the best matches for you", comment: "Subtitle shown while searching for foods"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var secondaryPulseScale: CGFloat = 1.0
    @State private var rotationAngle: Angle = .degrees(0)
    @State private var dotScales: [CGFloat] = [1.0, 1.0, 1.0]
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange)
            
            Text(NSLocalizedString("Search Error", comment: "Title for food search error"))
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title)
                .foregroundColor(.orange)
            
            Text(NSLocalizedString("No Foods Found", comment: "Title when no food search results"))
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("Check your spelling and try again", comment: "Primary suggestion when no food search results"))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(NSLocalizedString("Try simpler terms like \"bread\" or \"apple\", or scan a barcode", comment: "Secondary suggestion when no food search results"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Helpful suggestions
            VStack(spacing: 4) {
                Text("💡 Search Tips:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("• Use simple, common food names")
                    Text("• Try brand names (e.g., \"Cheerios\")")
                    Text("• Check spelling carefully")
                    Text("• Use the barcode scanner for packaged foods")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    private var resultsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults, id: \.id) { product in
                    FoodSearchResultRow(
                        product: product,
                        onSelected: { onProductSelected(product) }
                    )
                    .background(Color(.systemBackground))
                    
                    if product.id != searchResults.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: 300)
    }
}

// MARK: - Food Search Result Row

private struct FoodSearchResultRow: View {
    let product: OpenFoodFactsProduct
    let onSelected: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
                // Product image with async loading
                Group {
                    if let thumbnail = FruitThumbnailProvider.thumbnail(for: product.displayName) {
                        // Show emoji-based fruit/veg thumbnail for simple whole foods
                        thumbnail
                            .frame(width: 50, height: 50)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let imageURL = product.imageFrontURL ?? product.imageURL,
                              let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.7)
                                )
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "takeoutbag.and.cup.and.straw")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                
                // Product details
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let brands = product.brands, !brands.isEmpty {
                        Text(brands)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    
                    // Essential nutrition info
                    VStack(alignment: .leading, spacing: 2) {
                        VStack(alignment: .leading, spacing: 1) {
                            // Carbs per serving or per 100g
                            if let carbsPerServing = product.carbsPerServing {
                                Text(String(format: "%.1fg carbs per %@", carbsPerServing, product.servingSizeDisplay))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(String(format: "%.1fg carbs per 100g", product.nutriments.carbohydrates))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                            }
                        }
                        
                        // Additional nutrition if available
                        HStack(spacing: 8) {
                            if let protein = product.nutriments.proteins {
                                Text(String(format: "%.1fg protein", protein))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let fat = product.nutriments.fat {
                                Text(String(format: "%.1fg fat", fat))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    print("🔍 User tapped on food result: \(product.displayName)")
                    onSelected()
                }
                
                // Selection indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lightweight Fruit/Veg Thumbnails

/// Provides emoji-based thumbnails for simple whole foods (e.g., apple, banana).
/// Keeps UI visually helpful when provider (USDA) does not offer images.
private enum FruitThumbnailProvider {
    static func thumbnail(for name: String) -> AnyView? {
        let n = name.lowercased()
        let emoji: String? = {
            switch true {
            // Fruits
            case n.contains("apple"): return "🍎"
            case n.contains("banana"): return "🍌"
            case n.contains("orange"): return "🍊"
            case n.contains("grape"): return "🍇"
            case n.contains("strawberry"): return "🍓"
            case n.contains("blueberry") || n.contains("blueberries"): return "🫐"
            case n.contains("cherry") || n.contains("cherries"): return "🍒"
            case n.contains("pear"): return "🍐"
            case n.contains("peach"): return "🍑"
            case n.contains("mango"): return "🥭"
            case n.contains("pineapple"): return "🍍"
            case n.contains("watermelon"): return "🍉"
            case n.contains("melon"): return "🍈"
            case n.contains("kiwi"): return "🥝"
            case n.contains("coconut"): return "🥥"
            case n.contains("lemon"): return "🍋"
            case n.contains("lime"): return "🟢"
            case n.contains("avocado"): return "🥑"
            // Vegetables
            case n.contains("tomato"): return "🍅"
            case n.contains("carrot"): return "🥕"
            case n.contains("broccoli"): return "🥦"
            case n.contains("cauliflower"): return "🥦"
            case n.contains("lettuce") || n.contains("spinach") || n.contains("kale") || n.contains("greens"): return "🥬"
            case n.contains("cucumber") || n.contains("zucchini"): return "🥒"
            case n.contains("pepper") && !n.contains("chili"): return "🫑"
            case n.contains("chili") || n.contains("chilli") || n.contains("jalapeno"): return "🌶️"
            case n.contains("corn"): return "🌽"
            case n.contains("onion"): return "🧅"
            case n.contains("garlic"): return "🧄"
            case n.contains("mushroom"): return "🍄"
            case n.contains("potato"): return "🥔"
            case n.contains("sweet potato") || n.contains("yam"): return "🍠"
            case n.contains("olive") || n.contains("olives"): return "🫒"
            case n.contains("salad"): return "🥗"
            // Grains / staples
            case n.contains("rice"): return "🍚"
            case n.contains("pasta") || n.contains("spaghetti") || n.contains("noodle") || n.contains("noodles"): return "🍝"
            case n.contains("bread"): return "🍞"
            case n.contains("bagel"): return "🥯"
            case n.contains("oatmeal") || n.contains("oats") || n.contains("cereal"): return "🥣"
            case n.contains("tortilla") || n.contains("flatbread") || n.contains("pita"): return "🫓"
            // Proteins / dairy
            case n.contains("egg"): return "🥚"
            case n.contains("milk"): return "🥛"
            case n.contains("yogurt") || n.contains("yoghurt"): return "🥛"
            case n.contains("cheese"): return "🧀"
            case n.contains("chicken") || n.contains("turkey"): return "🍗"
            case n.contains("beef") || n.contains("steak"): return "🥩"
            case n.contains("pork"): return "🍖"
            case n.contains("fish") || n.contains("salmon") || n.contains("tuna"): return "🐟"
            case n.contains("shrimp") || n.contains("prawn"): return "🍤"
            case n.contains("bean") || n.contains("lentil") || n.contains("chickpea") || n.contains("legume"): return "🫘"
            case n.contains("nut") || n.contains("almond") || n.contains("walnut") || n.contains("peanut"): return "🥜"
            default: return nil
            }
        }()
        guard let e = emoji else { return nil }
        let view = Text(e)
            .font(.system(size: 28))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        return AnyView(view)
    }
}

#if DEBUG
struct FoodSearchResultsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            // Loading state
            FoodSearchResultsView(
                searchResults: [],
                isSearching: true,
                errorMessage: nil,
                onProductSelected: { _ in }
            )
            .frame(height: 100)
            
            Divider()
            
            // Results state
            FoodSearchResultsView(
                searchResults: [
                    OpenFoodFactsProduct.sample(name: "Whole Wheat Bread", carbs: 45.0, servingSize: "2 slices (60g)"),
                    OpenFoodFactsProduct.sample(name: "Brown Rice", carbs: 75.0),
                    OpenFoodFactsProduct.sample(name: "Apple", carbs: 15.0, servingSize: "1 medium (182g)")
                ],
                isSearching: false,
                errorMessage: nil,
                onProductSelected: { _ in }
            )
            
            Divider()
            
            // Error state
            FoodSearchResultsView(
                searchResults: [],
                isSearching: false,
                errorMessage: "Network connection failed",
                onProductSelected: { _ in }
            )
            .frame(height: 150)
            
            Divider()
            
            // Empty state
            FoodSearchResultsView(
                searchResults: [],
                isSearching: false,
                errorMessage: nil,
                onProductSelected: { _ in }
            )
            .frame(height: 150)
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
