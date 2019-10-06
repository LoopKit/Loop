
import WatchKit

extension WKInterfaceLabel {
    func setRoundedText(_ text: String?, style: UIFont.TextStyle, traits: UIFontDescriptor.SymbolicTraits = []) {
        guard let text = text else {
            setText(nil)
            return
        }

        if #available(watchOSApplicationExtension 5.2, *),
            let descriptor = UIFontDescriptor.rounded(style: style, traits: traits)
        {
            setAttributedText(NSAttributedString(string: text, attributes: [NSAttributedString.Key.font: UIFont(descriptor: descriptor, size: 0)]))
        } else {
            setText(text)
        }
    }

    func setLargeBoldRoundedText(_ text: String?) {
        if #available(watchOSApplicationExtension 5.0, *) {
            setRoundedText(text, style: .largeTitle, traits: .traitBold)
        } else {
            setRoundedText(text, style: .title1, traits: .traitBold)
        }
    }
}

extension UIFontDescriptor {
    @available(watchOSApplicationExtension 5.2, *)
    class func rounded(style: UIFont.TextStyle, traits: UIFontDescriptor.SymbolicTraits) -> UIFontDescriptor? {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        return descriptor.withDesign(.rounded)?.withSymbolicTraits(.traitBold)
    }
}
