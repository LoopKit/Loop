//
//  ServicesViewModel.swift
//  Loop
//
//  Created by Rick Pasetto on 8/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

public protocol ServicesViewModelDelegate: AnyObject {
    func addService(withIdentifier identifier: String)
    func gotoService(withIdentifier identifier: String)
}

public class ServicesViewModel: ObservableObject {
    
    @Published var showServices: Bool
    @Published var availableServices: () -> [ServiceDescriptor]
    @Published var activeServices: () -> [Service]
    
    var inactiveServices: () -> [ServiceDescriptor] {
        return {
            return self.availableServices().filter { availableService in
                !self.activeServices().contains { $0.pluginIdentifier == availableService.identifier }
            }
        }
    }
    
    weak var delegate: ServicesViewModelDelegate?
    
    init(showServices: Bool,
         availableServices: @escaping () -> [ServiceDescriptor],
         activeServices: @escaping () -> [Service],
         delegate: ServicesViewModelDelegate? = nil) {
        self.showServices = showServices
        self.activeServices = activeServices
        self.availableServices = availableServices
        self.delegate = delegate
    }
    
    func didTapService(_ index: Int) {
        delegate?.gotoService(withIdentifier: activeServices()[index].pluginIdentifier)
    }
    
    func didTapAddService(_ availableService: ServiceDescriptor) {
        delegate?.addService(withIdentifier: availableService.identifier)
    }
}

// For previews only
extension ServicesViewModel {
    fileprivate class FakeService1: Service {
        static var localizedTitle: String = "Service 1"
        static var pluginIdentifier: String = "FakeService1"
        var stateDelegate: StatefulPluggableDelegate?
        var serviceDelegate: ServiceDelegate?
        var rawState: RawStateValue = [:]
        required init() {}
        required init?(rawState: RawStateValue) {}
        let isOnboarded = true
        var available: ServiceDescriptor { ServiceDescriptor(identifier: pluginIdentifier, localizedTitle: localizedTitle) }
    }
    fileprivate class FakeService2: Service {
        static var localizedTitle: String = "Service 2"
        static var pluginIdentifier: String = "FakeService2"
        var stateDelegate: StatefulPluggableDelegate?
        var serviceDelegate: ServiceDelegate?
        var rawState: RawStateValue = [:]
        required init() {}
        required init?(rawState: RawStateValue) {}
        let isOnboarded = true
        var available: ServiceDescriptor { ServiceDescriptor(identifier: pluginIdentifier, localizedTitle: localizedTitle) }
    }

    static var preview: ServicesViewModel {
        return ServicesViewModel(showServices: true,
                                 availableServices: { [FakeService1().available, FakeService2().available] },
                                 activeServices: { [FakeService1()] })
    }
}
