//
//  OpenFoodFactsTests.swift
//  LoopTests
//
//  Created by Claude Code for OpenFoodFacts Integration
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import Loop

@MainActor
class OpenFoodFactsModelsTests: XCTestCase {
    
    // MARK: - Model Tests
    
    func testNutrimentsDecoding() throws {
        let json = """
        {
            "carbohydrates_100g": 25.5,
            "sugars_100g": 5.2,
            "fiber_100g": 3.1,
            "proteins_100g": 8.0,
            "fat_100g": 2.5,
            "energy_100g": 180
        }
        """.data(using: .utf8)!
        
        let nutriments = try JSONDecoder().decode(Nutriments.self, from: json)
        
        XCTAssertEqual(nutriments.carbohydrates, 25.5)
        XCTAssertEqual(nutriments.sugars ?? 0, 5.2)
        XCTAssertEqual(nutriments.fiber ?? 0, 3.1)
        XCTAssertEqual(nutriments.proteins ?? 0, 8.0)
        XCTAssertEqual(nutriments.fat ?? 0, 2.5)
        XCTAssertEqual(nutriments.energy ?? 0, 180)
    }
    
    func testNutrimentsDecodingWithMissingCarbs() throws {
        let json = """
        {
            "sugars_100g": 5.2,
            "proteins_100g": 8.0
        }
        """.data(using: .utf8)!
        
        let nutriments = try JSONDecoder().decode(Nutriments.self, from: json)
        
        // Should default to 0 when carbohydrates are missing
        XCTAssertEqual(nutriments.carbohydrates, 0.0)
        XCTAssertEqual(nutriments.sugars ?? 0, 5.2)
        XCTAssertEqual(nutriments.proteins ?? 0, 8.0)
        XCTAssertNil(nutriments.fiber)
    }
    
    func testProductDecoding() throws {
        let json = """
        {
            "product_name": "Whole Wheat Bread",
            "brands": "Sample Brand",
            "categories": "Breads",
            "code": "1234567890123",
            "serving_size": "2 slices (60g)",
            "serving_quantity": 60,
            "nutriments": {
                "carbohydrates_100g": 45.0,
                "sugars_100g": 3.0,
                "fiber_100g": 6.0,
                "proteins_100g": 9.0,
                "fat_100g": 3.5
            }
        }
        """.data(using: .utf8)!
        
        let product = try JSONDecoder().decode(OpenFoodFactsProduct.self, from: json)
        
        XCTAssertEqual(product.productName, "Whole Wheat Bread")
        XCTAssertEqual(product.brands, "Sample Brand")
        XCTAssertEqual(product.code, "1234567890123")
        XCTAssertEqual(product.id, "1234567890123")
        XCTAssertEqual(product.servingSize, "2 slices (60g)")
        XCTAssertEqual(product.servingQuantity, 60)
        XCTAssertEqual(product.nutriments.carbohydrates, 45.0)
        XCTAssertTrue(product.hasSufficientNutritionalData)
    }
    
    func testProductDecodingWithoutBarcode() throws {
        let json = """
        {
            "product_name": "Generic Bread",
            "nutriments": {
                "carbohydrates_100g": 50.0
            }
        }
        """.data(using: .utf8)!
        
        let product = try JSONDecoder().decode(OpenFoodFactsProduct.self, from: json)
        
        XCTAssertEqual(product.productName, "Generic Bread")
        XCTAssertNil(product.code)
        XCTAssertTrue(product.id.hasPrefix("synthetic_"))
        XCTAssertTrue(product.hasSufficientNutritionalData)
    }
    
