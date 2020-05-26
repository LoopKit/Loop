//
//  StoredAlert.swift
//  Loop
//
//  Created by Rick Pasetto on 5/11/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreData
import LoopKit

extension StoredAlert {
    
    static var encoder = JSONEncoder()
    static var decoder = JSONDecoder()
          
    convenience init(from deviceAlert: DeviceAlert, context: NSManagedObjectContext, issuedDate: Date = Date()) {
        do {
            self.init(context: context)
            self.issuedDate = issuedDate
            alertIdentifier = deviceAlert.identifier.alertIdentifier
            managerIdentifier = deviceAlert.identifier.managerIdentifier
            triggerType = deviceAlert.trigger.storedType
            triggerInterval = deviceAlert.trigger.storedInterval
            isCritical = deviceAlert.foregroundContent?.isCritical ?? false || deviceAlert.backgroundContent?.isCritical ?? false
            // Encode as JSON strings
            let encoder = StoredAlert.encoder
            sound = try encoder.encodeToStringIfPresent(deviceAlert.sound)
            foregroundContent = try encoder.encodeToStringIfPresent(deviceAlert.foregroundContent)
            backgroundContent = try encoder.encodeToStringIfPresent(deviceAlert.backgroundContent)
        } catch {
            fatalError("Failed to encode: \(error)")
        }
    }

    public var trigger: DeviceAlert.Trigger {
        get {
            do {
                return try DeviceAlert.Trigger(storedType: triggerType, storedInterval: triggerInterval)
            } catch {
                fatalError("\(error): \(triggerType) \(String(describing: triggerInterval))")
            }
        }
    }
    
    public var title: String? {
        if let contentString = foregroundContent ?? backgroundContent,
            let contentData = contentString.data(using: .utf8),
            let content = try? StoredAlert.decoder.decode(DeviceAlert.Content.self, from: contentData) {
            return content.title
        }
        return nil
    }
    
    public var identifier: DeviceAlert.Identifier {
        return DeviceAlert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: alertIdentifier)
    }
    
    public override func willSave() {
        if isInserted || isUpdated {
            setPrimitiveValue(managedObjectContext!.modificationCounter ?? 0, forKey: "modificationCounter")
        }
        super.willSave()
    }
}

extension DeviceAlert.Trigger {
    enum StorageError: Error {
        case invalidStoredInterval, invalidStoredType
    }
    
    var storedType: Int16 {
        switch self {
        case .immediate: return 0
        case .delayed: return 1
        case .repeating: return 2
        }
    }
    var storedInterval: NSNumber? {
        switch self {
        case .immediate: return nil
        case .delayed(let interval): return NSNumber(value: interval)
        case .repeating(let repeatInterval): return NSNumber(value: repeatInterval)
        }
    }
    init(storedType: Int16, storedInterval: NSNumber?) throws {
        switch storedType {
        case 0: self = .immediate
        case 1:
            if let storedInterval = storedInterval {
                self = .delayed(interval: storedInterval.doubleValue)
            } else {
                throw StorageError.invalidStoredInterval
            }
        case 2:
            if let storedInterval = storedInterval {
                self = .repeating(repeatInterval: storedInterval.doubleValue)
            } else {
                throw StorageError.invalidStoredInterval
            }
        default:
            throw StorageError.invalidStoredType
        }
    }
}

enum JSONEncoderError: Swift.Error {
    case stringEncodingError
}

fileprivate extension JSONEncoder {
    func encodeToStringIfPresent<T>(_ encodable: T?) throws -> String? where T: Encodable {
        guard let encodable = encodable else { return nil }
        let data = try self.encode(encodable)
        guard let result = String(data: data, encoding: .utf8) else {
            throw JSONEncoderError.stringEncodingError
        }
        return result
    }
}
