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

    init(siteURL: URL?, APISecret: String?) {
        credentials = [
            ServiceCredential(
                title: NSLocalizedString("Site URL", comment: "The title of the nightscout site URL credential"),
                placeholder: NSLocalizedString("https://mysite.azurewebsites.net", comment: "The placeholder text for the nightscout site URL credential"),
                isSecret: false,
                keyboardType: .URL,
                value: siteURL?.absoluteString
            ),
            ServiceCredential(
                title: NSLocalizedString("API Secret", comment: "The title of the nightscout API secret credential"),
                placeholder: nil,
                isSecret: false,
                keyboardType: .asciiCapable,
                value: APISecret
            )
        ]

        verify { _, _ in }
    }

    // The uploader instance, if credentials are present
    private(set) var uploader: NightscoutUploader? {
        didSet {
            uploader?.errorHandler = { (error: Error, context: String) -> Void in
                print("Error \(error), while \(context)")
            }
        }
    }

    var siteURL: URL? {
        if let URLString = credentials[0].value, !URLString.isEmpty {
            return URL(string: URLString)
        }

        return nil
    }

    var APISecret: String? {
        return credentials[1].value
    }

    var isAuthorized: Bool = true

    mutating func verify(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        guard let siteURL = siteURL, let APISecret = APISecret else {
            isAuthorized = false
            completion(false, nil)
            return
        }

        let uploader = NightscoutUploader(siteURL: siteURL, APISecret: APISecret)
        uploader.checkAuth { (error) in
            completion(true, error)
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
