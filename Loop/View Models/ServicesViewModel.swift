//
//  ServicesViewModel.swift
//  Loop
//
//  Created by Rick Pasetto on 8/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI

public protocol ServicesViewModelDelegate: class {
    func addService(identifier: String)
    func gotoService(identifier: String)
}

public class ServicesViewModel: ObservableObject {
    
    @Published var showServices: Bool
    @Published var availableServices: () -> [AvailableService]
    @Published var activeServices: () -> [Service]
    
    var inactiveServices: () -> [AvailableService] {
        return {
            return self.availableServices().filter { availableService in
                !self.activeServices().contains { $0.serviceIdentifier == availableService.identifier }
            }
        }
    }
    
    weak var delegate: ServicesViewModelDelegate?
    
    init(showServices: Bool,
         availableServices: @escaping () -> [AvailableService],
         activeServices: @escaping () -> [Service],
         delegate: ServicesViewModelDelegate? = nil) {
        self.showServices = showServices
        self.activeServices = activeServices
        self.availableServices = availableServices
        self.delegate = delegate
    }
    
    func didTapService(_ index: Int) {
        delegate?.gotoService(identifier: activeServices()[index].serviceIdentifier)
    }
    
    func didTapAddService(_ availableService: AvailableService) {
        delegate?.addService(identifier: availableService.identifier)
    }
}
