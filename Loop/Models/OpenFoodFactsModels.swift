//
//  OpenFoodFactsModels.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code in June 2025
//  Copyright © 20253 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - OpenFoodFacts API Response Models

/// Root response structure for OpenFoodFacts search API
struct OpenFoodFactsSearchResponse: Codable {
    let products: [OpenFoodFactsProduct]
    let count: Int
    let page: Int
    let pageCount: Int
    let pageSize: Int
    
    enum CodingKeys: String, CodingKey {
        case products
        case count
        case page
        case pageCount = "page_count"
        case pageSize = "page_size"
    }
}

/// Response structure for single product lookup by barcode
struct OpenFoodFactsProductResponse: Codable {
    let code: String
    let product: OpenFoodFactsProduct?
    let status: Int
    let statusVerbose: String
    
    enum CodingKeys: String, CodingKey {
        case code
        case product
        case status
        case statusVerbose = "status_verbose"
    }
}

// MARK: - Core Product Models

/// Food data source types
enum FoodDataSource: String, CaseIterable, Codable {
    case barcodeScan = "barcode_scan"
    case textSearch = "text_search"
    case aiAnalysis = "ai_analysis"
    case manualEntry = "manual_entry"
    case unknown = "unknown"
}

/// Represents a food product from OpenFoodFacts database
struct OpenFoodFactsProduct: Codable, Identifiable, Hashable {
    let id: String
    let productName: String?
    let brands: String?
    let categories: String?
    let nutriments: Nutriments
    let servingSize: String?
    let servingQuantity: Double?
    let imageURL: String?
    let imageFrontURL: String?
    let code: String? // barcode
    var dataSource: FoodDataSource = .unknown
    
    // Non-codable property for UI state only
    var isSkeleton: Bool = false // Flag to identify skeleton loading items
    
    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case categories
        case nutriments
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case imageURL = "image_url"
        case imageFrontURL = "image_front_url"
        case code
        case dataSource = "data_source"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle product identification
        let code = try container.decodeIfPresent(String.self, forKey: .code)
        let productName = try container.decodeIfPresent(String.self, forKey: .productName)
        
        // Generate ID from barcode or create synthetic one
        if let code = code {
            self.id = code
            self.code = code
        } else {
            // Create synthetic ID for products without barcodes
            let name = productName ?? "unknown"
            self.id = "synthetic_\(abs(name.hashValue))"
            self.code = nil
        }
        
        self.productName = productName
        self.brands = try container.decodeIfPresent(String.self, forKey: .brands)
        self.categories = try container.decodeIfPresent(String.self, forKey: .categories)
        // Handle nutriments with fallback
        self.nutriments = (try? container.decode(Nutriments.self, forKey: .nutriments)) ?? Nutriments.empty()
        self.servingSize = try container.decodeIfPresent(String.self, forKey: .servingSize)
        // Handle serving_quantity which can be String or Double
        if let servingQuantityDouble = try? container.decodeIfPresent(Double.self, forKey: .servingQuantity) {
            self.servingQuantity = servingQuantityDouble
        } else if let servingQuantityString = try? container.decodeIfPresent(String.self, forKey: .servingQuantity) {
            self.servingQuantity = Double(servingQuantityString)
        } else {
            self.servingQuantity = nil
        }
        self.imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        self.imageFrontURL = try container.decodeIfPresent(String.self, forKey: .imageFrontURL)
        // dataSource has a default value, but override if present in decoded data
        if let decodedDataSource = try? container.decode(FoodDataSource.self, forKey: .dataSource) {
            self.dataSource = decodedDataSource
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(productName, forKey: .productName)
        try container.encodeIfPresent(brands, forKey: .brands)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encode(nutriments, forKey: .nutriments)
        try container.encodeIfPresent(servingSize, forKey: .servingSize)
        try container.encodeIfPresent(servingQuantity, forKey: .servingQuantity)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(imageFrontURL, forKey: .imageFrontURL)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encode(dataSource, forKey: .dataSource)
        // Note: isSkeleton is intentionally not encoded as it's UI state only
    }
    
    // MARK: - Custom Initializers
    
    /// Create a skeleton product for loading states
    init(id: String, productName: String?, brands: String?, categories: String? = nil, nutriments: Nutriments, servingSize: String?, servingQuantity: Double?, imageURL: String?, imageFrontURL: String?, code: String?, dataSource: FoodDataSource = .unknown, isSkeleton: Bool = false) {
        self.id = id
        self.productName = productName
        self.brands = brands
        self.categories = categories
        self.nutriments = nutriments
        self.servingSize = servingSize
        self.servingQuantity = servingQuantity
        self.imageURL = imageURL
        self.imageFrontURL = imageFrontURL
        self.code = code
        self.dataSource = dataSource
        self.isSkeleton = isSkeleton
    }
    
    // MARK: - Computed Properties
    
