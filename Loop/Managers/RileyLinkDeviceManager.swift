//
//  RileyLinkDeviceManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import RileyLinkKit


extension RileyLinkDeviceManager {
    /// Read the pump's current state, including reservoir and clock
    ///
    /// - Parameter completion: A closure called after the command is complete. This closure takes a single Result argument:
    /// - Parameter result:
    ///     - success(status, date): The pump status, and the resolved date according to the pump's clock
    ///     - failure(error): An error describing why the command failed
    func readPumpData(_ completion: @escaping (_ result: RileyLinkKit.Either<(status: RileyLinkKit.PumpStatus, date: Date), Error>) -> Void) {
        guard let device = firstConnectedDevice, let ops = device.ops else {
            completion(.failure(LoopError.connectionError))
            return
        }

        ops.readPumpStatus { (result) in
            switch result {
            case .success(let status):
                var clock = status.clock
                clock.timeZone = ops.pumpState.timeZone

                guard let date = clock.date else {
                    let errorStr = "Could not interpret pump clock: \(clock)"
                    completion(.failure(LoopError.invalidData(details: errorStr)))
                    return
                }
                completion(.success((status: status, date: date)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

}
