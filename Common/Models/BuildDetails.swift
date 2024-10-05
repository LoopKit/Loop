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
    private var cachedProfileExpirationDate: Date?

    init() {
        guard let url = Bundle.main.url(forResource: "BuildDetails", withExtension: ".plist"),
           let data = try? Data(contentsOf: url),
           let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else
        {
            dict = [:]
            return
        }
        dict = parsed
        cachedProfileExpirationDate = loadProfileExpirationDate()
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
        return cachedProfileExpirationDate
    }

    var profileExpirationString: String {
        if let profileExpiration = cachedProfileExpirationDate {
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

    private func loadProfileExpirationDate() -> Date? {
        guard
            let profilePath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
            let profileData = try? Data(contentsOf: URL(fileURLWithPath: profilePath)),
            let profileNSString = NSString(data: profileData, encoding: String.Encoding.ascii.rawValue)
        else {
            print(
                "WARNING: Could not find or read `embedded.mobileprovision`. If running on Simulator, there are no provisioning profiles."
            )
            return nil
        }

        let regexPattern = "<key>ExpirationDate</key>[\\W]*?<date>(.*?)</date>"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []),
              let match = regex.firstMatch(
                in: profileNSString as String,
                options: [],
                range: NSRange(location: 0, length: profileNSString.length)
              ),
              let range = Range(match.range(at: 1), in: profileNSString as String)
        else {
            print("Warning: Could not create regex or find match.")
            return nil
        }

        let dateString = String(profileNSString.substring(with: NSRange(range, in: profileNSString as String)))
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        return dateFormatter.date(from: dateString)
    }
}

