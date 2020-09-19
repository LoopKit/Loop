//
//  GlucloserLogging.swift
//  Loop
//
//  Created by Nathan Lefler on 9/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

class GlucloserLogging {
  static var shared = GlucloserLogging()
  
  var urlSession: URLSession
  var dateFormatter: DateFormatter
  
  init() {
    urlSession = URLSession(configuration: URLSessionConfiguration.default)
    dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZ"
    dateFormatter.timeZone = TimeZone.autoupdatingCurrent
  }
  
  public func saveInsulin(dateTime: Date, units: Double) {
    let dateTimeS = dateFormatter.string(from: dateTime)
    guard let url =  URL(string: "https://auth.glucloser.com/log/insulin?dateTime=\(dateTimeS)&units=\(units)") else {
      return
    }
    let task = urlSession.dataTask(with: url)
    task.resume()
  }
  
  public func saveCarbs(dateTime: Date, carbs: HKQuantity) {
    let dateTimeS = dateFormatter.string(from: dateTime)
    let carbAmount: Int
    if carbs.is(compatibleWith: HKUnit.gram()) {
      carbAmount = Int(carbs.doubleValue(for: .gram()))
    } else if carbs.is(compatibleWith: HKUnit.count()) {
      carbAmount = Int(carbs.doubleValue(for: .count()))
    } else {
      carbAmount = 0
    }
    guard let url =  URL(string: "https://auth.glucloser.com/log/carb?dateTime=\(dateTimeS)&carbs=\(carbAmount)") else {
      return
    }
    let task = urlSession.dataTask(with: url)
    task.resume()
  }
}
