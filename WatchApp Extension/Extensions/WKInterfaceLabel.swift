//
//  WKInterfaceLabel.swift
//  WatchApp Extension
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import WatchKit

extension WKInterfaceLabel {
    func setRoundedText(_ text: String?, style: UIFont.TextStyle, traits: UIFontDescriptor.SymbolicTraits = []) {
        guard let text = text else {
            setText(nil)
            return
        }

        if let descriptor = UIFontDescriptor.rounded(style: style, traits: traits)
        {
            setAttributedText(NSAttributedString(string: text, attributes: [NSAttributedString.Key.font: UIFont(descriptor: descriptor, size: 0)]))
        } else {
            setText(text)
        }
    }

    func setLargeBoldRoundedText(_ text: String?) {
        setRoundedText(text, style: .largeTitle, traits: .traitBold)
    }
}

extension UIFontDescriptor {
    class func rounded(style: UIFont.TextStyle, traits: UIFontDescriptor.SymbolicTraits) -> UIFontDescriptor? {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        return descriptor.withDesign(.rounded)?.withSymbolicTraits(.traitBold)
    }
}