    /// Display name with fallback logic
    var displayName: String {
        if let productName = productName, !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return productName
        } else if let brands = brands, !brands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return brands
        } else {
            return NSLocalizedString("Unknown Product", comment: "Fallback name for products without names")
        }
    }
    
    /// Carbohydrates per serving (calculated from 100g values if serving size available)
    var carbsPerServing: Double? {
        guard let servingQuantity = servingQuantity, servingQuantity > 0 else {
            return nutriments.carbohydrates
        }
        return (nutriments.carbohydrates * servingQuantity) / 100.0
    }
    
    /// Protein per serving (calculated from 100g values if serving size available)
    var proteinPerServing: Double? {
        guard let protein = nutriments.proteins,
              let servingQuantity = servingQuantity, servingQuantity > 0 else {
            return nutriments.proteins
        }
        return (protein * servingQuantity) / 100.0
    }
    
    /// Fat per serving (calculated from 100g values if serving size available)
    var fatPerServing: Double? {
        guard let fat = nutriments.fat,
              let servingQuantity = servingQuantity, servingQuantity > 0 else {
            return nutriments.fat
        }
        return (fat * servingQuantity) / 100.0
    }
    
    /// Calories per serving (calculated from 100g values if serving size available)
    var caloriesPerServing: Double? {
        guard let calories = nutriments.calories,
              let servingQuantity = servingQuantity, servingQuantity > 0 else {
            return nutriments.calories
        }
        return (calories * servingQuantity) / 100.0
    }
    
    /// Fiber per serving (calculated from 100g values if serving size available)
    var fiberPerServing: Double? {
        guard let fiber = nutriments.fiber,
              let servingQuantity = servingQuantity, servingQuantity > 0 else {
            return nutriments.fiber
        }
        return (fiber * servingQuantity) / 100.0
    }
    
    /// Formatted serving size display text
    var servingSizeDisplay: String {
        if let servingSize = servingSize, !servingSize.isEmpty {
            return servingSize
        } else if let servingQuantity = servingQuantity, servingQuantity > 0 {
            return "\(Int(servingQuantity))g"
        } else {
            return "100g"
        }
    }
    
    /// Whether this product has sufficient nutritional data for Loop
    var hasSufficientNutritionalData: Bool {
        return nutriments.carbohydrates >= 0 && !displayName.isEmpty
    }
    
    // MARK: - Hashable & Equatable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: OpenFoodFactsProduct, rhs: OpenFoodFactsProduct) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Nutritional information for a food product - simplified to essential nutrients only
struct Nutriments: Codable {
    let carbohydrates: Double
    let proteins: Double?
    let fat: Double?
    let calories: Double?
    let sugars: Double?
    let fiber: Double?
    let energy: Double?
    
    enum CodingKeys: String, CodingKey {
        case carbohydratesServing = "carbohydrates_serving"
        case carbohydrates100g = "carbohydrates_100g"
        case proteinsServing = "proteins_serving"
        case proteins100g = "proteins_100g"
        case fatServing = "fat_serving"
        case fat100g = "fat_100g"
        case caloriesServing = "energy-kcal_serving"
        case calories100g = "energy-kcal_100g"
        case sugarsServing = "sugars_serving"
        case sugars100g = "sugars_100g"
        case fiberServing = "fiber_serving"
        case fiber100g = "fiber_100g"
        case energyServing = "energy_serving"
        case energy100g = "energy_100g"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Use 100g values as base since serving sizes are often incorrect in the database
        // The app will handle serving size calculations based on actual product weight
        self.carbohydrates = try container.decodeIfPresent(Double.self, forKey: .carbohydrates100g) ?? 0.0
        self.proteins = try container.decodeIfPresent(Double.self, forKey: .proteins100g)
        self.fat = try container.decodeIfPresent(Double.self, forKey: .fat100g)
        self.calories = try container.decodeIfPresent(Double.self, forKey: .calories100g)
        self.sugars = try container.decodeIfPresent(Double.self, forKey: .sugars100g)
        self.fiber = try container.decodeIfPresent(Double.self, forKey: .fiber100g)
        self.energy = try container.decodeIfPresent(Double.self, forKey: .energy100g)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode as 100g values since that's what we're using internally
        try container.encode(carbohydrates, forKey: .carbohydrates100g)
        try container.encodeIfPresent(proteins, forKey: .proteins100g)
        try container.encodeIfPresent(fat, forKey: .fat100g)
        try container.encodeIfPresent(calories, forKey: .calories100g)
        try container.encodeIfPresent(sugars, forKey: .sugars100g)
        try container.encodeIfPresent(fiber, forKey: .fiber100g)
        try container.encodeIfPresent(energy, forKey: .energy100g)
    }
    
