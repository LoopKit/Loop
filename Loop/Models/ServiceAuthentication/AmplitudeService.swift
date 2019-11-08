//
//  AmplitudeService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import Amplitude
import LoopKit
import LoopKitUI


class AmplitudeService: ServiceAuthenticationUI {
    var credentialValues: [String?]

    var credentialFormFields: [ServiceCredential]

    let title: String = NSLocalizedString("Amplitude", comment: "The title of the Amplitude service")

    init(APIKey: String?) {
        credentialValues = [
            APIKey
        ]

        credentialFormFields = [
            ServiceCredential(
                title: NSLocalizedString("API Key", comment: "The title of the amplitude API key credential"),
                placeholder: nil,
                isSecret: false,
                keyboardType: .asciiCapable
            )
        ]

        verify { _, _ in }
    }

    var client: Amplitude?

    var APIKey: String? {
        return credentialValues[0]
    }

    var isAuthorized: Bool = true

    func verify(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        guard let APIKey = APIKey else {
            isAuthorized = false
            completion(false, nil)
            return
        }

        isAuthorized = true
        let client = Amplitude()
        client.disableIdfaTracking()
        client.disableLocationListening()
        client.initializeApiKey(APIKey)
        self.client = client
        completion(true, nil)
    }

    func reset() {
        isAuthorized = false
        client = nil
    }
}


private let AmplitudeAPIKeyService = "AmplitudeAPIKey"


extension KeychainManager {
    func setAmplitudeAPIKey(_ key: String?) throws {
        try replaceGenericPassword(key, forService: AmplitudeAPIKeyService)
    }

    func getAmplitudeAPIKey() -> String? {
        return try? getGenericPasswordForService(AmplitudeAPIKeyService)
    }
}
