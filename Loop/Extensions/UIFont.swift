//
//  UIFont.swift
//  Loop
//
//  Created by Michael Pangburn on 2/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit


extension UIFont {
    convenience init(
        style: UIFont.TextStyle,
        design: UIFontDescriptor.SystemDesign,
        traits: UIFontDescriptor.SymbolicTraits = []
    ) {
        var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)

        if let prettierDescriptor = descriptor.withDesign(design)?.withSymbolicTraits(traits)
        {
            descriptor = prettierDescriptor
        } else if let prettierDescriptor = descriptor.withSymbolicTraits(traits) {
            descriptor = prettierDescriptor
        }

        self.init(descriptor: descriptor, size: 0)
    }

    static func heavy(_ textStyle: UIFont.TextStyle) -> UIFont {
        let descriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: textStyle)
            .addingAttributes([
                .traits: [
                    UIFontDescriptor.TraitKey.weight: UIFont.Weight.heavy
                ]
            ])

        return UIFont(descriptor: descriptor, size: 0)
    }
}
