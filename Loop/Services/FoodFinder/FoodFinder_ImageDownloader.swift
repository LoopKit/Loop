import UIKit

enum ImageDownloader {
    static func fetchThumbnail(from url: URL, maxDimension: CGFloat = 300) async -> UIImage? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            // Basic size guard (<= 2 MB)
            guard data.count <= 2_000_000 else { return nil }
            guard let image = UIImage(data: data) else { return nil }
            let size = computeTargetSize(for: image.size, maxDimension: maxDimension)
            return scale(image: image, to: size)
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

