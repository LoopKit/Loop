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
          
    convenience init(from alert: Alert, context: NSManagedObjectContext, issuedDate: Date = Date()) {
        do {
            self.init(context: context)
            self.issuedDate = issuedDate
            alertIdentifier = alert.identifier.alertIdentifier
            managerIdentifier = alert.identifier.managerIdentifier
            triggerType = alert.trigger.storedType
            triggerInterval = alert.trigger.storedInterval
            isCritical = alert.foregroundContent?.isCritical ?? false || alert.backgroundContent?.isCritical ?? false
            // Encode as JSON strings
            let encoder = StoredAlert.encoder
            sound = try encoder.encodeToStringIfPresent(alert.sound)
            foregroundContent = try encoder.encodeToStringIfPresent(alert.foregroundContent)
            backgroundContent = try encoder.encodeToStringIfPresent(alert.backgroundContent)
        } catch {
            fatalError("Failed to encode: \(error)")
        }
    }

    public var trigger: Alert.Trigger {
        get {
            do {
                return try Alert.Trigger(storedType: triggerType, storedInterval: triggerInterval)
            } catch {
                fatalError("\(error): \(triggerType) \(String(describing: triggerInterval))")
            }
        }
    }
    
    public var title: String? {
        if let contentString = foregroundContent ?? backgroundContent,
            let contentData = contentString.data(using: .utf8),
            let content = try? StoredAlert.decoder.decode(Alert.Content.self, from: contentData) {
            return content.title
        }
        return nil
    }
    
    public var identifier: Alert.Identifier {
        return Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: alertIdentifier)
    }
    
    public override func willSave() {
        if isInserted || isUpdated {
            setPrimitiveValue(managedObjectContext!.modificationCounter ?? 0, forKey: "modificationCounter")
        }
        super.willSave()
    }
}

extension Alert.Trigger {
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
