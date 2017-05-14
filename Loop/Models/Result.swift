//
//  Result.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//


enum Result<T> {
    case success(T)
    case failure(Error)
}
