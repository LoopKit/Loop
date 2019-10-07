//
//  ServicesManager.swift
//  Loop
//
//  Created by Darin Krauss on 5/22/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit

protocol ServicesManagerObserver {

    /// The service manager update the list of available services.
    ///
    /// - Parameter services: The list of available services
    func servicesManagerDidUpdate(services: [Service])

}

class ServicesManager {

    private let queue = DispatchQueue(label: "com.loopkit.ServicesManagerQueue", qos: .utility)

    private let lock = UnfairLock()

    private var observers = WeakSet<ServicesManagerObserver>()

    var services: [Service] {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))
            UserDefaults.appGroup?.services = services
            notifyObservers()
        }
    }

    init() {
        self.services = UserDefaults.appGroup?.services ?? []
    }

    public func addObserver(_ observer: ServicesManagerObserver) {
        lock.withLock {
            observers.insert(observer)
            return
        }
    }

    public func removeObserver(_ observer: ServicesManagerObserver) {
        lock.withLock {
            observers.remove(observer)
            return
        }
    }

    private func notifyObservers() {
        for observer in lock.withLock({ observers }) {
            observer.servicesManagerDidUpdate(services: services)
        }
    }

}
