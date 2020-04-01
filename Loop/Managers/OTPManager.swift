//
//  OTPManager.swift
//  Loop
//
//  Created by Jose Paredes on 3/28/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import OneTimePassword
import Base32

private let OTPSecretKeyService = "OTPSecretKeyService"
private let OTPSecretKeyCreatedService = "OTPSecretKeyCreatedService"

extension KeychainManager {
    func setOTPSecretKey(_ key: String?) throws {
        try replaceGenericPassword(key, forService: OTPSecretKeyService)
    }
    func setOTPSecretKeyCreated(_ key: String?) throws {
        try replaceGenericPassword(key, forService: OTPSecretKeyCreatedService)
    }

    func getOTPSecretKey() -> String? {
        return try? getGenericPasswordForService(OTPSecretKeyService)
    }
    func getOTPSecretKeyCreated() -> String? {
        return try? getGenericPasswordForService(OTPSecretKeyCreatedService)
    }
}

private let Base32Dictionary = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
class OTPManager {

    private var otpToken: Token
    private var secretKey: String
    var otpURL: String
    var created: String
    
    func refreshOTPToken() {
       // TODO: refresh tokens
       // generate secret key
       self.secretKey = String((0..<32).map{_ in Base32Dictionary.randomElement()!})
       self.created = String(format: "%.0f", round(Date().timeIntervalSince1970*1000))
        
       // try to save new secret key
       let keychain = KeychainManager()
       do {
          try keychain.setOTPSecretKey(self.secretKey)
          try keychain.setOTPSecretKeyCreated(self.created)
       } catch {}
            
       // generator+token
       let secretKeyData = MF_Base32Codec.data(fromBase32String: secretKey)!
       let generator = Generator(factor: .timer(period: 30), secret: secretKeyData, algorithm: .sha1, digits: 6)!
       self.otpToken = Token(name: "\(created)", issuer: "Loop", generator: generator)
      
       // URL
       self.otpURL = "otpauth://totp/\(created)?algoritm=SHA1&digits=6&issuer=Loop&period=30&secret=\(secretKey)"
    }
    func otp() -> String {
        return self.otpToken.currentPassword!
    }
    
    init() {
        // OTP
        let keychain = KeychainManager()
        if let secretKeyVal = keychain.getOTPSecretKey(), let createdVal = keychain.getOTPSecretKeyCreated() {
            self.secretKey = secretKeyVal
            self.created = createdVal
        } else {
            
           // generate secret key
           self.secretKey = String((0..<32).map{_ in Base32Dictionary.randomElement()!})
           self.created = String(format: "%.0f", round(Date().timeIntervalSince1970*1000))
            
           // try to save secretKey
           do {
              try keychain.setOTPSecretKey(self.secretKey)
              try keychain.setOTPSecretKeyCreated(self.created)
           } catch {}
                
        }
        //print("OTP Secret Key: \(secretKey)")
        //print("OTP Created: \(created)")

        let secretKeyData = MF_Base32Codec.data(fromBase32String: self.secretKey)!
         
        // generator+token
        let generator = Generator(factor: .timer(period: 30), secret: secretKeyData, algorithm: .sha1, digits: 6)!
        self.otpToken = Token(name: "\(created)", issuer: "Loop", generator: generator)
        
        // url
        self.otpURL = "otpauth://totp/\(created)?algoritm=SHA1&digits=6&issuer=Loop&period=30&secret=\(secretKey)"
        //print("OTP URL: \(otpURL)")
        
        // first password
        // let password = self.otpToken.currentPassword!
        //print("OTP: \(password)")
    }
}



