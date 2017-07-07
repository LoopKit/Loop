//
//  mLabService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


private let mLabAPIHost = URL(string: "https://api.mongolab.com/api/1/databases")!


class MLabService: ServiceAuthentication {
    var credentials: [ServiceCredential]

    let title: String = NSLocalizedString("mLab", comment: "The title of the mLab service")

    init(databaseName: String?, APIKey: String?) {
        credentials = [
            ServiceCredential(
                title: NSLocalizedString("Database", comment: "The title of the mLab database name credential"),
                placeholder: "nightscoutdb",
                isSecret: false,
                keyboardType: .asciiCapable,
                value: databaseName
            ),
            ServiceCredential(
                title: NSLocalizedString("API Key", comment: "The title of the mLab API Key credential"),
                placeholder: nil,
                isSecret: false,
                keyboardType: .asciiCapable,
                value: APIKey
            )
        ]

        if databaseName != nil && APIKey != nil {
            isAuthorized = true
        }
    }

    var databaseName: String? {
        return credentials[0].value
    }

    var APIKey: String? {
        return credentials[1].value
    }

    var isAuthorized: Bool = false

    func verify(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        guard let APIURL = APIURLForCollection("") else {
            completion(false, nil)
            return
        }

        URLSession.shared.dataTask(with: APIURL, completionHandler: { (_, response, error) in
            var error: Error? = error
            if error == nil, let response = response as? HTTPURLResponse, response.statusCode >= 300 {
                error = LoopError.connectionError
            }

            completion(true, error)
        }).resume()
    }

    func reset() {
        credentials[0].reset()
        credentials[1].reset()
        isAuthorized = false
    }

    private func APIURLForCollection(_ collection: String) -> URL? {
        guard let databaseName = databaseName, let APIKey = APIKey else {
            return nil
        }

        let APIURL = mLabAPIHost.appendingPathComponent("\(databaseName)/collections").appendingPathComponent(collection)
        var components = URLComponents(url: APIURL, resolvingAgainstBaseURL: true)!

        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "apiKey", value: APIKey))
        components.queryItems = items

        return components.url
    }

    func uploadTaskWithData(_ data: Data, inCollection collection: String) -> URLSessionTask? {
        guard let URL = APIURLForCollection(collection) else {
            return nil
        }

        var request = URLRequest(url: URL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return URLSession.shared.uploadTask(with: request, from: data)
    }
}


extension KeychainManager {
    func setMLabDatabaseName(_ databaseName: String?, APIKey: String?) throws {
        let credentials: InternetCredentials?

        if let username = databaseName, let password = APIKey {
            credentials = InternetCredentials(username: username, password: password, url: mLabAPIHost)
        } else {
            credentials = nil
        }

        try replaceInternetCredentials(credentials, forURL: mLabAPIHost)
    }

    func getMLabCredentials() -> (databaseName: String, APIKey: String)? {
        do {
            let credentials = try getInternetCredentials(url: mLabAPIHost)

            return (databaseName: credentials.username, APIKey: credentials.password)
        } catch {
            return nil
        }
    }
}
