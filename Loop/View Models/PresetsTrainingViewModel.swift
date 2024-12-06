//
//  PresetsTrainingViewModel.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

class PresetsTrainingViewModel: ObservableObject {
    
    @Published var navigationPath: [Step]
    
    init(step: Step = .creatingYourOwnPresets) {
        self.navigationPath = step.fullPath()
    }
    
    func nextPage() {
        if navigationPath.isEmpty, let firstPage = Step.allCases.dropFirst().first {
            navigationPath.append(firstPage)
        } else if let next = navigationPath.last?.next() {
            navigationPath.append(next)
        }
    }
}

extension PresetsTrainingViewModel {
    enum Step: Int, Hashable, CaseIterable {
        case creatingYourOwnPresets
        case howTheyWork1
        case howTheyWork2
        case presetsAndExercise1
        case presetsAndExercise2
        case presetsAndExercise3
        case presetsAndExercise4
        case presetsAndIllness1
        case presetsAndIllness2
        case presetsAndIllness3
        case presetsAndIllness4
        
        var localizedTitle: String {
            switch self {
            case .creatingYourOwnPresets:
                return NSLocalizedString("Creating Your Own Presets", comment: "Preset training, Creating your own presets, title")
            case .howTheyWork1, .howTheyWork2:
                return NSLocalizedString("How They Work", comment: "Preset training, How they work, title")
            case .presetsAndExercise1, .presetsAndExercise2, .presetsAndExercise3, .presetsAndExercise4:
                return NSLocalizedString("Presets and Exercise", comment: "Preset training, Presets and exercise, title")
            case .presetsAndIllness1, .presetsAndIllness2, .presetsAndIllness3, .presetsAndIllness4:
                return NSLocalizedString("Presets and Illness", comment: "Preset training, Presets and illness, title")
            }
        }
        
        var isFinalStep: Bool {
            self.rawValue == Step.allCases.last?.rawValue
        }
        
        fileprivate func next() -> Self? {
            switch self {
            case .creatingYourOwnPresets: .howTheyWork1
            case .howTheyWork1: .howTheyWork2
            case .howTheyWork2: .presetsAndExercise1
            case .presetsAndExercise1: .presetsAndExercise2
            case .presetsAndExercise2: .presetsAndExercise3
            case .presetsAndExercise3: .presetsAndExercise4
            case .presetsAndExercise4: .presetsAndIllness1
            case .presetsAndIllness1: .presetsAndIllness2
            case .presetsAndIllness2: .presetsAndIllness3
            case .presetsAndIllness3: .presetsAndIllness4
            case .presetsAndIllness4: nil
            }
        }
        
        fileprivate func fullPath() -> [Self] {
            guard let currentIndex = Step.allCases.firstIndex(of: self), currentIndex != 0 else {
                return []
            }
            
            return Array((1...currentIndex).map({ Step.allCases[$0] }))
        }
    }
}
