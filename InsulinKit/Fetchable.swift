//
//  Fetchable.swift
//  Naterade
//
//  Based on https://gist.github.com/capttaco/adb38e0d37fbaf9c004e
//  See http://martiancraft.com/blog/2015/07/objective-c-swift-core-data/
//


import CoreData


protocol Fetchable {
    typealias FetchableType: NSManagedObject = Self

    static func entityName() -> String
    static func objectsInContext(context: NSManagedObjectContext, predicate: NSPredicate?, sortedBy: String?, ascending: Bool) throws -> [FetchableType]
    static func singleObjectInContext(context: NSManagedObjectContext, predicate: NSPredicate?, sortedBy: String?, ascending: Bool) throws -> FetchableType?
    static func objectCountInContext(context: NSManagedObjectContext, predicate: NSPredicate?) throws -> Int
    static func fetchRequest(context: NSManagedObjectContext, predicate: NSPredicate?, sortedBy: String?, ascending: Bool) -> NSFetchRequest
}


extension Fetchable where Self : NSManagedObject, FetchableType == Self {

    static func entityName() -> String {
        return NSStringFromClass(self).componentsSeparatedByString(".").last!
    }

    static func singleObjectInContext(context: NSManagedObjectContext, predicate: NSPredicate? = nil, sortedBy: String? = nil, ascending: Bool = false) throws -> FetchableType? {
        let managedObjects: [FetchableType] = try objectsInContext(context, predicate: predicate, sortedBy: sortedBy, ascending: ascending)

        return managedObjects.first
    }

    static func objectCountInContext(context: NSManagedObjectContext, predicate: NSPredicate? = nil) throws -> Int {
        let request = fetchRequest(context, predicate: predicate)
        var error: NSError? = nil;
        let count = context.countForFetchRequest(request, error: &error)

        if let error = error {
            throw error
        }

        return count;
    }

    static func objectsInContext(context: NSManagedObjectContext, predicate: NSPredicate? = nil, sortedBy: String? = nil, ascending: Bool = false) throws -> [FetchableType] {
        let request = fetchRequest(context, predicate: predicate, sortedBy: sortedBy, ascending: ascending)
        let fetchResults = try context.executeFetchRequest(request)

        return fetchResults as! [FetchableType]
    }

    static func fetchRequest(context: NSManagedObjectContext, predicate: NSPredicate? = nil, sortedBy: String? = nil, ascending: Bool = false) -> NSFetchRequest {
        let request = NSFetchRequest()

        request.entity = NSEntityDescription.entityForName(entityName(), inManagedObjectContext: context)
        request.predicate = predicate

        if (sortedBy != nil) {
            let sort = NSSortDescriptor(key: sortedBy, ascending: ascending)
            let sortDescriptors = [sort]
            request.sortDescriptors = sortDescriptors
        }

        return request
    }

    static func insertNewObjectInContext(context: NSManagedObjectContext) -> FetchableType {

        return NSEntityDescription.insertNewObjectForEntityForName(entityName(), inManagedObjectContext: context) as! FetchableType
    }
}
