//
//  NightscoutService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutUploadKit


// Encapsulates a Nightscout site and its authentication
struct NightscoutService: ServiceAuthentication {
    var credentials: [ServiceCredential]

    let title: String = NSLocalizedString("Nightscout", comment: "The title of the Nightscout service")

    init(siteURL: NSURL?, APISecret: String?) {
        credentials = [
            ServiceCredential(
                title: NSLocalizedString("Site URL", comment: "The title of the nightscout site URL credential"),
                placeholder: NSLocalizedString("http://mysite.azurewebsites.net", comment: "The placeholder text for the nightscout site URL credential"),
                isSecret: false,
                keyboardType: .URL,
                value: siteURL?.absoluteString
            ),
            ServiceCredential(
                title: NSLocalizedString("API Secret", comment: "The title of the nightscout API secret credential"),
                placeholder: nil,
                isSecret: false,
                keyboardType: .ASCIICapable,
                value: APISecret
            )
        ]

        verify { _, _ in }
    }

    // The uploader instance, if credentials are present
    private(set) var uploader: NightscoutUploader? {
        didSet {
            uploader?.errorHandler = { (error: ErrorType, context: String) -> Void in
                print("Error \(error), while \(context)")
            }
        }
    }

    var siteURL: NSURL? {
        if let URLString = credentials[0].value where !URLString.isEmpty {
            return NSURL(string: URLString)
        }

        return nil
    }

    var APISecret: String? {
        return credentials[1].value
    }

    private(set) var isAuthorized: Bool = false

    mutating func verify(completion: (success: Bool, error: ErrorType?) -> Void) {
        guard let siteURL = siteURL, APISecret = APISecret else {
            completion(success: false, error: nil)
            return
        }

        let uploader = NightscoutUploader(siteURL: siteURL, APISecret: APISecret)
        uploader.checkAuth { (error) in
            if let error = error {
                self.isAuthorized = false
                completion(success: false, error: error)
            } else {
                self.isAuthorized = true
                completion(success: true, error: nil)
            }
        }
        self.uploader = uploader
    }

    mutating func reset() {
        credentials[0].value = nil
        credentials[1].value = nil
        isAuthorized = false
        uploader = nil
    }
}
