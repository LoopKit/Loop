//
//  CGM.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation


enum CGM {
    case g5(transmitterID: String?)
    case g4
    case enlite

    var appURL: URL? {
        switch self {
        case .g4:
            return URL(string: "dexcomshare://")
        case .g5:
            return URL(string: "dexcomcgm://")
        case .enlite:
            return nil
        }
    }

    func createManager() -> CGMManager? {
        switch self {
        case .enlite:
            return EnliteCGMManager()
        case .g4:
            return G4CGMManager()
        case .g5(let transmitterID):
            return G5CGMManager(transmitterID: transmitterID)
        }
    }
}


extension CGM: RawRepresentable {
    typealias RawValue = [String: Any]
    private static let version = 1

    init?(rawValue: RawValue) {
        guard
            let version = rawValue["version"] as? Int,
            version == CGM.version,
            let type = rawValue["type"] as? String
        else {
            return nil
        }

        switch CGMType(rawValue: type) {
        case .g5?:
            self = .g5(transmitterID: rawValue["transmitterID"] as? String)
        case .g4?:
            self = .g4
        case .enlite?:
            self = .enlite
        case .none:
            return nil
        }
    }

    private enum CGMType: String {
        case g5
        case g4
        case enlite
    }

    private var type: CGMType {
        switch self {
        case .g5: return .g5
        case .g4: return .g4
        case .enlite: return .enlite
        }
    }

    var rawValue: [String: Any] {
        var raw: RawValue = [
            "version": CGM.version,
            "type": type.rawValue
        ]

        if case .g5(let transmitterID) = self {
            raw["transmitterID"] = transmitterID
        }

        return raw
    }
}


extension CGM: Equatable {
    static func ==(lhs: CGM, rhs: CGM) -> Bool {
        switch (lhs, rhs) {
        case (.g4, .g4), (.enlite, .enlite):
            return true
        case (.g5(let a), .g5(let b)):
            return a == b
        default:
            return false
        }
    }
}