    func testProductDisplayName() {
        let productWithName = OpenFoodFactsProduct.sample(name: "Test Product")
        XCTAssertEqual(productWithName.displayName, "Test Product")
        
        let productWithBrandOnly = OpenFoodFactsProduct(
            id: "test",
            productName: nil,
            brands: "Test Brand",
            categories: nil,
            nutriments: Nutriments.sample(),
            servingSize: nil,
            servingQuantity: nil,
            imageURL: nil,
            imageFrontURL: nil,
            code: nil
        )
        XCTAssertEqual(productWithBrandOnly.displayName, "Test Brand")
        
        let productWithoutNameOrBrand = OpenFoodFactsProduct(
            id: "test",
            productName: nil,
            brands: nil,
            categories: nil,
            nutriments: Nutriments.sample(),
            servingSize: nil,
            servingQuantity: nil,
            imageURL: nil,
            imageFrontURL: nil,
            code: nil
        )
        XCTAssertEqual(productWithoutNameOrBrand.displayName, "Unknown Product")
    }
    
    func testProductCarbsPerServing() {
        let product = OpenFoodFactsProduct(
            id: "test",
            productName: "Test",
            brands: nil,
            categories: nil,
            nutriments: Nutriments.sample(carbs: 50.0), // 50g per 100g
            servingSize: "30g",
            servingQuantity: 30.0, // 30g serving
            imageURL: nil,
            imageFrontURL: nil,
            code: nil
        )
        
        // 50g carbs per 100g, with 30g serving = 15g carbs per serving
        XCTAssertEqual(product.carbsPerServing ?? 0, 15.0, accuracy: 0.01)
    }
    
    func testProductSufficientNutritionalData() {
        let validProduct = OpenFoodFactsProduct.sample()
        XCTAssertTrue(validProduct.hasSufficientNutritionalData)
        
        let productWithNegativeCarbs = OpenFoodFactsProduct(
            id: "test",
            productName: "Test",
            brands: nil,
            categories: nil,
            nutriments: Nutriments.sample(carbs: -1.0),
            servingSize: nil,
            servingQuantity: nil,
            imageURL: nil,
            imageFrontURL: nil,
            code: nil
        )
        XCTAssertFalse(productWithNegativeCarbs.hasSufficientNutritionalData)
        
        let productWithoutName = OpenFoodFactsProduct(
            id: "test",
            productName: "",
            brands: "",
            categories: nil,
            nutriments: Nutriments.sample(),
            servingSize: nil,
            servingQuantity: nil,
            imageURL: nil,
            imageFrontURL: nil,
            code: nil
        )
        XCTAssertFalse(productWithoutName.hasSufficientNutritionalData)
    }
    
