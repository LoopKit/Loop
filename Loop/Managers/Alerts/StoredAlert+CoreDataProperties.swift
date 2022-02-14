//
//  StoredAlert+CoreDataProperties.swift
//  Loop
//
//  Created by Rick Pasetto on 5/22/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//
//

import Foundation
import CoreData


extension StoredAlert {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<StoredAlert> {
        return NSFetchRequest<StoredAlert>(entityName: "StoredAlert")
    }

    @NSManaged public var acknowledgedDate: Date?
    @NSManaged public var alertIdentifier: String
    @NSManaged public var backgroundContent: String?
    @NSManaged public var foregroundContent: String?
    @NSManaged public var primitiveInterruptionLevel: NSNumber
    @NSManaged public var issuedDate: Date
    @NSManaged public var managerIdentifier: String
    @NSManaged public var metadata: String?
    @NSManaged public var modificationCounter: Int64
    @NSManaged public var retractedDate: Date?
    @NSManaged public var sound: String?
    @NSManaged public var syncIdentifier: UUID?
    @NSManaged public var triggerInterval: NSNumber?
    @NSManaged public var triggerType: Int16
    
}

extension StoredAlert: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(acknowledgedDate, forKey: .acknowledgedDate)
        try container.encode(alertIdentifier, forKey: .alertIdentifier)
        try container.encodeIfPresent(backgroundContent, forKey: .backgroundContent)
        try container.encodeIfPresent(foregroundContent, forKey: .foregroundContent)
        try container.encode(interruptionLevel, forKey: .interruptionLevel)
        try container.encode(issuedDate, forKey: .issuedDate)
        try container.encode(managerIdentifier, forKey: .managerIdentifier)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encode(modificationCounter, forKey: .modificationCounter)
        try container.encodeIfPresent(retractedDate, forKey: .retractedDate)
        try container.encodeIfPresent(sound, forKey: .sound)
        try container.encodeIfPresent(syncIdentifier, forKey: .syncIdentifier)
        try container.encodeIfPresent(triggerInterval?.doubleValue, forKey: .triggerInterval)
        try container.encode(triggerType, forKey: .triggerType)
    }

    private enum CodingKeys: String, CodingKey {
        case acknowledgedDate
        case alertIdentifier
        case backgroundContent
        case foregroundContent
        case interruptionLevel
        case issuedDate
        case managerIdentifier
        case metadata
        case modificationCounter
        case retractedDate
        case sound
        case syncIdentifier
        case triggerInterval
        case triggerType
    }
}
