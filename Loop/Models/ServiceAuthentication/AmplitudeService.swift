//
//  AmplitudeService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import Amplitude


struct AmplitudeService: ServiceAuthentication {
    var credentials: [ServiceCredential]

    let title: String = NSLocalizedString("Amplitude", comment: "The title of the Amplitude service")

    init(APIKey: String?) {
        credentials = [
            ServiceCredential(
                title: NSLocalizedString("API Key", comment: "The title of the amplitude API key credential"),
                placeholder: nil,
                isSecret: false,
                keyboardType: .asciiCapable,
                value: APIKey
            )
        ]

        verify { _, _ in }
    }

    var client: Amplitude?

    var APIKey: String? {
        return credentials[0].value
    }

    var isAuthorized: Bool = true

    mutating func verify(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        guard let APIKey = APIKey else {
            isAuthorized = false
            completion(false, nil)
            return
        }

        isAuthorized = true
        let client = Amplitude()
        client.initializeApiKey(APIKey)
        self.client = client
        completion(true, nil)
    }

    mutating func reset() {
        credentials[0].value = nil
        isAuthorized = false
        client = nil
    }
}
