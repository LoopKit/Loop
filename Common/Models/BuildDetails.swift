//
//  BuildDetails.swift
//  Loop
//
//  Created by Pete Schwamb on 6/13/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

class BuildDetails {

    static var `default` = BuildDetails()

    let dict: [String: Any]

    init() {
        guard let url = Bundle.main.url(forResource: "BuildDetails", withExtension: ".plist"),
              let data = try? Data(contentsOf: url),
              let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else
        {
            dict = [:]
            return
        }
        dict = parsed
    }

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

    var buildDateString: String? {
        return dict["com-loopkit-Loop-build-date"] as? String
    }

    var xcodeVersion: String? {
        return dict["com-loopkit-Loop-xcode-version"] as? String
    }

    var gitRevision: String? {
        return dict["com-loopkit-Loop-git-revision"] as? String
    }

    var gitBranch: String? {
        return dict["com-loopkit-Loop-git-branch"] as? String
    }

    var sourceRoot: String? {
        return dict["com-loopkit-Loop-srcroot"] as? String
    }

    var profileExpiration: Date? {
        return dict["com-loopkit-Loop-profile-expiration"] as? Date
    }

    var profileExpirationString: String {
        if let profileExpiration = profileExpiration {
            return "\(profileExpiration)"
        } else {
            return "N/A"
        }
    }

    // These strings are only configured if it is a workspace build
    var workspaceGitRevision: String? {
        return dict["com-loopkit-LoopWorkspace-git-revision"] as? String
    }

    var workspaceGitBranch: String? {
        return dict["com-loopkit-LoopWorkspace-git-branch"] as? String
    }

    /// Returns a dictionary of submodule details.
    /// The keys are the submodule names, and the values are tuples (branch, commitSHA).
    var submodules: [String: (branch: String, commitSHA: String)] {
        guard let subs = dict["com-loopkit-Loop-submodules"] as? [String: [String: Any]] else {
            return [:]
        }
        var result = [String: (branch: String, commitSHA: String)]()
        for (name, info) in subs {
            let branch = info["branch"] as? String ?? String(localized: "Unknown")
            let commitSHA = info["commit_sha"] as? String ?? String(localized: "Unknown")
            result[name] = (branch: branch, commitSHA: commitSHA)
        }
        return result
    }
}

