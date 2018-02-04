//
//  WCSession.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchConnectivity


enum MessageError: Error {
    case activationError
    case decodingError
    case reachabilityError
}


extension WCSession {
    func sendCarbEntryMessage(_ carbEntry: CarbEntryUserInfo, replyHandler: @escaping (BolusSuggestionUserInfo) -> Void, errorHandler: @escaping (Error) -> Void) throws {
        guard activationState == .activated else {
            throw MessageError.activationError
        }

        guard isReachable else {
            transferUserInfo(carbEntry.rawValue)
            return
        }

        sendMessage(carbEntry.rawValue,
            replyHandler: { reply in
                guard let suggestion = BolusSuggestionUserInfo(rawValue: reply as BolusSuggestionUserInfo.RawValue) else {
                    errorHandler(MessageError.decodingError)
                    return
                }

                replyHandler(suggestion)
            },
            errorHandler: errorHandler
        )
    }

    func sendBolusMessage(_ userInfo: SetBolusUserInfo, errorHandler: @escaping (Error) -> Void) throws {
        guard activationState == .activated else {
            throw MessageError.activationError
        }

        guard isReachable else {
            throw MessageError.reachabilityError
        }

        sendMessage(userInfo.rawValue,
            replyHandler: { reply in },
            errorHandler: errorHandler
        )
    }

    func sendGlucoseRangeScheduleOverrideMessage(_ userInfo: GlucoseRangeScheduleOverrideUserInfo?, replyHandler: @escaping ([String: Any]) -> Void, errorHandler: @escaping (Error) -> Void) throws {
        guard activationState == .activated else {
            throw MessageError.activationError
        }

        guard isReachable else {
            throw MessageError.reachabilityError
        }

        sendMessage(userInfo?.rawValue ?? GlucoseRangeScheduleOverrideUserInfo.clearOverride,
            replyHandler: replyHandler,
            errorHandler: errorHandler
        )
    }
}
