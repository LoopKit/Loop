//
//  LogglyService.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI


class LogglyService: ServiceAuthenticationUI {
    var credentialValues: [String?]

    var credentialFormFields: [ServiceCredential]

    let title: String = NSLocalizedString("Loggly", comment: "The title of the loggly service")

    init(customerToken: String?) {
        credentialValues = [
            customerToken
        ]

        credentialFormFields = [
            ServiceCredential(
                title: NSLocalizedString("Customer Token", comment: "The title of the Loggly customer token credential"),
                placeholder: nil,
                isSecret: false,
                keyboardType: .asciiCapable
            )
        ]

        verify { _, _ in }
    }

    var client: LogglyClient?

    var isAuthorized: Bool = true

    var customerToken: String? {
        return credentialValues[0]
    }

    func verify(_ completion: @escaping (Bool, Error?) -> Void) {
        guard let customerToken = customerToken else {
            isAuthorized = false
            completion(false, nil)
            return
        }

        isAuthorized = true
        client = LogglyClient(customerToken: customerToken)
        completion(true, nil)
    }

    func reset() {
        isAuthorized = false
        client = nil
    }
}


private let LogglyURLSessionConfiguration = "LogglyURLSessionConfiguration"
private let LogglyCustomerTokenService = "LogglyCustomerToken"


extension KeychainManager {
    func setLogglyCustomerToken(_ token: String?) throws {
        try replaceGenericPassword(token, forService: LogglyCustomerTokenService)
    }

    func getLogglyCustomerToken() -> String? {
        return try? getGenericPasswordForService(LogglyCustomerTokenService)
    }
}


enum LogglyAPIEndpoint: String {
    case inputs

    private var base: String {
        return "https://logs-01.loggly.com/\(rawValue)/"
    }

    func url(token: String, tags: [String]) -> URL {
        let tags = tags.count > 0 ? tags : ["http"]
        return URL(string: "\(base)\(token)/tag/\(tags.joined(separator: ","))/")!
    }
}


extension URLSession {
    fileprivate static func logglySession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral

        configuration.isDiscretionary = true
        configuration.sessionSendsLaunchEvents = false
        configuration.networkServiceType = .background

        return URLSession(configuration: configuration)
    }

    private func inputTask(body: Data, contentType: String, token: String, tags: [String]) -> URLSessionUploadTask? {
        let url = LogglyAPIEndpoint.inputs.url(token: token, tags: tags)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "content-type")

        return uploadTask(with: request, from: body)
    }

    fileprivate func inputTask(body: String, token: String, tags: [String]) -> URLSessionUploadTask? {
        guard let data = body.data(using: .utf8) else {
            return nil
        }

        return inputTask(body: data, contentType: "text/plain", token: token, tags: tags)
    }

    fileprivate func inputTask(body: [String: Any], token: String, tags: [String]) -> URLSessionUploadTask? {
        do {
            let data = try JSONSerialization.data(withJSONObject: body, options: [])
            return inputTask(body: data, contentType: "application/json", token: token, tags: tags)
        } catch {
            return nil
        }
    }
}


class LogglyClient {
    let customerToken: String
    let session = URLSession.logglySession()

    init(customerToken: String) {
        self.customerToken = customerToken
    }

    func send(_ body: String, tags: [String]) {
        session.inputTask(body: body, token: customerToken, tags: tags)?.resume()
    }

    func send(_ body: [String: Any], tags: [String]) {
        session.inputTask(body: body, token: customerToken, tags: tags)?.resume()
    }
}
