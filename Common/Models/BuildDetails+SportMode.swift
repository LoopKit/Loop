//
//  BuildDetails+SportMode.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  Sport Mode's build identity, shown on both devices and sent with a loan request.
//

import Foundation

extension BuildDetails {
    /// The workspace commit plus build date and time: the same on phone and watch when built
    /// together. CFBundleVersion is pinned, so it cannot tell builds apart.
    var codeIdentity: String {
        let sha = (dict["com-loopkit-Loop-commit-sha"] as? String)
            ?? (dict["com-loopkit-LoopWorkspace-git-revision"] as? String)
            ?? gitRevision
        guard let sha else { return "sha?" }
        // "Wed Aug 19 15:59:38 EDT 2026" -> "Aug19 15:59".
        let parts = (dict["com-loopkit-Loop-build-date"] as? String)?
            .split(separator: " ").map(String.init) ?? []
        let stamp = parts.count >= 4 ? " \(parts[1])\(parts[2]) \(parts[3].prefix(5))" : ""
        return sha + stamp
    }
}
