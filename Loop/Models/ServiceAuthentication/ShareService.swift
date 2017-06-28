//
//  ShareService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import ShareClient


// Encapsulates the Dexcom Share client service and its authentication
class ShareService: ServiceAuthentication {
    var credentials: [ServiceCredential]

    let title: String = NSLocalizedString("Dexcom Share", comment: "The title of the Dexcom Share service")

    init(username: String?, password: String?, url: URL?) {
        credentials = [
            ServiceCredential(
                title: NSLocalizedString("Username", comment: "The title of the Dexcom share username credential"),
                isSecret: false,
                keyboardType: .asciiCapable,
                value: username
            ),
            ServiceCredential(
                title: NSLocalizedString("Password", comment: "The title of the Dexcom share password credential"),
                isSecret: true,
                keyboardType: .asciiCapable,
                value: password
            ),
            ServiceCredential(
                title: NSLocalizedString("Server", comment: "The title of the Dexcom share server URL credential"),
                isSecret: false,
                value: url?.absoluteString,
                options: [
                    (title: NSLocalizedString("US", comment: "U.S. share server option title"),
                     value: DexcomShareURL.absoluteString)
                ]
            )
        ]

        if let username = username, let password = password, url != nil {
            isAuthorized = true
            client = ShareClient(username: username, password: password)
        }
    }

    // The share client, if credentials are present
    private(set) var client: ShareClient?

    var username: String? {
        return credentials[0].value
    }

    var password: String? {
        return credentials[1].value
    }

    var url: URL? {
        guard let urlString = credentials[2].value else {
            return nil
        }

        return URL(string: urlString)
    }

    var isAuthorized: Bool = false

    func verify(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        guard let username = username, let password = password, url != nil else {
            completion(false, nil)
            return
        }

        let client = ShareClient(username: username, password: password)
        client.fetchLast(1) { (error, _) in
            completion(true, error)
        }
        self.client = client
    }

    func reset() {
        credentials[0].value = nil
        credentials[1].value = nil
        credentials[2].value = nil
        isAuthorized = false
        client = nil
    }
}


private let DexcomShareURL = URL(string: "https://share1.dexcom.com")!
private let DexcomShareServiceLabel = "DexcomShare1"


extension KeychainManager {
    func setDexcomShareUsername(_ username: String?, password: String?, url: URL?) throws {
        let credentials: InternetCredentials?

        if let username = username, let password = password, let url = url {
            credentials = InternetCredentials(username: username, password: password, url: url)
        } else {
            credentials = nil
        }

        // Replace the legacy URL-keyed credentials
        try replaceInternetCredentials(nil, forURL: DexcomShareURL)

        try replaceInternetCredentials(credentials, forLabel: DexcomShareServiceLabel)
    }

    func getDexcomShareCredentials() -> (username: String, password: String, url: URL)? {
        do { // Silence all errors and return nil
            do {
                let credentials = try getInternetCredentials(label: DexcomShareServiceLabel)

                return (username: credentials.username, password: credentials.password, url: credentials.url)
            } catch KeychainManagerError.copy {
                // Fetch and replace the legacy URL-keyed credentials
                let credentials = try getInternetCredentials(url: DexcomShareURL)

                try setDexcomShareUsername(credentials.username, password: credentials.password, url: credentials.url)

                return (username: credentials.username, password: credentials.password, url: credentials.url)
            }
        } catch {
            return nil
        }
    }
}
