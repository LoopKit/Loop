//
//  SiteAtlas_BodyMapView.swift
//  Loop
//
//  SiteAtlas — Visual body map with age-colored pins.
//  Shows front/back body outline with swipe navigation.
//  Existing pins are draggable to adjust position.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - Draggable Pin

/// A single pin on the body map that can be dragged to a new position.
/// Uses .offset() instead of .position() so the gesture hit area follows the visual.
private struct DraggablePin: View {
    let entry: SiteAtlas_SiteEntry
    let imageSize: CGSize
    let imageOrigin: CGPoint
    let containerSize: CGSize
    var onMoved: ((UUID, CGPoint) -> Void)?

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    var body: some View {
        let pinX = imageOrigin.x + entry.normalizedX * imageSize.width
        let pinY = imageOrigin.y + entry.normalizedY * imageSize.height
        // Offset from container center (ZStack centers its children by default)
        let offsetX = pinX - containerSize.width / 2 + dragOffset.width
        let offsetY = pinY - containerSize.height / 2 + dragOffset.height

        Image(systemName: entry.type.iconName)
            .font(.system(size: isDragging ? 110 : 22))
            .foregroundColor(SiteAtlas_Theme.ageColor(daysSincePlaced: entry.daysSincePlaced, type: entry.type))
            // Fade pins from full opacity at placement to 0 over the
            // type-specific safe-reuse window (pump: 10d, sensor: 5d).
            // Force full visibility while dragging so the user can see
            // what they're moving even if the pin is mid-fade.
            .opacity(isDragging ? 1.0 : SiteAtlas_Theme.ageOpacity(daysSincePlaced: entry.daysSincePlaced, type: entry.type))
            .shadow(color: .black.opacity(isDragging ? 0.7 : 0.3), radius: isDragging ? 8 : 2, x: 0, y: isDragging ? 5 : 1)
            .background(
                Circle()
                    .fill(SiteAtlas_Theme.ageColor(daysSincePlaced: entry.daysSincePlaced, type: entry.type).opacity(0.2))
                    .frame(width: isDragging ? 130 : 0, height: isDragging ? 130 : 0)
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            withAnimation(.easeOut(duration: 0.15)) {
                                isDragging = true
                            }
                        }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let newX = (pinX + value.translation.width - imageOrigin.x) / imageSize.width
                        let newY = (pinY + value.translation.height - imageOrigin.y) / imageSize.height
                        let clamped = CGPoint(
                            x: min(max(newX, 0), 1),
                            y: min(max(newY, 0), 1)
                        )
                        onMoved?(entry.id, clamped)
                        withAnimation(.easeOut(duration: 0.15)) {
                            isDragging = false
                        }
                        dragOffset = .zero
                    }
            )
            .offset(x: offsetX, y: offsetY)
            .animation(.easeOut(duration: 0.15), value: isDragging)
    }
}

// MARK: - Single Side Map View

struct SiteAtlas_BodyMapView: View {

    let entries: [SiteAtlas_SiteEntry]
    let selectedSide: SiteAtlas_BodySide
    let interactive: Bool
    var onTap: ((CGPoint) -> Void)? = nil
    var onPinMoved: ((UUID, CGPoint) -> Void)? = nil

