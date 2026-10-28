//
//  LoanPushSender.swift
//  WatchApp Extension
//
//  Sends a loan message to the phone by Apple push, over the watch's own internet, signed with the
//  user's key that came in the standing copy. One attempt: the phone's take-back covers a lost push.
//

import Foundation
import CryptoKit
import LoopCore

enum LoanPushSender {
    enum SendError: Error {
        case unusableAddress
    }

    /// Waits a little for a network: a watch that has just left the phone may still be bringing up
    /// its own.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    static func send(_ push: LoanPush, to reach: PhoneReach) {
        let request: URLRequest
        do {
            request = try makeRequest(push, reach: reach, issuedAt: Date())
        } catch {
            SportLog.event("push", "not sent to the phone: \(error)")
            return
        }
        session.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            SportLog.event("push", status == 200 ? "sent to the phone"
                           : "not delivered to the phone: \(status.map { "HTTP \($0)" } ?? error?.localizedDescription ?? "no answer")")
        }.resume()
    }

    static func makeRequest(_ push: LoanPush, reach: PhoneReach, issuedAt: Date) throws -> URLRequest {
        let host = reach.production ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        guard !reach.deviceToken.isEmpty, reach.deviceToken.allSatisfy(\.isHexDigit),
              let url = URL(string: "https://\(host)/3/device/\(reach.deviceToken)") else { throw SendError.unusableAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: push.apnsPayload())
        request.setValue("bearer \(try providerToken(reach: reach, issuedAt: issuedAt))", forHTTPHeaderField: "authorization")
        request.setValue(reach.topic, forHTTPHeaderField: "apns-topic")
        request.setValue("background", forHTTPHeaderField: "apns-push-type")
        // Apple requires the low priority for a silent push.
        request.setValue("5", forHTTPHeaderField: "apns-priority")
        request.setValue(String(Int(push.sentAt.addingTimeInterval(LoanPush.maxAge).timeIntervalSince1970)), forHTTPHeaderField: "apns-expiration")
        return request
    }

    /// Apple's provider token: a JWT naming the key and the team, signed with the key (ES256).
    static func providerToken(reach: PhoneReach, issuedAt: Date) throws -> String {
        let key = try P256.Signing.PrivateKey(pemRepresentation: reach.key)
        let header = base64URL(try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": reach.keyID], options: .sortedKeys))
        let claims = base64URL(try JSONSerialization.data(withJSONObject: ["iss": reach.teamID, "iat": Int(issuedAt.timeIntervalSince1970)], options: .sortedKeys))
        let signature = try key.signature(for: Data("\(header).\(claims)".utf8))
        return "\(header).\(claims).\(base64URL(signature.rawRepresentation))"
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
