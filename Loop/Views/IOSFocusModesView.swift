//
//  IOSFocusModesView.swift
//  Loop
//
//  Created by Cameron Ingham on 6/11/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

struct IOSFocusModesView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.appName) private var appName

    var bullets: [String] {
        [
            NSLocalizedString("Go to Settings > Focus.", comment: "Focus modes step 1"),
            NSLocalizedString("Tap a provided Focus option — like Do Not Disturb, Personal, or Sleep.", comment: "Focus modes step 2"),
            NSLocalizedString("Tap “Apps”.", comment: "Focus modes step 3"),
            String(format: NSLocalizedString("Ensure that notifications are allowed and NOT silenced from %1$@.", comment: "Focus modes step 4 (1: appName)"), appName)
        ]
    }
    
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 24) {
                Text(
                    String(
                        format: NSLocalizedString(
                            "iOS has added features such as ‘Focus Mode’ that enable you to have more control over when apps can send you notifications.\n\nIf you wish to continue receiving important notifications from %1$@ while in a Focus Mode, you must ensure that notifications are allowed and NOT silenced from %1$@ for each Focus Mode.",
                            comment: "Description text for iOS Focus Modes (1: app name) (2: app name)"
                        ),
                        appName,
                        appName
                    )
                )
                
                ForEach(Array(zip(bullets.indices, bullets)), id: \.0) { index, bullet in
                    HStack(spacing: 10) {
                        NumberCircle(index + 1)
                        
                        Text(bullet)
                    }
                }
                
                // MARK: To be removed before next DIY Sync
                if appName.contains("Tidepool") {
                    VStack(alignment: .leading, spacing: 8) {
                        Image("focus-mode-1")
                        
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Example: Allow Notifications from %1$@",
                                    comment: "Focus mode image 1 caption (1: appName)"
                                ),
                                appName
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Image("focus-mode-2")
                        
                        Text(
                            NSLocalizedString(
                                "Example: Silence Notifications from other apps",
                                comment: "Focus mode image 2 caption"
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                
                Callout(
                    .caution,
                    title: Text(
                        NSLocalizedString(
                            "You’ll need to ensure these settings for each Focus Mode you have enabled or plan to enable.",
                            comment: "iOS focus modes callout title"
                        )
                    )
                )
                .padding(.horizontal, -20)
                .padding(.bottom, -22)
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(NSLocalizedString("iOS Focus Modes", comment: "View title for iOS focus modes"))
    }
}
