//
//  OpenFoodFactsService.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code for OpenFoodFacts Integration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log

/// Service for interacting with the OpenFoodFacts API
/// Provides food search functionality and barcode lookup for carb counting
class OpenFoodFactsService {
    
    // MARK: - Properties
    
    private let session: URLSession
    private let baseURL = "https://world.openfoodfacts.net"
    private let userAgent = "Loop-iOS-Diabetes-App/1.0"
    private let log = OSLog(category: "OpenFoodFactsService")
    
    // MARK: - Initialization
    
    /// Initialize the service
    /// - Parameter session: URLSession to use for network requests (defaults to optimized configuration)
    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            // Create optimized configuration for food database requests
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.timeoutIntervalForResource = 60.0
            config.waitsForConnectivity = true
            config.networkServiceType = .default
            config.allowsCellularAccess = true
            config.httpMaximumConnectionsPerHost = 4
            self.session = URLSession(configuration: config)
        }
    }
    
    // MARK: - Public API
    
    /// Search for food products by name
    /// - Parameters:
    ///   - query: The search query string
    ///   - pageSize: Number of results to return (max 100, default 20)
    /// - Returns: Array of OpenFoodFactsProduct objects matching the search
    /// - Throws: OpenFoodFactsError for various failure cases
    func searchProducts(query: String, pageSize: Int = 20) async throws -> [OpenFoodFactsProduct] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            os_log("Empty search query provided", log: log, type: .info)
            return []
        }
        
        guard let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            os_log("Failed to encode search query: %{public}@", log: log, type: .error, trimmedQuery)
            throw OpenFoodFactsError.invalidURL
        }
        
        let clampedPageSize = min(max(pageSize, 1), 100)
        let urlString = "\(baseURL)/cgi/search.pl?search_terms=\(encodedQuery)&search_simple=1&action=process&json=1&page_size=\(clampedPageSize)"
        
        guard let url = URL(string: urlString) else {
            os_log("Failed to create URL from string: %{public}@", log: log, type: .error, urlString)
            throw OpenFoodFactsError.invalidURL
        }
        
        os_log("Searching OpenFoodFacts for: %{public}@", log: log, type: .info, trimmedQuery)
        
        let request = createRequest(for: url)
        let response = try await performRequest(request)
        let searchResponse = try decodeResponse(OpenFoodFactsSearchResponse.self, from: response.data)
        
        let validProducts = searchResponse.products.filter { product in
            product.hasSufficientNutritionalData
        }
        
        os_log("Found %d valid products (of %d total)", log: log, type: .info, validProducts.count, searchResponse.products.count)
        
        return validProducts
    }
    
    /// Search for a specific product by barcode
    /// - Parameter barcode: The product barcode (EAN-13, EAN-8, UPC-A, etc.)
    /// - Returns: OpenFoodFactsProduct object for the barcode
    /// - Throws: OpenFoodFactsError for various failure cases
    func searchProduct(barcode: String) async throws -> OpenFoodFactsProduct {
        let cleanBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBarcode.isEmpty else {
            throw OpenFoodFactsError.invalidBarcode
        }
        
        guard isValidBarcode(cleanBarcode) else {
            os_log("Invalid barcode format: %{public}@", log: log, type: .error, cleanBarcode)
            throw OpenFoodFactsError.invalidBarcode
        }
        
        let urlString = "\(baseURL)/api/v2/product/\(cleanBarcode).json"
        
        guard let url = URL(string: urlString) else {
            os_log("Failed to create URL for barcode: %{public}@", log: log, type: .error, cleanBarcode)
            throw OpenFoodFactsError.invalidURL
        }
        
        os_log("Looking up product by barcode: %{public}@ at URL: %{public}@", log: log, type: .info, cleanBarcode, urlString)
        
        let request = createRequest(for: url)
        os_log("Starting barcode request with timeout: %.1f seconds", log: log, type: .info, request.timeoutInterval)
        let response = try await performRequest(request)
        let productResponse = try decodeResponse(OpenFoodFactsProductResponse.self, from: response.data)
        
        guard let product = productResponse.product else {
            os_log("Product not found for barcode: %{public}@", log: log, type: .info, cleanBarcode)
            throw OpenFoodFactsError.productNotFound
        }
        
        guard product.hasSufficientNutritionalData else {
            os_log("Product found but lacks sufficient nutritional data: %{public}@", log: log, type: .info, cleanBarcode)
            throw OpenFoodFactsError.productNotFound
        }
        
        os_log("Successfully found product: %{public}@", log: log, type: .info, product.displayName)
        
        return product
    }
    
    /// Fetch a specific product by barcode (alias for searchProduct)
    /// - Parameter barcode: The product barcode to look up
    /// - Returns: OpenFoodFactsProduct if found, nil if not found
    /// - Throws: OpenFoodFactsError for various failure cases
    func fetchProduct(barcode: String) async throws -> OpenFoodFactsProduct? {
        do {
            let product = try await searchProduct(barcode: barcode)
            return product
        } catch OpenFoodFactsError.productNotFound {
            return nil
        } catch {
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    private func createRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 30.0  // Increased from 10 to 30 seconds
        return request
    }
    
    private func performRequest(_ request: URLRequest, retryCount: Int = 0) async throws -> (data: Data, response: HTTPURLResponse) {
        let maxRetries = 2
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                os_log("Invalid response type received", log: log, type: .error)
                throw OpenFoodFactsError.networkError(URLError(.badServerResponse))
            }
            
            switch httpResponse.statusCode {
            case 200:
                return (data, httpResponse)
            case 404:
                throw OpenFoodFactsError.productNotFound
            case 429:
                os_log("Rate limit exceeded", log: log, type: .error)
                throw OpenFoodFactsError.rateLimitExceeded
            case 500...599:
                os_log("Server error: %d", log: log, type: .error, httpResponse.statusCode)
                
                // Retry server errors
                if retryCount < maxRetries {
                    os_log("Retrying request due to server error (attempt %d/%d)", log: log, type: .info, retryCount + 1, maxRetries)
                    try await Task.sleep(nanoseconds: UInt64((retryCount + 1) * 1_000_000_000)) // 1s, 2s delay
                    return try await performRequest(request, retryCount: retryCount + 1)
                }
                
                throw OpenFoodFactsError.serverError(httpResponse.statusCode)
            default:
                os_log("Unexpected HTTP status: %d", log: log, type: .error, httpResponse.statusCode)
                throw OpenFoodFactsError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
            }
            
        } catch let urlError as URLError {
            // Retry timeout and connection errors
            if (urlError.code == .timedOut || urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost) && retryCount < maxRetries {
                os_log("Network error (attempt %d/%d): %{public}@, retrying...", log: log, type: .info, retryCount + 1, maxRetries, urlError.localizedDescription)
                try await Task.sleep(nanoseconds: UInt64((retryCount + 1) * 2_000_000_000)) // 2s, 4s delay
                return try await performRequest(request, retryCount: retryCount + 1)
            }
            
            os_log("Network error: %{public}@", log: log, type: .error, urlError.localizedDescription)
            throw OpenFoodFactsError.networkError(urlError)
        } catch let openFoodFactsError as OpenFoodFactsError {
            throw openFoodFactsError
        } catch {
            os_log("Unexpected error: %{public}@", log: log, type: .error, error.localizedDescription)
            throw OpenFoodFactsError.networkError(error)
        }
    }
    
    private func decodeResponse<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch let decodingError as DecodingError {
            os_log("JSON decoding failed: %{public}@", log: log, type: .error, decodingError.localizedDescription)
            throw OpenFoodFactsError.decodingError(decodingError)
        } catch {
            os_log("Decoding error: %{public}@", log: log, type: .error, error.localizedDescription)
            throw OpenFoodFactsError.decodingError(error)
        }
    }
    
    private func isValidBarcode(_ barcode: String) -> Bool {
        // Basic barcode validation
        // Should be numeric and between 8-14 digits (covers EAN-8, EAN-13, UPC-A, etc.)
        let numericPattern = "^[0-9]{8,14}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", numericPattern)
        return predicate.evaluate(with: barcode)
    }
}

