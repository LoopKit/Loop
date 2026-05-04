//
//  SiteAtlas_SiteSelectionSheet.swift
//  Loop
//
//  SiteAtlas — Modal sheet for logging a new site placement.
//  Presented on pump deactivation or manual trigger from Settings.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct SiteAtlas_SiteSelectionSheet: View {

    @ObservedObject var coordinator = SiteAtlas_Coordinator.shared

    @State private var selectedType: SiteAtlas_SiteType = .pump
    @State private var selectedSide: SiteAtlas_BodySide = .front
    @State private var pinLocation: CGPoint? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var notes: String = ""
    @State private var existingEntries: [SiteAtlas_SiteEntry] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        headerSection
                        siteTypePicker
                        bodySidePicker
                        bodyMapSection
                        notesSection
                    }
                    .padding()
                }

                // Save button pinned to bottom, always visible
                actionButtons
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .padding(.top, 4)
            }
            .navigationTitle("Log Site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        coordinator.skipLogging()
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            selectedType = coordinator.promptedSiteType
            existingEntries = coordinator.allEntries()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 4) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 32))
                .foregroundColor(SiteAtlas_Theme.primaryColor)
            Text("Where did you place your \(selectedType.displayName.lowercased())?")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var siteTypePicker: some View {
        Picker("Site Type", selection: $selectedType) {
            ForEach(SiteAtlas_SiteType.allCases, id: \.self) { type in
                Label(type.displayName, systemImage: type.iconName)
                    .tag(type)
            }
        }
        .pickerStyle(.segmented)
    }

    private var bodySidePicker: some View {
        Picker("Body Side", selection: $selectedSide) {
            ForEach(SiteAtlas_BodySide.allCases, id: \.self) { side in
                Text(side.displayName).tag(side)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedSide) { _ in
            // Clear pin when switching sides
            pinLocation = nil
            dragOffset = .zero
        }
    }

    private var bodyMapSection: some View {
        GeometryReader { geometry in
            let imageSize = imageFitSize(in: geometry.size)
            let imageOrigin = CGPoint(
                x: (geometry.size.width - imageSize.width) / 2,
                y: (geometry.size.height - imageSize.height) / 2
            )

            ZStack {
                bodyImage(for: selectedSide)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                // Recommended placement zones
                ForEach(SiteAtlas_Zones.zones(for: selectedSide).filter { SiteAtlas_Zones.isEnabled($0) }) { zone in
                    Ellipse()
                        .fill(Color.gray.opacity(0.18))
                        .overlay(Ellipse().strokeBorder(Color.gray.opacity(0.35), lineWidth: 1))
                        .frame(
                            width: zone.radiusX * 2 * imageSize.width,
                            height: zone.radiusY * 2 * imageSize.height
                        )
                        .position(
                            x: imageOrigin.x + zone.centerX * imageSize.width,
                            y: imageOrigin.y + zone.centerY * imageSize.height
                        )
                        .allowsHitTesting(false)
                }

                // Show existing pins on same side (faded, non-interactive)
                ForEach(existingEntries.filter { $0.bodySide == selectedSide && !$0.isHidden }) { entry in
                    Image(systemName: entry.type.iconName)
                        .font(.system(size: 18))
                        .foregroundColor(SiteAtlas_Theme.ageColor(daysSincePlaced: entry.daysSincePlaced).opacity(0.5))
                        .position(
                            x: imageOrigin.x + entry.normalizedX * imageSize.width,
                            y: imageOrigin.y + entry.normalizedY * imageSize.height
                        )
                        .allowsHitTesting(false)
                }

                // Placed pin (visual only, hit testing disabled)
                if let pin = pinLocation {
                    let currentScreenX = imageOrigin.x + pin.x * imageSize.width + dragOffset.width
                    let currentScreenY = imageOrigin.y + pin.y * imageSize.height + dragOffset.height
                    let currentNormX = (currentScreenX - imageOrigin.x) / imageSize.width
                    let currentNormY = (currentScreenY - imageOrigin.y) / imageSize.height
                    let proximityColor = proximityColor(at: CGPoint(x: currentNormX, y: currentNormY))

                    Image(systemName: selectedType.iconName)
                        .font(.system(size: isDragging ? 110 : 26))
                        .foregroundColor(isDragging ? proximityColor : selectedType.color)
                        .shadow(color: .black.opacity(isDragging ? 0.7 : 0.3), radius: isDragging ? 8 : 3, x: 0, y: isDragging ? 5 : 2)
                        .background(
                            Circle()
                                .fill((isDragging ? proximityColor : selectedType.color).opacity(0.2))
                                .frame(width: isDragging ? 130 : 0, height: isDragging ? 130 : 0)
                        )
                        .position(x: currentScreenX, y: currentScreenY)
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.15), value: isDragging)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if pinLocation != nil {
                            // Check if drag started near existing pin
                            let pinScreenX = imageOrigin.x + (pinLocation?.x ?? 0) * imageSize.width
                            let pinScreenY = imageOrigin.y + (pinLocation?.y ?? 0) * imageSize.height
                            let dist = hypot(value.startLocation.x - pinScreenX, value.startLocation.y - pinScreenY)
                            if dist < 50 {
                                if !isDragging {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        isDragging = true
                                    }
                                }
                                dragOffset = value.translation
                                return
                            }
                        }
                    }
                    .onEnded { value in
                        let pinScreenX = imageOrigin.x + (pinLocation?.x ?? 0) * imageSize.width
                        let pinScreenY = imageOrigin.y + (pinLocation?.y ?? 0) * imageSize.height
                        let dist = hypot(value.startLocation.x - pinScreenX, value.startLocation.y - pinScreenY)

                        if pinLocation != nil && dist < 50 {
                            // Finished dragging — clamp to body bounds
                            let newX = (pinScreenX + value.translation.width - imageOrigin.x) / imageSize.width
                            let newY = (pinScreenY + value.translation.height - imageOrigin.y) / imageSize.height
                            let clamped = clampToBodyBounds(CGPoint(x: newX, y: newY))
                            withAnimation(.spring(response: 0.2)) {
                                pinLocation = clamped
                                dragOffset = .zero
                                isDragging = false
                            }
                        } else {
                            // Tap or tap-away — place new pin, clamped to body
                            let normX = (value.location.x - imageOrigin.x) / imageSize.width
                            let normY = (value.location.y - imageOrigin.y) / imageSize.height
                            guard normX >= 0, normX <= 1, normY >= 0, normY <= 1 else { return }
                            let clamped = clampToBodyBounds(CGPoint(x: normX, y: normY))
                            withAnimation(.spring(response: 0.3)) {
                                pinLocation = clamped
                                dragOffset = .zero
                                isDragging = false
                            }
                        }
                    }
            )
        }
        .frame(height: 567)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .overlay(
            Group {
                if pinLocation == nil {
                    Text("Tap to place, drag to adjust")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        )
    }

    private var notesSection: some View {
        TextField("Notes (optional)", text: $notes)
            .textFieldStyle(.roundedBorder)
            .font(.subheadline)
    }

    private var actionButtons: some View {
        Button(action: saveSite) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save Site")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(pinLocation != nil ? SiteAtlas_Theme.primaryColor : Color.gray)
            )
        }
        .disabled(pinLocation == nil)
    }

    // MARK: - Helpers

    private func bodyImage(for side: SiteAtlas_BodySide) -> Image {
        let filename = side == .front ? "BodyMapFront" : "BodyMapBack"
        if let path = Bundle.main.path(forResource: filename, ofType: "png"),
           let uiImage = UIImage(contentsOfFile: path) {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "figure.stand")
    }

    private func imageFitSize(in containerSize: CGSize) -> CGSize {
        let imageAspect: CGFloat = 574.0 / 1282.0
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect < containerAspect {
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        } else {
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        }
    }

    /// Clamps a normalized point to the approximate body silhouette bounds.
    /// The body map figure occupies roughly the center of the image — this prevents
    /// pins from being placed in the empty space outside the body outline.
    /// If the point is outside, it snaps to the nearest edge of the body region.
    private func clampToBodyBounds(_ point: CGPoint) -> CGPoint {
        // Approximate body silhouette in normalized coords (0-1).
        // These define horizontal bounds at various Y positions (top to bottom).
        // Format: (y, xMin, xMax)
        let bodyProfile: [(y: Double, xMin: Double, xMax: Double)] = [
            (0.05, 0.35, 0.65),  // Top of head
            (0.10, 0.32, 0.68),  // Head
            (0.15, 0.30, 0.70),  // Head/neck
            (0.18, 0.42, 0.58),  // Neck
            (0.22, 0.20, 0.80),  // Shoulders
            (0.30, 0.15, 0.85),  // Upper arms/chest
            (0.40, 0.18, 0.82),  // Arms/torso
            (0.50, 0.22, 0.78),  // Waist
            (0.55, 0.22, 0.78),  // Hips
            (0.60, 0.25, 0.75),  // Upper thighs
            (0.70, 0.28, 0.72),  // Mid thighs
            (0.80, 0.30, 0.70),  // Knees
            (0.90, 0.32, 0.68),  // Calves
            (0.95, 0.33, 0.67),  // Ankles
        ]

        let y = min(max(point.y, bodyProfile.first!.y), bodyProfile.last!.y)

        // Find the two profile entries that bracket this Y
        var xMin = 0.3, xMax = 0.7
        for i in 0..<(bodyProfile.count - 1) {
            let lower = bodyProfile[i]
            let upper = bodyProfile[i + 1]
            if y >= lower.y && y <= upper.y {
                let t = (y - lower.y) / (upper.y - lower.y)
                xMin = lower.xMin + t * (upper.xMin - lower.xMin)
                xMax = lower.xMax + t * (upper.xMax - lower.xMax)
                break
            }
        }

        let x = min(max(point.x, xMin), xMax)
        return CGPoint(x: x, y: y)
    }

    /// Returns green if far from recent sites, red if close to a recently-used site.
    /// Checks all visible entries on the same body side. Distance is normalized (0–1 range).
    private func proximityColor(at point: CGPoint) -> Color {
        let sameSideEntries = existingEntries.filter { $0.bodySide == selectedSide && !$0.isHidden }
        guard !sameSideEntries.isEmpty else { return .green }

        // Find the closest recent entry — weight by both distance and recency
        var worstThreat: Double = 0 // 0 = safe, 1 = danger
        for entry in sameSideEntries {
            let dist = hypot(point.x - entry.normalizedX, point.y - entry.normalizedY)
            // Normalize: 0.15 in normalized coords (~body-width fraction) is "too close"
            let distanceThreat = max(0, 1.0 - dist / 0.15)
            // Weight by recency: fresh sites (0 days) = full threat, 14+ days = no threat
            let recencyWeight = max(0, 1.0 - Double(entry.daysSincePlaced) / 14.0)
            let threat = distanceThreat * recencyWeight
            worstThreat = max(worstThreat, threat)
        }

        // Interpolate: 0 = green (safe), 1 = red (danger)
        let r = min(worstThreat * 2.0, 1.0)
        let g = min((1.0 - worstThreat) * 2.0, 1.0)
        return Color(red: r, green: g, blue: 0.1)
    }

    private func saveSite() {
        guard let pin = pinLocation else { return }

        let entry = SiteAtlas_SiteEntry(
            type: selectedType,
            bodySide: selectedSide,
            normalizedX: pin.x,
            normalizedY: pin.y,
            notes: notes.isEmpty ? nil : notes
        )

        coordinator.logSite(entry)
        dismiss()
    }
}
