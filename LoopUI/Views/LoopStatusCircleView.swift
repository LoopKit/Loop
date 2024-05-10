//
//  LoopStatusCircleView.swift
//  LoopUI
//
//  Created by Arwain Karlin on 5/8/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

@available(iOSApplicationExtension 17.0, *)
public struct LoopStatusCircleView: View {
    
    public enum Status {
        case closedLoopOn
        case closedLoopOff
        case closedLoopUnavailable
        
        var color: Color {
            switch self {
            case .closedLoopOn:
                return .green  // Use guidanceColors
            case .closedLoopOff:
                return .red  // Use guidanceColors
            case .closedLoopUnavailable:
                return .orange // Use guidanceColors
            }
        }
    }
    
    @Binding var closedLoop: Bool
    var closedLoopUnavailable: Bool
    
    @State var loopStatus: Status
    
    public init(
        closedLoop: Binding<Bool>,
        closedLoopUnavailable: Bool
    ) {
        self._closedLoop = closedLoop
        self.closedLoopUnavailable = closedLoopUnavailable
        self.loopStatus = closedLoopUnavailable ? .closedLoopUnavailable : (closedLoop.wrappedValue ? .closedLoopOn : .closedLoopOff)
    }
    
    public var body: some View {
        Circle()
            .trim(from: closedLoop ? 0 : 0.25, to: 1)
            .rotation(.degrees(-135))
            .stroke(loopStatus.color, lineWidth: 6)
            .frame(width: 30)
            .animation(.default, value: closedLoop)
            .onChange(of: closedLoop) { _, newValue in
                withAnimation {
                    if closedLoopUnavailable {
                        loopStatus = .closedLoopUnavailable
                    } else {
                        loopStatus = newValue ? .closedLoopOn : .closedLoopOff
                    }
                }
            }
            .onChange(of: closedLoopUnavailable) { _, newValue in
                withAnimation {
                    if newValue {
                        loopStatus = .closedLoopUnavailable
                    } else {
                        loopStatus = closedLoop ? .closedLoopOn : .closedLoopOff
                    }
                }
            }
    }
}
