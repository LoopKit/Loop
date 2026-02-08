import UIKit

/// Stores small thumbnails for Favorite Foods and returns identifiers for lookup.
/// Images are stored under Application Support/Favorites/Thumbnails as JPEG.
enum FavoriteFoodImageStore {
    private static var thumbnailsDir: URL? = {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = base.appendingPathComponent("Favorites/Thumbnails", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            #if DEBUG
            print("📂 FavoriteFoodImageStore init error: \(error)")
            #endif
            return nil
        }
    }()

    /// Save a thumbnail (JPEG) and return its identifier (filename)
    static func saveThumbnail(from image: UIImage, maxDimension: CGFloat = 300) -> String? {
        guard let dir = thumbnailsDir else { return nil }
        let size = computeTargetSize(for: image.size, maxDimension: maxDimension)
        let thumb = imageByScaling(image: image, to: size)
        guard let data = thumb.jpegData(compressionQuality: 0.8) else { return nil }
        let id = UUID().uuidString + ".jpg"
        let url = dir.appendingPathComponent(id)
        do {
            try data.write(to: url, options: .atomic)
            return id
        } catch {
            #if DEBUG
            print("💾 Failed to save favorite thumbnail: \(error)")
            #endif
            return nil
        }
    }

    /// Load thumbnail for identifier
    static func loadThumbnail(id: String) -> UIImage? {
        guard let dir = thumbnailsDir else { return nil }
        let url = dir.appendingPathComponent(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Delete thumbnail for identifier
    static func deleteThumbnail(id: String) {
        guard let dir = thumbnailsDir else { return }
        let url = dir.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: url)
    }

    private static func computeTargetSize(for size: CGSize, maxDimension: CGFloat) -> CGSize {
        guard max(size.width, size.height) > maxDimension else { return size }
        let scale = maxDimension / max(size.width, size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func imageByScaling(image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

