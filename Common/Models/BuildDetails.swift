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

    /// The one string that unambiguously identifies the code on a device.
    ///
    /// WHY. `CFBundleVersion` is pinned in `VersionOverride.xcconfig`, so every local build renders the
    /// SAME number and the on-wrist tag cannot detect staleness at all. TestFlight assigns its own
    /// numbers (109, 111, 112...) on a different sequence again, so "build 58" on the wrist and
    /// "build 115" in TestFlight could be the same code or six hours apart and nothing on screen says
    /// which. Two devices that must run compatible code had no way to be compared by looking at them.
    ///
    /// The superproject SHA has none of those problems: it is the same identifier on both halves when
    /// they were built together, and visibly different when they were not. `capture-build-details.sh`
    /// already wrote it; nothing read it.
    var codeIdentity: String {
        let sha = (dict["com-loopkit-Loop-commit-sha"] as? String)
            ?? (dict["com-loopkit-LoopWorkspace-git-revision"] as? String)
            ?? gitRevision
        guard let sha else { return "sha?" }
        // Build date AND time disambiguate two installs of the same commit — the case where a rebuild
        // is the only difference, which is most of them during a debugging session. The DATE is not
        // optional detail: a build left on the wrist overnight reads as plausibly current from the time
        // alone, and "is this yesterday's?" is exactly the question the tag exists to answer.
        // Source format: "Wed Aug 19 15:59:38 EDT 2026" -> "Aug19 15:59".
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

