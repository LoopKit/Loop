//
//  Debug.swift
//  Loop
//
//  Created by Michael Pangburn on 3/5/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

var debugEnabled: Bool {
    #if DEBUG || IOS_SIMULATOR
    return true
    #else
    return false
    #endif
}

func assertDebugOnly(file: StaticString = #file, line: UInt = #line) {
    guard debugEnabled else {
        fatalError("\(file):\(line) should never be invoked in release builds", file: file, line: line)
    }
}
