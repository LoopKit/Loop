//
//  CGMManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopUI


/// Describes the result of a CGM manager operation
///
/// - noData: No new data was available or retrieved
/// - newData: New glucose data was received and stored
/// - error: An error occurred while receiving or store data
enum CGMResult {
    case noData
    case newData([(quantity: HKQuantity, date: Date, isDisplayOnly: Bool)])
    case error(Error)
}


protocol CGMManagerDelegate: class {
    /// Asks the delegate for a date with which to filter incoming glucose data
    ///
    /// - Parameter manager: The manager instance
    /// - Returns: The date data occuring on or after which should be kept
    func startDateToFilterNewData(for manager: CGMManager) -> Date?

    /// Informs the delegate that the device has updated with a new result
    ///
    /// - Parameters:
    ///   - manager: The manager instance
    ///   - result: The result of the update
    func cgmManager(_ manager: CGMManager, didUpdateWith result: CGMResult) -> Void
}


protocol CGMManager: CustomDebugStringConvertible {
    weak var delegate: CGMManagerDelegate? { get set }

    /// Whether the device is capable of waking the app
    var providesBLEHeartbeat: Bool { get }

    var sensorState: SensorDisplayable? { get }

    /// The representation of the device for use in HealthKit
    var device: HKDevice? { get }

    /// Performs a manual fetch of glucose data from the device, if necessary
    ///
    /// - Parameters:
    ///   - deviceManager: The device manager instance to use for fetching
    ///   - completion: A closure called when operation has completed
    func fetchNewDataIfNeeded(with deviceManager: DeviceDataManager, _ completion: @escaping (CGMResult) -> Void) -> Void
}

