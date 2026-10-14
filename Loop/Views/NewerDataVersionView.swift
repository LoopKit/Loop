//
//  NewerDataVersionView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

final class NewerDataVersionViewController: UIHostingController<NewerDataVersionView> {
    init() {
        super.init(rootView: NewerDataVersionView())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct NewerDataVersionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(NSLocalizedString("Data From a Newer Version", comment: "Title of the screen shown when Loop's data was saved by a newer version of Loop"))
                .font(.title2.bold())
            Text(NSLocalizedString("This data is from a newer version of Loop. Install that version to continue.", comment: "Explanation shown when Loop's data was saved by a newer version of Loop"))
            Text(NSLocalizedString("Until then, Loop is not running and does not adjust insulin. Your data has not been changed.", comment: "Consequence shown when Loop's data was saved by a newer version of Loop"))
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}