    var body: some View {
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

                // Recommended placement zones (grey ellipses)
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

                // Existing pins — draggable when onPinMoved is provided
                ForEach(filteredEntries) { entry in
                    if onPinMoved != nil {
                        DraggablePin(
                            entry: entry,
                            imageSize: imageSize,
                            imageOrigin: imageOrigin,
                            containerSize: geometry.size,
                            onMoved: onPinMoved
                        )
                    } else {
                        Image(systemName: entry.type.iconName)
                            .font(.system(size: 22))
                            .foregroundColor(SiteAtlas_Theme.ageColor(daysSincePlaced: entry.daysSincePlaced, type: entry.type))
                            .opacity(SiteAtlas_Theme.ageOpacity(daysSincePlaced: entry.daysSincePlaced, type: entry.type))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .position(
                                x: imageOrigin.x + entry.normalizedX * imageSize.width,
                                y: imageOrigin.y + entry.normalizedY * imageSize.height
                            )
                    }
                }

                // Tap overlay — only when interactive (used by non-sheet contexts)
                if interactive, let onTap = onTap {
                    TapLocationView { rawPoint in
                        let normX = (rawPoint.x - imageOrigin.x) / imageSize.width
                        let normY = (rawPoint.y - imageOrigin.y) / imageSize.height
                        guard normX >= 0, normX <= 1, normY >= 0, normY <= 1 else { return }
                        onTap(CGPoint(x: normX, y: normY))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Computed

    private var filteredEntries: [SiteAtlas_SiteEntry] {
        entries.filter {
            $0.bodySide == selectedSide
                && !$0.isHidden
                && SiteAtlas_Theme.shouldDisplayOnBodyMap(daysSincePlaced: $0.daysSincePlaced, type: $0.type)
        }
    }

    /// Calculate the fitted image size within the container, preserving aspect ratio.
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

    // MARK: - Subviews

    private func bodyImage(for side: SiteAtlas_BodySide) -> Image {
        Image(side == .front ? "BodyMapFront" : "BodyMapBack")
    }
}

// MARK: - UIKit Tap Location Overlay

/// Transparent UIView that captures taps with location, letting swipes pass through to TabView.
private struct TapLocationView: UIViewRepresentable {
    var onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        var onTap: (CGPoint) -> Void

        init(onTap: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            onTap(location)
        }
    }
}

// MARK: - Swipeable Body Map

/// Full body map — swipe the image itself to flip between front and back.
struct SiteAtlas_SwipeableBodyMap: View {

    let entries: [SiteAtlas_SiteEntry]
    let interactive: Bool
    @Binding var selectedSide: SiteAtlas_BodySide
    var onTap: ((CGPoint) -> Void)? = nil
    var onPinMoved: ((UUID, CGPoint) -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Side label with chevrons
            HStack {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(selectedSide == .back ? 1 : 0.3)

                Spacer()

                Text(selectedSide.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(SiteAtlas_Theme.primaryColor)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(selectedSide == .front ? 1 : 0.3)
            }
            .padding(.horizontal, 8)

            // Swipeable body map pages
            TabView(selection: $selectedSide) {
                SiteAtlas_BodyMapView(
                    entries: entries,
                    selectedSide: .front,
                    interactive: interactive,
                    onTap: onTap,
                    onPinMoved: onPinMoved
                )
                .tag(SiteAtlas_BodySide.front)

                SiteAtlas_BodyMapView(
                    entries: entries,
                    selectedSide: .back,
                    interactive: interactive,
                    onTap: onTap,
                    onPinMoved: onPinMoved
                )
                .tag(SiteAtlas_BodySide.back)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Dot indicators
            HStack(spacing: 8) {
                Circle()
                    .fill(selectedSide == .front ? SiteAtlas_Theme.primaryColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(selectedSide == .back ? SiteAtlas_Theme.primaryColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Legend

struct SiteAtlas_MapLegend: View {
    var body: some View {
        VStack(spacing: 6) {
            // Device type icons
            HStack(spacing: 16) {
                legendItem(icon: "cross.circle.fill", label: "Pump")
                legendItem(icon: "sensor.fill", label: "Sensor")
            }
            // Age color scale
            HStack(spacing: 4) {
                Text("Recent")
                    .foregroundColor(.secondary)
                // Sample the ramp at 0/33/66/100% of the pump window so
                // the gradient renders the full red→green ramp. Sensor
                // shares the same ramp on a shorter clock, so one
                // gradient illustrates both.
                LinearGradient(
                    colors: [
                        SiteAtlas_Theme.ageColor(daysSincePlaced: 0,  type: .pump),
                        SiteAtlas_Theme.ageColor(daysSincePlaced: 3,  type: .pump),
                        SiteAtlas_Theme.ageColor(daysSincePlaced: 7,  type: .pump),
                        SiteAtlas_Theme.ageColor(daysSincePlaced: 10, type: .pump)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 6)
                .cornerRadius(3)
                Text("Safe")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
        .padding(.vertical, 4)
    }

    private func legendItem(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.primary)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}
