import UIKit
import LoopKitUI

/// Provides small UIImage thumbnails for simple whole foods using emoji.
/// Useful when the data provider (e.g., USDA) does not supply product images.
enum EmojiThumbnailProvider {
    /// Quick keyword → emoji pairs we maintain locally (supplements the shared data source).
    private static let directMatches: [String: String] = {
        var map: [String: String] = [
            // allow simple keyword lookups not covered by data source
            "apple": "🍎",
            "banana": "🍌",
            "orange": "🍊",
            "grape": "🍇",
            "strawberry": "🍓",
            "blueberry": "🫐",
            "cherry": "🍒",
            "pear": "🍐",
            "peach": "🍑",
            "mango": "🥭",
            "pineapple": "🍍",
            "watermelon": "🍉",
            "melon": "🍈",
            "kiwi": "🥝",
            "coconut": "🥥",
            "lemon": "🍋",
            "lime": "🟢",
            "avocado": "🥑",
            "tomato": "🍅",
            "carrot": "🥕",
            "broccoli": "🥦",
            "lettuce": "🥬",
            "spinach": "🥬",
            "cucumber": "🥒",
            "pepper": "🫑",
            "chili": "🌶️",
            "corn": "🌽",
            "onion": "🧅",
            "garlic": "🧄",
            "mushroom": "🍄",
            "potato": "🥔",
            "sweet potato": "🍠",
            "rice": "🍚",
            "pasta": "🍝",
            "bread": "🍞",
            "bagel": "🥯",
            "oat": "🥣",
            "tortilla": "🫓"
        ]
        return map
    }()

    /// Returns the mapped emoji for a simple food name, if recognized.
    static func emoji(for name: String) -> String? {
        let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if let builtin = directMatches.first(where: { cleaned.contains($0.key) })?.value {
            return builtin
        }

        if let mapped = FoodEmojiKeywordLibrary.keywordEmojiMap.first(where: { cleaned.contains($0.key) })?.value {
            return mapped
        }

        return nil
    }

    /// Return a rendered emoji thumbnail if the name matches a known simple food.
    static func image(for name: String, size: CGFloat = 50) -> UIImage? {
        guard let e = emoji(for: name) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            UIColor.systemGray6.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerRadius: 8).fill()
            let attr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.56)
            ]
            let t = (e as NSString)
            let textSize = t.size(withAttributes: attr)
            let rect = CGRect(x: (size - textSize.width)/2, y: (size - textSize.height)/2, width: textSize.width, height: textSize.height)
            t.draw(in: rect, withAttributes: attr)
        }
    }
}
