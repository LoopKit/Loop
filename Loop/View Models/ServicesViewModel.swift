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
                !self.activeServices().contains { $0.serviceIdentifier == availableService.identifier }
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
        delegate?.gotoService(withIdentifier: activeServices()[index].serviceIdentifier)
    }
    
    func didTapAddService(_ availableService: ServiceDescriptor) {
        delegate?.addService(withIdentifier: availableService.identifier)
    }
}
