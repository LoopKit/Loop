

import Foundation

extension NumberFormatter {
    class var bolus: NumberFormatter {
       let formatter = NumberFormatter()
       formatter.numberStyle = .decimal
       formatter.minimumIntegerDigits = 1

       return formatter
    }

    func string(fromBolusValue bolusValue: Double) -> String {
        switch bolusValue {
        case let x where x < 1:
            minimumFractionDigits = 3
        case let x where x < 10:
            minimumFractionDigits = 2
        default:
            minimumFractionDigits = 1
        }

        return string(from: bolusValue) ?? "--"
    }
}
