//
//  PresetsTrainingCard.swift
//  Loop
//
//  Created by Cameron Ingham on 8/27/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI

public struct PresetsTrainingCard: View {
    
    let imageName: String?
    
    public init(trainingCompletion: PresetsTrainingCompletion) {
        if trainingCompletion.completedChapters[.customizingPresets] != true {
            self.imageName = "PresetsTrainingCreditEditStartCard"
        } else if !trainingCompletion.isComplete {
            self.imageName = "PresetsTrainingCreditEditResumeCard"
        } else {
            self.imageName = nil
        }
    }
    
    public var body: some View {
        if let imageName, let image = Image.optional(imageName) {
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        }
    }
}
