//
//  KeychainManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import Security


/**
 
 Influenced by https://github.com/marketplacer/keychain-swift
 */
struct KeychainManager {
    typealias Query = [String: NSObject]

    var accessibility: CFString = kSecAttrAccessibleAfterFirstUnlock

    var accessGroup: String?

    enum Error: ErrorType {
        case add(OSStatus)
        case copy(OSStatus)
        case delete(OSStatus)
        case unknownResult
    }

    struct InternetCredentials {
        let username: String
        let password: String
        let URL: NSURL
    }

    // MARK: - Convenience methods

    private func queryByClass(`class`: CFString) -> Query {
        var query: Query = [kSecClass as String: `class`]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func queryForGenericPasswordByService(service: String) -> Query {
        var query = queryByClass(kSecClassGenericPassword)

        query[kSecAttrService as String] = service

        return query
    }

    private func queryForInternetPassword(account account: String? = nil, URL: NSURL? = nil) -> Query {
        var query = queryByClass(kSecClassInternetPassword)

        if let account = account {
            query[kSecAttrAccount as String] = account
        }

        if let URL = URL, components = NSURLComponents(URL: URL, resolvingAgainstBaseURL: true) {
            for (key, value) in components.keychainAttributes {
                query[key] = value
            }
        }

        return query
    }

    private func updatedQuery(query: Query, withPassword password: String) throws -> Query {
        var query = query

        guard let value = password.dataUsingEncoding(NSUTF8StringEncoding) else {
            throw Error.add(errSecDecode)
        }

        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] = accessibility

        return query
    }

    func delete(query: Query) throws {
        let statusCode = SecItemDelete(query)

        guard statusCode == errSecSuccess || statusCode == errSecItemNotFound else {
            throw Error.delete(statusCode)
        }
    }

    // MARK: – Generic Passwords

    func replaceGenericPassword(password: String?, forService service: String) throws {
        var query = queryForGenericPasswordByService(service)

        try delete(query)

        guard let password = password else {
            return
        }

        query = try updatedQuery(query, withPassword: password)

        let statusCode = SecItemAdd(query, nil)

        guard statusCode == errSecSuccess else {
            throw Error.add(statusCode)
        }
    }

    func getGenericPasswordForService(service: String) throws -> String {
        var query = queryForGenericPasswordByService(service)

        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: NSData?

        let statusCode: OSStatus = withUnsafeMutablePointer(&result) {
            SecItemCopyMatching(query, UnsafeMutablePointer($0))
        }

        guard statusCode == errSecSuccess else {
            throw Error.copy(statusCode)
        }

        guard let passwordData = result, password = String(data: passwordData, encoding: NSUTF8StringEncoding) else {
            throw Error.unknownResult
        }

        return password
    }

    // MARK – Internet Passwords

    func setInternetPassword(password: String, forAccount account: String, atURL url: NSURL) throws {
        var query = try updatedQuery(queryForInternetPassword(account: account, URL: url), withPassword: password)

        query[kSecAttrAccount as String] = account

        if let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: true) {
            for (key, value) in components.keychainAttributes {
                query[key] = value
            }
        }

        let statusCode = SecItemAdd(query, nil)

        guard statusCode == errSecSuccess else {
            throw Error.add(statusCode)
        }
    }

    func replaceInternetCredentials(credentials: InternetCredentials?, forAccount account: String) throws {
        let query = queryForInternetPassword(account: account)

        try delete(query)

        if let credentials = credentials {
            try setInternetPassword(credentials.password, forAccount: credentials.username, atURL: credentials.URL)
        }
    }

    func replaceInternetCredentials(credentials: InternetCredentials?, forURL URL: NSURL) throws {
        let query = queryForInternetPassword(URL: URL)

        try delete(query)

        if let credentials = credentials {
            try setInternetPassword(credentials.password, forAccount: credentials.username, atURL: credentials.URL)
        }
    }

    func getInternetCredentials(account account: String? = nil, URL: NSURL? = nil) throws -> InternetCredentials {
        var query = queryForInternetPassword(account: account, URL: URL)

        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecReturnAttributes as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFDictionary?

        let statusCode: OSStatus = withUnsafeMutablePointer(&result) {
            SecItemCopyMatching(query, UnsafeMutablePointer($0))
        }

        guard statusCode == errSecSuccess else {
            throw Error.copy(statusCode)
        }

        let resultDict = result as [NSObject: AnyObject]?

        if let  result = resultDict, passwordData = result[kSecValueData as String] as? NSData,
                password = String(data: passwordData, encoding: NSUTF8StringEncoding),
                URL = NSURLComponents(keychainAttributes: result)?.URL,
                username = result[kSecAttrAccount as String] as? String
        {
            return InternetCredentials(username: username, password: password, URL: URL)
        }

        throw Error.unknownResult
    }
}


private enum SecurityProtocol {
    case HTTP
    case HTTPS

    init?(scheme: String?) {
        switch scheme?.lowercaseString {
        case "http"?:
            self = .HTTP
        case "https"?:
            self = .HTTPS
        default:
            return nil
        }
    }

    init?(secAttrProtocol: CFString) {
        if secAttrProtocol == kSecAttrProtocolHTTP {
            self = .HTTP
        } else if secAttrProtocol == kSecAttrProtocolHTTPS {
            self = .HTTPS
        } else {
            return nil
        }
    }

    var scheme: String {
        switch self {
        case .HTTP:
            return "http"
        case .HTTPS:
            return "https"
        }
    }

    var secAttrProtocol: CFString {
        switch self {
        case .HTTP:
            return kSecAttrProtocolHTTP
        case .HTTPS:
            return kSecAttrProtocolHTTPS
        }
    }
}


private extension NSURLComponents {
    convenience init?(keychainAttributes: [NSObject: AnyObject]) {
        self.init()

        if let secAttProtocol = keychainAttributes[kSecAttrProtocol as String] {
            scheme = SecurityProtocol(secAttrProtocol: secAttProtocol as! CFString)?.scheme
        }

        host = keychainAttributes[kSecAttrServer as String] as? String

        if let port = keychainAttributes[kSecAttrPort as String] as? NSNumber where port.integerValue > 0 {
            self.port = port
        }

        path = keychainAttributes[kSecAttrPath as String] as? String
    }

    var keychainAttributes: [String: NSObject] {
        var query: [String: NSObject] = [:]

        if let `protocol` = SecurityProtocol(scheme: scheme) {
            query[kSecAttrProtocol as String] = `protocol`.secAttrProtocol
        }

        if let host = host {
            query[kSecAttrServer as String] = host
        }

        if let port = port {
            query[kSecAttrPort as String] = port
        }

        if let path = path {
            query[kSecAttrPath as String] = path
        }

        return query
    }
}

