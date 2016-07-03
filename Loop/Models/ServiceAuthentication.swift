//
//  ServiceAuthentication.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//


// Defines the authentication for a service
protocol ServiceAuthentication {
    // The title of the service
    var title: String { get }

    // The credentials (e.g. username, password) used to authenticate
    var credentials: [ServiceCredential] { get set }

    // Whether the current credential values are valid authorization
    var isAuthorized: Bool { get }

    // Tests the credentials for valid authorization
    mutating func verify(completion: (success: Bool, error: ErrorType?) -> Void)

    // Clears the credential values and authorization status
    mutating func reset()
}
