//
//  FoodFinder_ImageCropView.swift
//  Loop
//
//  FoodFinder — Interactive image crop view for focusing AI analysis.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit

/// Interactive crop overlay shown after capturing/selecting a photo.
/// Users can drag and resize a crop rectangle to focus the AI analysis
/// on a specific portion of the image (e.g., a menu section or a single dish).
struct FoodFinder_ImageCropView: View {

    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onSkip: (UIImage) -> Void

    // MARK: - Crop State

    /// The crop rectangle in image-view-relative coordinates.
    @State private var cropRect: CGRect = .zero
    /// Tracks which handle/edge is being dragged.
    @State private var activeHandle: CropHandle? = nil
    /// The rect at drag start for offset calculations.
    @State private var dragStartRect: CGRect = .zero
    /// The frame of the displayed image within the GeometryReader.
    @State private var imageFrame: CGRect = .zero

    /// Minimum crop dimension (points).
    private let minCropSize: CGFloat = 60

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Image + crop overlay
                    GeometryReader { geo in
                        let fitted = fittedImageRect(in: geo.size)

                        ZStack {
                            // The photo
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: fitted.width, height: fitted.height)
                                .position(x: fitted.midX, y: fitted.midY)

                            // Dimmed overlay outside crop
                            CropDimOverlay(cropRect: cropRect, bounds: fitted)

                            // Crop border + handles
                            CropBorderOverlay(cropRect: cropRect)

                            // Gesture layer
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { value in
                                            onDragChanged(value, in: fitted)
                                        }
                                        .onEnded { _ in
                                            activeHandle = nil
                                        }
                                )
                        }
                        .onAppear {
                            imageFrame = fitted
                            resetCropRect(in: fitted)
                        }
                        .onChange(of: geo.size) { _ in
                            let newFitted = fittedImageRect(in: geo.size)
                            imageFrame = newFitted
                            resetCropRect(in: newFitted)
                        }
                    }

                    // Bottom bar
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Button(action: { onSkip(image) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.right.circle")
                                    Text("Use Full Image")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                            }

                            Button(action: { performCrop() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "crop")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Crop & Analyze")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(red: 0.85, green: 0.25, blue: 0.85))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }

                        Text("Drag corners or edges to adjust the crop area")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle("Crop Image")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        resetCropRect(in: imageFrame)
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Image Fitting

    /// Computes the rect where the image is displayed (aspect-fit) within the container.
    private func fittedImageRect(in containerSize: CGSize) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        var w: CGFloat, h: CGFloat
        if imageAspect > containerAspect {
            w = containerSize.width
            h = w / imageAspect
        } else {
            h = containerSize.height
            w = h * imageAspect
        }

        let x = (containerSize.width - w) / 2
        let y = (containerSize.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Crop Rect Management

    private func resetCropRect(in fitted: CGRect) {
        // Default crop: 90% of the image area, centered
        let inset: CGFloat = fitted.width * 0.05
        cropRect = fitted.insetBy(dx: inset, dy: inset)
    }

    // MARK: - Drag Handling

    private func onDragChanged(_ value: DragGesture.Value, in bounds: CGRect) {
        if activeHandle == nil {
            // Determine which handle/region the drag started in
            activeHandle = hitTest(value.startLocation)
            dragStartRect = cropRect
        }

        guard let handle = activeHandle else { return }

        let dx = value.translation.width
        let dy = value.translation.height

        var newRect = dragStartRect

        switch handle {
        case .topLeft:
            newRect.origin.x = dragStartRect.minX + dx
            newRect.origin.y = dragStartRect.minY + dy
            newRect.size.width = dragStartRect.width - dx
            newRect.size.height = dragStartRect.height - dy
        case .topRight:
            newRect.origin.y = dragStartRect.minY + dy
            newRect.size.width = dragStartRect.width + dx
            newRect.size.height = dragStartRect.height - dy
        case .bottomLeft:
            newRect.origin.x = dragStartRect.minX + dx
            newRect.size.width = dragStartRect.width - dx
            newRect.size.height = dragStartRect.height + dy
        case .bottomRight:
            newRect.size.width = dragStartRect.width + dx
            newRect.size.height = dragStartRect.height + dy
        case .top:
            newRect.origin.y = dragStartRect.minY + dy
            newRect.size.height = dragStartRect.height - dy
        case .bottom:
            newRect.size.height = dragStartRect.height + dy
        case .left:
            newRect.origin.x = dragStartRect.minX + dx
            newRect.size.width = dragStartRect.width - dx
        case .right:
            newRect.size.width = dragStartRect.width + dx
        case .center:
            newRect.origin.x = dragStartRect.minX + dx
            newRect.origin.y = dragStartRect.minY + dy
        }

        // Enforce minimum size
        if newRect.width < minCropSize {
            if handle == .topLeft || handle == .bottomLeft || handle == .left {
                newRect.origin.x = newRect.maxX - minCropSize
            }
            newRect.size.width = minCropSize
        }
        if newRect.height < minCropSize {
            if handle == .topLeft || handle == .topRight || handle == .top {
                newRect.origin.y = newRect.maxY - minCropSize
            }
            newRect.size.height = minCropSize
        }

        // Clamp to image bounds
        newRect.origin.x = max(bounds.minX, newRect.origin.x)
        newRect.origin.y = max(bounds.minY, newRect.origin.y)
        if newRect.maxX > bounds.maxX {
            if handle == .center || handle == .right || handle == .topRight || handle == .bottomRight {
                newRect.origin.x = bounds.maxX - newRect.width
            }
            newRect.size.width = min(newRect.width, bounds.maxX - newRect.origin.x)
        }
        if newRect.maxY > bounds.maxY {
            if handle == .center || handle == .bottom || handle == .bottomLeft || handle == .bottomRight {
                newRect.origin.y = bounds.maxY - newRect.height
            }
            newRect.size.height = min(newRect.height, bounds.maxY - newRect.origin.y)
        }

        cropRect = newRect
    }

    /// Hit-test to determine which handle or region the touch is in.
    private func hitTest(_ point: CGPoint) -> CropHandle {
        let handleRadius: CGFloat = 30

        let corners: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: cropRect.minX, y: cropRect.minY)),
            (.topRight, CGPoint(x: cropRect.maxX, y: cropRect.minY)),
            (.bottomLeft, CGPoint(x: cropRect.minX, y: cropRect.maxY)),
            (.bottomRight, CGPoint(x: cropRect.maxX, y: cropRect.maxY)),
        ]

        for (handle, corner) in corners {
            if hypot(point.x - corner.x, point.y - corner.y) < handleRadius {
                return handle
            }
        }

        // Edge detection
        let edgeThreshold: CGFloat = 24
        let nearTop = abs(point.y - cropRect.minY) < edgeThreshold && point.x > cropRect.minX && point.x < cropRect.maxX
        let nearBottom = abs(point.y - cropRect.maxY) < edgeThreshold && point.x > cropRect.minX && point.x < cropRect.maxX
        let nearLeft = abs(point.x - cropRect.minX) < edgeThreshold && point.y > cropRect.minY && point.y < cropRect.maxY
        let nearRight = abs(point.x - cropRect.maxX) < edgeThreshold && point.y > cropRect.minY && point.y < cropRect.maxY

        if nearTop { return .top }
        if nearBottom { return .bottom }
        if nearLeft { return .left }
        if nearRight { return .right }

        return .center
    }

    // MARK: - Perform Crop

    private func performCrop() {
        // Convert crop rect from view coordinates to image pixel coordinates
        let scaleX = image.size.width / imageFrame.width
        let scaleY = image.size.height / imageFrame.height

        let pixelRect = CGRect(
            x: (cropRect.minX - imageFrame.minX) * scaleX,
            y: (cropRect.minY - imageFrame.minY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )

        // Clamp to image bounds
        let clampedRect = pixelRect.intersection(
            CGRect(origin: .zero, size: image.size)
        )

        guard !clampedRect.isEmpty,
              let cgImage = image.cgImage,
              let cropped = cgImage.cropping(to: clampedRect) else {
            // Fallback: use original image if crop fails
            onCrop(image)
            return
        }

        let croppedImage = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        onCrop(croppedImage)
    }
}

