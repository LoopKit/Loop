//
//  Dictionary.swift
//  Loop
//
//  Created by Michael Pangburn on 7/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

extension Dictionary {
    func compactMapValuesWithKeys<NewValue>(_ transform: (Element) throws -> NewValue?) rethrows -> [Key: NewValue] {
        try reduce(into: [:]) { result, element in
            if let newValue = try transform(element) {
                result[element.key] = newValue
            }
        }
    }
}