    /// Manual initializer for programmatic creation (e.g., AI analysis)
    init(carbohydrates: Double, proteins: Double? = nil, fat: Double? = nil, calories: Double? = nil, sugars: Double? = nil, fiber: Double? = nil, energy: Double? = nil) {
        self.carbohydrates = carbohydrates
        self.proteins = proteins
        self.fat = fat
        self.calories = calories
        self.sugars = sugars
        self.fiber = fiber
        self.energy = energy
    }
    
    /// Create empty nutriments with zero values
    static func empty() -> Nutriments {
        return Nutriments(carbohydrates: 0.0, proteins: nil, fat: nil, calories: nil, sugars: nil, fiber: nil, energy: nil)
    }
}

// MARK: - Error Types

/// Errors that can occur when interacting with OpenFoodFacts API
enum OpenFoodFactsError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case decodingError(Error)
    case networkError(Error)
    case productNotFound
    case invalidBarcode
    case rateLimitExceeded
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid API URL", comment: "Error message for invalid OpenFoodFacts URL")
        case .invalidResponse:
            return NSLocalizedString("Invalid API response", comment: "Error message for invalid OpenFoodFacts response")
        case .noData:
            return NSLocalizedString("No data received", comment: "Error message when no data received from OpenFoodFacts")
        case .decodingError(let error):
            return String(format: NSLocalizedString("Failed to decode response: %@", comment: "Error message for JSON decoding failure"), error.localizedDescription)
        case .networkError(let error):
            return String(format: NSLocalizedString("Network error: %@", comment: "Error message for network failures"), error.localizedDescription)
        case .productNotFound:
            return NSLocalizedString("Product not found", comment: "Error message when product is not found in OpenFoodFacts database")
        case .invalidBarcode:
            return NSLocalizedString("Invalid barcode format", comment: "Error message for invalid barcode")
        case .rateLimitExceeded:
            return NSLocalizedString("Too many requests. Please try again later.", comment: "Error message for API rate limiting")
        case .serverError(let code):
            return String(format: NSLocalizedString("Server error (%d)", comment: "Error message for server errors"), code)
        }
    }
    
    var failureReason: String? {
        switch self {
        case .invalidURL:
            return "The OpenFoodFacts API URL is malformed"
        case .invalidResponse:
            return "The API response format is invalid"
        case .noData:
            return "The API returned no data"
        case .decodingError:
            return "The API response format is unexpected"
        case .networkError:
            return "Network connectivity issue"
        case .productNotFound:
            return "The barcode or product is not in the database"
        case .invalidBarcode:
            return "The barcode format is not valid"
        case .rateLimitExceeded:
            return "API usage limit exceeded"
        case .serverError:
            return "OpenFoodFacts server is experiencing issues"
        }
    }
}

// MARK: - Testing Support

#if DEBUG
extension OpenFoodFactsProduct {
    /// Create a sample product for testing
    static func sample(
        name: String = "Sample Product",
        carbs: Double = 25.0,
        servingSize: String? = "100g"
    ) -> OpenFoodFactsProduct {
        return OpenFoodFactsProduct(
            id: "sample_\(abs(name.hashValue))",
            productName: name,
            brands: "Sample Brand",
            categories: "Sample Category",
            nutriments: Nutriments.sample(carbs: carbs),
            servingSize: servingSize,
            servingQuantity: 100.0,
            imageURL: nil,
            imageFrontURL: nil,
            code: "1234567890123"
        )
    }
}

extension Nutriments {
    /// Create sample nutriments for testing
    static func sample(carbs: Double = 25.0) -> Nutriments {
        return Nutriments(
            carbohydrates: carbs,
            proteins: 8.0,
            fat: 2.0,
            calories: nil,
            sugars: nil,
            fiber: nil,
            energy: nil
        )
    }
}

extension OpenFoodFactsProduct {
    init(id: String, productName: String?, brands: String?, categories: String?, nutriments: Nutriments, servingSize: String?, servingQuantity: Double?, imageURL: String?, imageFrontURL: String?, code: String?) {
        self.id = id
        self.productName = productName
        self.brands = brands
        self.categories = categories
        self.nutriments = nutriments
        self.servingSize = servingSize
        self.servingQuantity = servingQuantity
        self.imageURL = imageURL
        self.imageFrontURL = imageFrontURL
        self.code = code
    }
    
    // Simplified initializer for programmatic creation
    init(id: String, productName: String, brands: String, nutriments: Nutriments, servingSize: String, imageURL: String?) {
        self.id = id
        self.productName = productName
        self.brands = brands
        self.categories = nil
        self.nutriments = nutriments
        self.servingSize = servingSize
        self.servingQuantity = 100.0
        self.imageURL = imageURL
        self.imageFrontURL = imageURL
        self.code = nil
    }
}

extension Nutriments {
    init(carbohydrates: Double, proteins: Double?, fat: Double?) {
        self.carbohydrates = carbohydrates
        self.proteins = proteins
        self.fat = fat
        self.calories = nil
        self.sugars = nil
        self.fiber = nil
        self.energy = nil
    }
}
#endif