// MARK: - Crop Handle Enum

private enum CropHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case center
}

// MARK: - Dimmed Overlay (outside crop area)

private struct CropDimOverlay: View {
    let cropRect: CGRect
    let bounds: CGRect

    var body: some View {
        Canvas { context, size in
            // Fill entire area with semi-transparent black
            var fullPath = Path()
            fullPath.addRect(CGRect(origin: .zero, size: size))
            context.fill(fullPath, with: .color(.black.opacity(0.55)))

            // Cut out the crop area (clear it)
            var cropPath = Path()
            cropPath.addRect(cropRect)
            context.blendMode = .destinationOut
            context.fill(cropPath, with: .color(.white))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Crop Border + Corner Handles

private struct CropBorderOverlay: View {
    let cropRect: CGRect

    private let handleSize: CGFloat = 20
    private let handleThickness: CGFloat = 3

    var body: some View {
        Canvas { context, _ in
            // Dashed border
            let borderPath = Path(cropRect)
            context.stroke(
                borderPath,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )

            // Rule-of-thirds grid lines
            let thirdW = cropRect.width / 3
            let thirdH = cropRect.height / 3
            for i in 1...2 {
                var vLine = Path()
                let x = cropRect.minX + thirdW * CGFloat(i)
                vLine.move(to: CGPoint(x: x, y: cropRect.minY))
                vLine.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                context.stroke(vLine, with: .color(.white.opacity(0.3)), lineWidth: 0.5)

                var hLine = Path()
                let y = cropRect.minY + thirdH * CGFloat(i)
                hLine.move(to: CGPoint(x: cropRect.minX, y: y))
                hLine.addLine(to: CGPoint(x: cropRect.maxX, y: y))
                context.stroke(hLine, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
            }

            // Corner handles (L-shaped brackets)
            drawCornerHandle(context: context, x: cropRect.minX, y: cropRect.minY, dx: 1, dy: 1)
            drawCornerHandle(context: context, x: cropRect.maxX, y: cropRect.minY, dx: -1, dy: 1)
            drawCornerHandle(context: context, x: cropRect.minX, y: cropRect.maxY, dx: 1, dy: -1)
            drawCornerHandle(context: context, x: cropRect.maxX, y: cropRect.maxY, dx: -1, dy: -1)
        }
        .allowsHitTesting(false)
    }

    private func drawCornerHandle(context: GraphicsContext, x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) {
        var path = Path()
        // Horizontal arm
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + handleSize * dx, y: y))
        // Vertical arm
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x, y: y + handleSize * dy))

        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: handleThickness, lineCap: .round))
    }
}

// MARK: - Preview

#if DEBUG
struct FoodFinder_ImageCropView_Previews: PreviewProvider {
    static var previews: some View {
        FoodFinder_ImageCropView(
            image: UIImage(systemName: "photo")!,
            onCrop: { _ in },
            onSkip: { _ in }
        )
    }
}
#endif