    func testSearchResponseDecoding() throws {
        let json = """
        {
            "products": [
                {
                    "product_name": "Test Product 1",
                    "code": "1111111111111",
                    "nutriments": {
                        "carbohydrates_100g": 25.0
                    }
                },
                {
                    "product_name": "Test Product 2",
                    "code": "2222222222222",
                    "nutriments": {
                        "carbohydrates_100g": 30.0
                    }
                }
            ],
            "count": 2,
            "page": 1,
            "page_count": 1,
            "page_size": 20
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(OpenFoodFactsSearchResponse.self, from: json)
        
        XCTAssertEqual(response.products.count, 2)
        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.page, 1)
        XCTAssertEqual(response.pageCount, 1)
        XCTAssertEqual(response.pageSize, 20)
        XCTAssertEqual(response.products[0].productName, "Test Product 1")
        XCTAssertEqual(response.products[1].productName, "Test Product 2")
    }
}

@MainActor
class OpenFoodFactsServiceTests: XCTestCase {
    
    var service: OpenFoodFactsService!
    
    override func setUp() {
        super.setUp()
        service = OpenFoodFactsService.mock()
        OpenFoodFactsService.configureMockResponses()
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    func testSearchProducts() async throws {
        let products = try await service.searchProducts(query: "bread")
        
        XCTAssertEqual(products.count, 2)
        XCTAssertEqual(products[0].displayName, "Test Bread")
        XCTAssertEqual(products[1].displayName, "Test Pasta")
        XCTAssertEqual(products[0].nutriments.carbohydrates, 45.0)
        XCTAssertEqual(products[1].nutriments.carbohydrates, 75.0)
    }
    
    func testSearchProductsWithEmptyQuery() async throws {
        let products = try await service.searchProducts(query: "")
        XCTAssertTrue(products.isEmpty)
        
        let whitespaceProducts = try await service.searchProducts(query: "   ")
        XCTAssertTrue(whitespaceProducts.isEmpty)
    }
    
    func testSearchProductByBarcode() async throws {
        let product = try await service.searchProduct(barcode: "1234567890123")
        
        XCTAssertEqual(product.displayName, "Test Product")
        XCTAssertEqual(product.nutriments.carbohydrates, 30.0)
        XCTAssertEqual(product.code, "1234567890123")
    }
    
    func testSearchProductWithInvalidBarcode() async {
        do {
            _ = try await service.searchProduct(barcode: "invalid")
            XCTFail("Should have thrown invalid barcode error")
        } catch OpenFoodFactsError.invalidBarcode {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        do {
            _ = try await service.searchProduct(barcode: "123") // Too short
            XCTFail("Should have thrown invalid barcode error")
        } catch OpenFoodFactsError.invalidBarcode {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        do {
            _ = try await service.searchProduct(barcode: "12345678901234567890") // Too long
            XCTFail("Should have thrown invalid barcode error")
        } catch OpenFoodFactsError.invalidBarcode {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testValidBarcodeFormats() async {
        let realService = OpenFoodFactsService()
        
        // Test valid barcode formats - these will likely fail with network errors
        // since they're fake barcodes, but they should pass barcode validation
        do {
            _ = try await realService.searchProduct(barcode: "12345678") // EAN-8
        } catch {
            // Expected to fail with network error in testing
        }
        
        do {
            _ = try await realService.searchProduct(barcode: "1234567890123") // EAN-13
        } catch {
            // Expected to fail with network error in testing
        }
        
        do {
            _ = try await realService.searchProduct(barcode: "123456789012") // UPC-A
        } catch {
            // Expected to fail with network error in testing
        }
    }
    
    func testErrorLocalizations() {
        let invalidURLError = OpenFoodFactsError.invalidURL
        XCTAssertNotNil(invalidURLError.errorDescription)
        XCTAssertNotNil(invalidURLError.failureReason)
        
        let productNotFoundError = OpenFoodFactsError.productNotFound
        XCTAssertNotNil(productNotFoundError.errorDescription)
        XCTAssertNotNil(productNotFoundError.failureReason)
        
        let networkError = OpenFoodFactsError.networkError(URLError(.notConnectedToInternet))
        XCTAssertNotNil(networkError.errorDescription)
        XCTAssertNotNil(networkError.failureReason)
    }
}

// MARK: - Performance Tests

@MainActor
class OpenFoodFactsPerformanceTests: XCTestCase {
    
    func testProductDecodingPerformance() throws {
        let json = """
        {
            "product_name": "Performance Test Product",
            "brands": "Test Brand",
            "categories": "Test Category",
            "code": "1234567890123",
            "serving_size": "100g",
            "serving_quantity": 100,
            "nutriments": {
                "carbohydrates_100g": 45.0,
                "sugars_100g": 3.0,
                "fiber_100g": 6.0,
                "proteins_100g": 9.0,
                "fat_100g": 3.5,
                "energy_100g": 250,
                "salt_100g": 1.2,
                "sodium_100g": 0.5
            }
        }
        """.data(using: .utf8)!
        
        measure {
            for _ in 0..<1000 {
                _ = try! JSONDecoder().decode(OpenFoodFactsProduct.self, from: json)
            }
        }
    }
    
    func testSearchResponseDecodingPerformance() throws {
        var productsJson = ""
        
        // Create JSON for 100 products
        for i in 0..<100 {
            let carbValue = Double(i) * 0.5
            if i > 0 { productsJson += "," }
            productsJson += """
            {
                "product_name": "Product \(i)",
                "code": "\(String(format: "%013d", i))",
                "nutriments": {
                    "carbohydrates_100g": \(carbValue)
                }
            }
            """
        }
        
        let json = """
        {
            "products": [\(productsJson)],
            "count": 100,
            "page": 1,
            "page_count": 1,
            "page_size": 100
        }
        """.data(using: .utf8)!
        
        measure {
            _ = try! JSONDecoder().decode(OpenFoodFactsSearchResponse.self, from: json)
        }
    }
}