// MARK: - Testing Support

#if DEBUG
extension OpenFoodFactsService {
    /// Create a mock service for testing that returns sample data
    static func mock() -> OpenFoodFactsService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return OpenFoodFactsService(session: session)
    }
    
    /// Configure mock responses for testing
    static func configureMockResponses() {
        MockURLProtocol.mockResponses = [
            "search": MockURLProtocol.createSearchResponse(),
            "product": MockURLProtocol.createProductResponse()
        ]
    }
}

/// Mock URL protocol for testing
class MockURLProtocol: URLProtocol {
    static var mockResponses: [String: (Data, HTTPURLResponse)] = [:]
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let url = request.url else { return }
        
        let key = url.path.contains("search") ? "search" : "product"
        
        if let (data, response) = MockURLProtocol.mockResponses[key] {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
    
    static func createSearchResponse() -> (Data, HTTPURLResponse) {
        let response = OpenFoodFactsSearchResponse(
            products: [
                OpenFoodFactsProduct.sample(name: "Test Bread", carbs: 45.0),
                OpenFoodFactsProduct.sample(name: "Test Pasta", carbs: 75.0)
            ],
            count: 2,
            page: 1,
            pageCount: 1,
            pageSize: 20
        )
        
        let data = try! JSONEncoder().encode(response)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://world.openfoodfacts.org/cgi/search.pl")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        
        return (data, httpResponse)
    }
    
    static func createProductResponse() -> (Data, HTTPURLResponse) {
        let response = OpenFoodFactsProductResponse(
            code: "1234567890123",
            product: OpenFoodFactsProduct.sample(name: "Test Product", carbs: 30.0),
            status: 1,
            statusVerbose: "product found"
        )
        
        let data = try! JSONEncoder().encode(response)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://world.openfoodfacts.org/api/v0/product/1234567890123.json")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        
        return (data, httpResponse)
    }
}
#endif
