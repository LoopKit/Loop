//
//  LoopDesign.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit

/// The tokens from the Loop design system (`design/project/tokens.json`).
///
/// Quantity colours reuse Loop's existing assets (`glucose`, `insulin`, `carbs`, `fresh`, `warning`, `accent`)
/// so a DerivedAssetsOverride still recolours them. Grounds and text map onto the iOS system colours they
/// were taken from; the rest are colour sets in DerivedAssetsBase.xcassets named after their token.
///
/// Insulin and carb amounts are set in `insulinInk` and `carbsInk` wherever they stand alone. Glucose, basal,
/// counts and figures beside a legend swatch stay `ink`. Red is only for something that needs action now.
enum LoopDesign {

    enum Palette {
        // Grounds
        static let surface = Color(uiColor: .systemGroupedBackground)
        static let surfaceRaised = Color(uiColor: .secondarySystemGroupedBackground)
        static let surfaceSunken = Color(uiColor: .systemGray5)
        static let controlThumb = Color("control-thumb")
        static let separator = Color(uiColor: .opaqueSeparator)
        static let grid = Color(uiColor: .systemGray5)

        // Text
        static let ink = Color(uiColor: .label)
        static let inkMuted = Color("ink-muted")
        static let accent = Color("accent")
        static let accentInk = Color("accent-ink")
        static let onFill = Color.black

        // Quantities
        static let glucose = Color("glucose")
        static let glucoseInk = Color("glucose-ink")
        static let targetBand = Color("target-band")
        static let agpOuter = Color("agp-outer")
        static let agpInner = Color("agp-inner")
        /// Insulin as a quantity and an action: the Bolus button and the active insulin curve.
        static let insulin = Color("insulin")
        /// Every insulin amount set as text, whether a bolus, a day's total or active insulin.
        static let insulinInk = Color("insulin-ink")
        static let basal = Color("basal")
        static let basalEdge = Color("basal-edge")
        /// Basal is a pale, quiet orange with a tan edge; bolus is insulin's orange made deep. Both stay orange,
        /// and their lightness is far enough apart (3:1 even where they touch) to tell them apart at a glance.
        static let bolus = Color("bolus")
        static let basalScheduled = inkMuted
        static let carbs = Color("carbs")
        static let carbsInk = Color("carbs-ink")

        // Time in range ladder, top to bottom
        static let rangeVeryHigh = Color("range-very-high")
        static let rangeHigh = Color("range-high")
        static let rangeIn = Color("range-in")
        static let rangeLow = Color("range-low")
        static let rangeVeryLow = Color("range-very-low")

        // Loop state
        static let statusAutomated = Color("fresh")
        static let statusWarning = Color("warning")
        static let criticalInk = Color("critical-ink")
    }

    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    /// Text styles follow Dynamic Type; the large numbers are fixed sizes in SF Pro Rounded with tabular figures.
    enum Typeface {
        static let statValue = Font.system(.title, design: .rounded).weight(.semibold).monospacedDigit()
        static let statValueSmall = Font.system(.title3, design: .rounded).weight(.semibold).monospacedDigit()
        static let title = Font.title.bold()
        static let headline = Font.headline
        static let body = Font.body
        static let subhead = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption2.weight(.medium).monospacedDigit()
    }
}

// MARK: - Card

struct LoopCard<Content: View>: View {
    var padding: CGFloat = LoopDesign.Space.s4
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s3) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LoopDesign.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: LoopDesign.Radius.lg, style: .continuous))
    }
}

/// A card title with an optional trailing detail or action, as on every card in the mock-ups.
struct CardHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(LoopDesign.Typeface.headline)
                .foregroundStyle(LoopDesign.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: LoopDesign.Space.s2)
            trailing
                .font(LoopDesign.Typeface.footnote)
                .foregroundStyle(LoopDesign.Palette.inkMuted)
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Legend

struct LegendItem: Identifiable {
    enum Swatch {
        case solid(Color)
        case outline(Color)
        case dash(Color)
        case dot(Color)
        case hatch(Color)
        case basal
    }

    let id = UUID()
    let swatch: Swatch
    let label: String
}

struct ChartLegend: View {
    let items: [LegendItem]

