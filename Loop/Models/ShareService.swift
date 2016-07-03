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
struct ShareService: ServiceAuthentication {
    var credentials: [ServiceCredential]

    let title: String = NSLocalizedString("Dexcom Share", comment: "The title of the Dexcom Share service")

    init(username: String?, password: String?) {
        credentials = [
            ServiceCredential(
                title: NSLocalizedString("Username", comment: "The title of the Dexcom share username credential"),
                isSecret: false,
                keyboardType: .ASCIICapable,
                value: username
            ),
            ServiceCredential(
                title: NSLocalizedString("Password", comment: "The title of the Dexcom share password credential"),
                isSecret: true,
                keyboardType: .ASCIICapable,
                value: password
            )
        ]

        isAuthorized = username != nil && password != nil
    }

    // The share client, if credentials are present
    var client: ShareClient?

    var username: String? {
        return credentials[0].value
    }

    var password: String? {
        return credentials[1].value
    }

    private(set) var isAuthorized: Bool

    mutating func verify(completion: (success: Bool, error: ErrorType?) -> Void) {
        guard let username = username, let password = password else {
            completion(success: false, error: nil)
            return
        }

        let client = ShareClient(username: username, password: password)
        client.fetchLast(1) { (error, _) in
            self.isAuthorized = (error == nil)

            completion(success: self.isAuthorized, error: error)
        }
        self.client = client
    }

    mutating func reset() {
        credentials[0].value = nil
        credentials[1].value = nil
        isAuthorized = false
    }
}
