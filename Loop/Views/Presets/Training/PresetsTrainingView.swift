//
//  PresetsTrainingView.swift
//  Loop
//
//  Created by Cameron Ingham on 8/26/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

public struct PresetsTrainingView: View {

    @Environment(\.appName) private var appName
    @Environment(\.colorPalette) private var colorPalette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    
    @State private var training: PresetsTraining
    
    @State private var confirmDismiss: Bool = false
    @State private var showSkipToChapterSelector: Bool = false
    @State private var selectedMedia: MediaContent?
    
    private let trainingContent: [MediaContent]
    private let onComplete: (() -> Void)?
    
    public init(
        navigationPath: [PresetsTraining.Step] = [],
        startingAt: PresetsTraining.Chapter? = nil,
        trainingCompletionConfiguration: PresetsTraining.TrainingCompletionConfiguration,
        trainingContent: [MediaContent],
        onComplete: (() -> Void)? = nil
    ) {
        self.training = PresetsTraining(
            navigationPath: navigationPath,
            startingAt: startingAt,
            trainingCompletionConfiguration: trainingCompletionConfiguration
        )
        
        self.trainingContent = trainingContent
        self.onComplete = onComplete
    }
    
    @ViewBuilder
    private var closeButton: some View {
        Button("Close") {
            if training.trainingCompletion.isComplete {
                close()
            } else {
                confirmDismiss = true
            }
        }
    }
    
    public var body: some View {
        NavigationStack(path: $training.navigationPath) {
            stepView(training.startingAt.firstStep)
                .navigationDestination(for: PresetsTraining.Step.self) { step in
                    stepView(step)
                }
        }
        .environment(training)
        .interactiveDismissDisabled(!training.trainingCompletion.isComplete)
        .fullScreenCover(item: $selectedMedia) { media in
            MediaPlayerView(media: media)
        }
    }
    
    private func close() {
        dismiss()
    }

    @ViewBuilder
    private func ctaButtons(for cta: PresetsTraining.CTA) -> some View {
        switch cta {
        case .start:
            Button("Start Required Training") {
                training.next()
            }
            .buttonStyle(ActionButtonStyle())
        case .continue:
            Button("Continue") {
                training.next()
            }
            .buttonStyle(ActionButtonStyle())
        case .close:
            Button("Close") {
                close()
                training.trainingCompletion.completedChapters[.trainingComplete] = true
                onComplete?()
            }
            .buttonStyle(ActionButtonStyle())
        case .closeOrContinue(let continueTo, let chapter):
            VStack(spacing: 12) {
                Button("Close Training") {
                    if training.trainingCompletion.completedChapters[chapter] != true {
                        training.trainingCompletion.completedChapters[chapter] = true
                    }

                    close()
                }
                .buttonStyle(ActionButtonStyle(.secondary))

                Button("Continue to \(continueTo)") {
                    training.next()
                }
                .buttonStyle(ActionButtonStyle())
            }
        }
    }
    
    @ViewBuilder
    private func stepView(_ step: PresetsTraining.Step) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 8) {
                    Text(step.title(appName: appName))
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .onLongPressGesture {
                            guard training.trainingCompletion.allowDebugFeatures else {
                                return
                            }

                            showSkipToChapterSelector = true
                        }

                    Divider()
                }
                .padding(.bottom, 24)

                step.content(
                    appName: appName,
                    displayGlucosePreference: displayGlucosePreference,
                    colorPalette: colorPalette,
                    dynamicTypeSize: dynamicTypeSize,
                    trainingContent: trainingContent,
                    next: training.next,
                    onPlayMedia: { selectedMedia = $0 }
                )
                .padding(.bottom, 24)
                .padding(.horizontal, 16)

                if !step.references.isEmpty {
                    ReferencesView(step.references)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 16)
                }

                if let cta = step.cta {
                    ctaButtons(for: cta)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(step.contentBackground.ignoresSafeArea(.all))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbar {
            if step != .trainingComplete {
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                }
            }
        }
        .alert(isPresented: $confirmDismiss) {
            Alert(
                title: Text("End Training?"),
                message: Text("You'll have to restart this section and some features will be disabled until you complete the training."),
                primaryButton: .cancel(),
                secondaryButton: .destructive(Text("End"), action: { close() })
            )
        }
        .confirmationDialog("Skip to Chapter", isPresented: $showSkipToChapterSelector) {
            ForEach(PresetsTraining.Chapter.allCases, id: \.self) { chapter in
                Button {
                    dismiss()
                    training.trainingCompletion.complete(to: chapter)
                } label: {
                    chapter.title
                }
            }
        } message: {
            Text("Skip and complete training up to")
        }
    }
}
