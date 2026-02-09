//
//  FoodFinder_ImageDownloader.swift
//  Loop
//
//  FoodFinder — Async image downloader with caching for product thumbnails.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import UIKit

enum ImageDownloader {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 50
        cache.totalCostLimit = 10 * 1024 * 1024 // 10 MB
        return cache
    }()

    static func fetchThumbnail(from url: URL, maxDimension: CGFloat = 300) async -> UIImage? {
        let cacheKey = url.absoluteString as NSString

        // Return cached image if available
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            // Basic size guard (<= 2 MB)
            guard data.count <= 2_000_000 else { return nil }
            guard let image = UIImage(data: data) else { return nil }
            let size = computeTargetSize(for: image.size, maxDimension: maxDimension)
            let scaled = scale(image: image, to: size)
            cache.setObject(scaled, forKey: cacheKey)
            return scaled
        } catch {
            #if DEBUG
            print("🌐 Image download failed: \(error)")
            #endif
            return nil
        }
    }

    private static func computeTargetSize(for size: CGSize, maxDimension: CGFloat) -> CGSize {
        guard max(size.width, size.height) > maxDimension else { return size }
        let scale = maxDimension / max(size.width, size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func scale(image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
