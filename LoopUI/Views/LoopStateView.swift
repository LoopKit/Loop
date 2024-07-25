//
//  LoopStateView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/7/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

class WrappedLoopStateViewModel: ObservableObject {
    @Published var loopStatusColors: StateColorPalette
    @Published var closedLoop: Bool
    @Published var freshness: LoopCompletionFreshness
    @Published var animating: Bool
    
    init(
        loopStatusColors: StateColorPalette = StateColorPalette(unknown: .black, normal: .black, warning: .black, error: .black),
        closedLoop: Bool = true,
        freshness: LoopCompletionFreshness = .stale,
        animating: Bool = false
    ) {
        self.loopStatusColors = loopStatusColors
        self.closedLoop = closedLoop
        self.freshness = freshness
        self.animating = animating
    }
}

struct WrappedLoopCircleView: View {
    
    @ObservedObject var viewModel: WrappedLoopStateViewModel
    
    var body: some View {
        LoopCircleView(closedLoop: viewModel.closedLoop, freshness: viewModel.freshness, animating: viewModel.animating)
            .environment(\.loopStatusColorPalette, viewModel.loopStatusColors)
    }
}

class LoopCircleHostingController: UIHostingController<WrappedLoopCircleView> {
    init(viewModel: WrappedLoopStateViewModel) {
        super.init(
            rootView: WrappedLoopCircleView(
                viewModel: viewModel
            )
        )
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
}


final class LoopStateView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        setupViews()
    }
    
    var loopStatusColors: StateColorPalette = StateColorPalette(unknown: .black, normal: .black, warning: .black, error: .black) {
        didSet {
            viewModel.loopStatusColors = loopStatusColors
        }
    }

    var freshness: LoopCompletionFreshness = .stale {
        didSet {
            viewModel.freshness = freshness
        }
    }
    
    var open = false {
        didSet {
            viewModel.closedLoop = !open
        }
    }

    var animated: Bool = false {
        didSet {
            viewModel.animating = animated
        }
    }
    
    private let viewModel = WrappedLoopStateViewModel()
    
    private func setupViews() {
        let hostingController = LoopCircleHostingController(viewModel: viewModel)
        
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

