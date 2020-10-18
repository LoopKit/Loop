//
//  UserDefaultsObserver.swift
//  Loop
//
//  Created by Anna Quinlan on 10/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation

class UserDefaultsObserver: NSObject {
    let key: String
    var onChange: ((Any, Any) -> Void)?

    init(key: String, onChange: ((Any, Any) -> Void)? = nil) {
        self.onChange = onChange
        self.key = key
        super.init()
        UserDefaults.appGroup?.addObserver(self, forKeyPath: key, options: [.old, .new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let change = change, object != nil, keyPath == key else { return }
        onChange?(change[.oldKey] as Any, change[.newKey] as Any)
    }

    deinit {
        UserDefaults.appGroup?.removeObserver(self, forKeyPath: key, context: nil)
    }
}