    var body: some View {
        FlowLayout(spacing: LoopDesign.Space.s3, lineSpacing: LoopDesign.Space.s1) {
            ForEach(items) { item in
                HStack(spacing: LoopDesign.Space.s1) {
                    LegendSwatch(swatch: item.swatch)
                    Text(item.label)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(LoopDesign.Typeface.footnote)
        .foregroundStyle(LoopDesign.Palette.inkMuted)
    }
}

/// The 10-point key for one kind of mark, shared by legends and the basal and bolus rows.
struct LegendSwatch: View {
    let swatch: LegendItem.Swatch
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch swatch {
        case .solid(let color):
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
        case .outline(let color):
            RoundedRectangle(cornerRadius: 2).strokeBorder(color, lineWidth: 1.5).frame(width: 10, height: 10)
        case .dash(let color):
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 14, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 2]))
            .frame(width: 14, height: 2)
        case .dot(let color):
            Circle().fill(color).frame(width: 8, height: 8)
        case .hatch(let color):
            RoundedRectangle(cornerRadius: 2).fill(Hatch.paint(color, scheme: scheme)).frame(width: 10, height: 10)
        case .basal:
            VStack(spacing: 0) {
                Rectangle().fill(LoopDesign.Palette.basalEdge).frame(height: 2)
                Rectangle().fill(LoopDesign.Palette.basal)
            }
            .frame(width: 10, height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

/// Diagonal stripes over a pale tint of a colour: automatic bolus, wherever a mark is wide enough to show it.
enum Hatch {
    static func paint(_ color: Color, scheme: ColorScheme) -> ImagePaint {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        let size: CGFloat = 5
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            resolved.withAlphaComponent(scheme == .dark ? 0.3 : 0.22).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            resolved.setStroke()
            // One stripe corner to corner, plus the ends of its neighbours, so tiles join into unbroken lines.
            let path = UIBezierPath()
            path.lineWidth = 1.4
            for offset in [-size, 0, size] {
                path.move(to: CGPoint(x: offset, y: size))
                path.addLine(to: CGPoint(x: offset + size, y: 0))
            }
            path.stroke()
        }
        return ImagePaint(image: Image(uiImage: image))
    }
}

/// Wraps its children onto new lines, for legends and chips.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// A row that stacks vertically at accessibility text sizes, so tiles and buttons keep their numbers on one line.
struct AdaptiveRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var spacing: CGFloat = LoopDesign.Space.s2
    @ViewBuilder var content: Content

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

// MARK: - Tiles

/// A small sunken tile with a label over a value, as used under the timeline.
struct ValueTile<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(LoopDesign.Typeface.footnote)
                .foregroundStyle(LoopDesign.Palette.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
            // A value with a long unit ("0.04 単位") shrinks to fit rather than breaking mid-word.
            value
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(LoopDesign.Space.s3)
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .topLeading)
        .background(LoopDesign.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The square icon tile at the start of logbook rows.
///
/// Insulin tiles are drawn the way the charts draw the same insulin, so a row and its mark read alike: manual bolus
/// solid, automatic bolus hatched, basal pale with its edge.
struct IconTile: View {
    enum Style {
        case solid(Color)
        case hatch(Color)
        case basal
    }

    let systemName: String
    let style: Style
    @Environment(\.colorScheme) private var scheme

    init(systemName: String, style: Style) {
        self.systemName = systemName
        self.style = style
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: LoopDesign.Radius.sm, style: .continuous) }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: isHatched ? 11 : 13, weight: .bold))
            .foregroundStyle(glyph)
            // Stripes behind a glyph blur it, so the hatched tile sets its glyph on a plain disc.
            .frame(width: isHatched ? 18 : 28, height: isHatched ? 18 : 28)
            .background { if isHatched { Circle().fill(LoopDesign.Palette.surfaceRaised) } }
            .frame(width: 28, height: 28)
            .background { background }
            .accessibilityHidden(true)
    }

    private var isHatched: Bool {
        if case .hatch = style { return true }
        return false
    }

    private var glyph: Color {
        switch style {
        case .solid: return LoopDesign.Palette.onFill
        case .hatch, .basal: return LoopDesign.Palette.insulinInk
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .solid(let fill):
            shape.fill(fill)
        case .hatch(let color):
            shape.fill(Hatch.paint(color, scheme: scheme))
                .overlay(shape.strokeBorder(color, lineWidth: 1.5))
        case .basal:
            shape.fill(LoopDesign.Palette.basal)
                .overlay(shape.strokeBorder(LoopDesign.Palette.basalEdge, lineWidth: 1.5))
        }
    }
}

/// The round previous and next buttons beside a date or period.
struct StepButton: View {
    let systemName: String
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(LoopDesign.Palette.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(LoopDesign.Palette.separator))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? LoopDesign.Palette.ink : LoopDesign.Palette.inkMuted.opacity(0.5))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// A message in place of a chart that has nothing to draw, saying why.
struct ChartPlaceholder: View {
    let message: String
    var height: CGFloat = 120

    var body: some View {
        Text(message)
            .font(LoopDesign.Typeface.footnote)
            .foregroundStyle(LoopDesign.Palette.inkMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(LoopDesign.Palette.surfaceSunken.opacity(0.5), in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md))
    }
}
