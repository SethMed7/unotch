import AppKit
import SwiftUI

enum HUDMetrics {
    static let idleTab = CGSize(width: 7, height: 52)
    static let railWidth: CGFloat = 58
    static let railTopPadding: CGFloat = 11
    static let ringRowHeight: CGFloat = 56
    static let ringRowSpacing: CGFloat = 10
    static let railFooterHeight: CGFloat = 42
    static let calloutWidth: CGFloat = 292
    static let usageCalloutHeight: CGFloat = 132
    static let usageCalloutTallHeight: CGFloat = 172
    static let settingsCalloutHeight: CGFloat = 188
    static let gap: CGFloat = 8

    /// The rail only holds the providers that are installed, so it shrinks with them:
    /// 252 pt for three, 186 for two, 120 for one.
    static func railHeight(providerCount: Int) -> CGFloat {
        let count = CGFloat(max(providerCount, 1))
        return railTopPadding
            + count * ringRowHeight
            + (count - 1) * ringRowSpacing
            + railTopPadding
            + railFooterHeight
    }

    /// The panel must hold the rail and the tallest callout (settings), whichever is taller.
    static func expandedSize(providerCount: Int) -> CGSize {
        CGSize(
            width: railWidth + gap + calloutWidth,
            height: max(railHeight(providerCount: providerCount), settingsCalloutHeight)
        )
    }
}

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var monitor: UsageMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: NotchState) {
        self.state = state
        self.monitor = state.monitor
    }

    var body: some View {
        Group {
            switch state.presentation {
            case .idle:
                MinimalEdgeTab(state: state, edge: state.edge)
                    .frame(width: HUDMetrics.idleTab.width, height: HUDMetrics.idleTab.height)
                    .transition(.opacity)
            case .expanded:
                ExpandedNotchView(state: state, monitor: monitor)
                    .transition(.opacity.combined(with: .move(edge: transitionEdge)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment)
        .animation(reduceMotion ? Brand.fade : Brand.spring, value: state.presentation)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("uNotch usage monitor")
    }

    private var transitionEdge: Edge { state.edge == .left ? .leading : .trailing }
    private var edgeAlignment: Alignment { state.edge == .left ? .leading : .trailing }
}

private struct MinimalEdgeTab: View {
    @ObservedObject var state: NotchState
    let edge: ScreenEdge

    var body: some View {
        ZStack {
            GlassEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            Brand.idleWash

            VStack(spacing: 4) {
                // The status point from the mark: the one mint element on the idle cue.
                Circle()
                    .fill(Brand.mint)
                    .frame(width: 2.5, height: 2.5)
                Capsule()
                    .fill(Brand.paper.opacity(0.22))
                    .frame(width: 1, height: 15)
                    .blur(radius: 0.25)
            }
            .offset(x: edge == .left ? 2.2 : -2.2)
        }
        .clipShape(EdgePressureShape(edge: edge))
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .accessibilityLabel("Usage monitor")
        .accessibilityHint("Hover briefly to reveal usage. Drag to reposition.")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { state.dragChanged($0.translation) }
            .onEnded { _ in state.dragEnded() }
    }
}

private struct ProviderRailView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var monitor: UsageMonitor
    let edge: ScreenEdge

    var body: some View {
        ZStack {
            GlassEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            Brand.glassTintStrong

            VStack(spacing: 0) {
                VStack(spacing: HUDMetrics.ringRowSpacing) {
                    ForEach(monitor.sources) { source in
                        SourceRingButton(
                            source: source,
                            remaining: monitor.remainingFraction(for: source),
                            isSelected: source == monitor.snapshot.source && !state.isSettingsOpen,
                            action: {
                                state.isSettingsOpen = false
                                monitor.select(source)
                            }
                        )
                    }
                }
                .padding(.top, HUDMetrics.railTopPadding)

                Spacer(minLength: 0)

                SettingsDockButton(state: state)
                    .frame(height: HUDMetrics.railFooterHeight)
            }
        }
        .clipShape(EdgeRailShape(edge: edge, radius: Brand.Radius.rail))
        .overlay {
            EdgeRailShape(edge: edge, radius: Brand.Radius.rail)
                .strokeBorder(Brand.hairline, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .help("Drag to reposition")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { state.dragChanged($0.translation) }
            .onEnded { _ in state.dragEnded() }
    }
}

/// The gear that surfaces when the pointer is near the bottom of the HUD.
private struct SettingsDockButton: View {
    @ObservedObject var state: NotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var isRevealed: Bool { state.isPointerNearBottom || state.isSettingsOpen }

    var body: some View {
        Button {
            state.toggleSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.isSettingsOpen || isHovering ? Brand.ink : Brand.ink2)
                .rotationEffect(.degrees(state.isSettingsOpen ? 30 : 0))
                .frame(width: 28, height: 28)
                .background(
                    state.isSettingsOpen ? Brand.hairline : Brand.divider,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .opacity(isRevealed ? 1 : 0)
        .allowsHitTesting(isRevealed)
        .animation(reduceMotion ? Brand.fade : Brand.spring, value: isRevealed)
        .animation(Brand.fade, value: state.isSettingsOpen)
        .help(state.isSettingsOpen ? "Back to usage" : "Settings")
        .accessibilityLabel("Settings")
        .accessibilityHidden(!isRevealed)
    }
}

private struct SourceRingButton: View {
    let source: MonitorSource
    let remaining: Double?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Brand.paper.opacity(0.10), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: remaining ?? 0)
                    .stroke(
                        isSelected ? Brand.mint : Brand.paper.opacity(0.58),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(Brand.fill, value: remaining)
                Circle()
                    .fill(isSelected ? Brand.paper.opacity(0.09) : Color.black.opacity(0.08))
                    .padding(6)
                CompanyLogo(source: source)
                    .frame(width: 17, height: 17)
            }
            .frame(width: 36, height: 36)

            Text(percentText)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Brand.ink2)
        }
        .frame(width: 50, height: HUDMetrics.ringRowHeight)
        .background(
            Brand.paper.opacity(isSelected ? 0.055 : 0),
            in: RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { action() }
        }
        .help("Show \(source.name) usage")
        .accessibilityLabel("\(source.name), \(percentText) remaining")
    }

    private var percentText: String {
        remaining.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }
}

private struct ExpandedNotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var monitor: UsageMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: HUDMetrics.gap) {
            if state.edge == .left {
                rail
                flyout
            } else {
                flyout
                rail
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: state.edge == .left ? .topLeading : .topTrailing
        )
    }

    private var railHeight: CGFloat {
        HUDMetrics.railHeight(providerCount: monitor.sources.count)
    }

    private var calloutHeight: CGFloat {
        if state.isSettingsOpen { return HUDMetrics.settingsCalloutHeight }
        return monitor.snapshot.limits.count > 1
            ? HUDMetrics.usageCalloutTallHeight
            : HUDMetrics.usageCalloutHeight
    }

    private var rail: some View {
        ProviderRailView(state: state, monitor: monitor, edge: state.edge)
            .frame(width: HUDMetrics.railWidth, height: railHeight)
            .animation(reduceMotion ? Brand.fade : Brand.spring, value: monitor.sources.count)
    }

    @ViewBuilder
    private var flyout: some View {
        Group {
            if state.isSettingsOpen {
                SettingsFlyoutView(state: state)
                    .frame(width: HUDMetrics.calloutWidth, height: HUDMetrics.settingsCalloutHeight)
                    .transition(.opacity)
            } else {
                UsageFlyoutView(state: state, monitor: monitor)
                    .frame(width: HUDMetrics.calloutWidth, height: calloutHeight)
                    .transition(.opacity)
            }
        }
        // Centre the callout on the rail so its pointer lands inside it; a callout taller
        // than a short rail simply shares the rail's top edge.
        .offset(y: max(0, (railHeight - calloutHeight) / 2))
        .animation(reduceMotion ? Brand.fade : Brand.spring, value: state.isSettingsOpen)
    }
}

/// Shared glass callout chrome for the usage and settings sections.
private struct CalloutSurface<Content: View>: View {
    let edge: ScreenEdge
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            GlassEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            Brand.glassTint

            content()
                .padding(.leading, edge == .left ? 24 : 16)
                .padding(.trailing, edge == .right ? 24 : 16)
                .padding(.vertical, 14)
        }
        .clipShape(CalloutBubbleShape(pointerEdge: edge))
        .overlay {
            CalloutBubbleShape(pointerEdge: edge)
                .stroke(Brand.hairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 7, y: 3)
    }
}

private struct UsageFlyoutView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        CalloutSurface(edge: state.edge) {
            VStack(alignment: .leading, spacing: 0) {
                header
                usageLimits
                    .padding(.top, 12)
            }
        }
        .accessibilityLabel("\(monitor.snapshot.source.name) usage details")
    }

    private var header: some View {
        HStack(spacing: 9) {
            CompanyLogo(source: monitor.snapshot.source)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(monitor.snapshot.source.name) usage")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.ink)
                Text(headerDetail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Brand.ink2)
                    .lineLimit(1)
            }

            Spacer()

            RefreshButton(
                isRefreshing: monitor.snapshot.state == .refreshing,
                action: monitor.refresh
            )
        }
    }

    @ViewBuilder
    private var usageLimits: some View {
        if monitor.snapshot.limits.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Plan usage")
                    Spacer()
                    Text(remainingText)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brand.ink2)
                Capsule()
                    .fill(Brand.paper.opacity(0.10))
                    .frame(height: 7)
            }
        } else {
            VStack(alignment: .leading, spacing: 11) {
                ForEach(monitor.snapshot.limits) { limit in
                    UsageLimitRow(limit: limit)
                }
            }
        }
    }

    private var remainingText: String {
        if let percent = monitor.snapshot.remainingPercent {
            return "\(percent)% remaining"
        }
        if monitor.snapshot.state == .refreshing { return "Reading CLI…" }
        return "Unavailable"
    }

    private var headerDetail: String {
        if let message = monitor.snapshot.statusMessage { return message }
        if monitor.snapshot.state == .refreshing {
            return monitor.snapshot.updatedAt == nil ? "Reading local CLI…" : "Refreshing from CLI…"
        }
        if let updatedAt = monitor.snapshot.updatedAt {
            return "Updated \(updatedAt.formatted(.relative(presentation: .named)))"
        }
        return "Waiting for local CLI"
    }
}

private struct UsageLimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.ink2)
                Spacer()
                Text("\(limit.remainingPercent)% remaining")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Brand.ink)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.paper.opacity(0.12))
                    Capsule()
                        .fill(Brand.mint)
                        .frame(width: max(5, proxy.size.width * limit.remainingFraction))
                        .animation(Brand.fill, value: limit.remainingFraction)
                }
            }
            .frame(height: 6)

            if let resetText = limit.resetText {
                Text(resetText)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Brand.ink3)
                    .lineLimit(1)
            }
        }
    }
}

private struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Brand.ink2)
                .frame(width: 26, height: 24)
                .background(Brand.paper.opacity(0.07), in: Circle())
                .contentShape(Circle())
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing
                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                        : .default,
                    value: isRefreshing
                )
        }
        .buttonStyle(.plain)
        .help("Refresh usage")
        .accessibilityLabel("Refresh usage")
    }
}

// MARK: - Settings section

private struct SettingsFlyoutView: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var updater: AppUpdater

    init(state: NotchState) {
        self.state = state
        self.updater = state.updater
    }

    var body: some View {
        CalloutSurface(edge: state.edge) {
            VStack(alignment: .leading, spacing: 0) {
                header
                SettingsRow(label: "Side") {
                    EdgeSegment(edge: $state.edge)
                }
                .padding(.top, 12)
                SettingsRow(label: "Position") {
                    DragGrip(state: state)
                }
                .padding(.top, 8)

                Rectangle()
                    .fill(Brand.divider)
                    .frame(height: 1)
                    .padding(.vertical, 10)

                HStack(spacing: 8) {
                    HUDButton(
                        title: updater.phase.label,
                        style: .primary,
                        isBusy: updater.phase.isBusy,
                        action: updater.updateAndRestart
                    )
                    HUDButton(title: "Quit", style: .ghost, isBusy: false) {
                        NSApplication.shared.terminate(nil)
                    }
                    .frame(width: 58)
                }
            }
        }
        .accessibilityLabel("uNotch settings")
    }

    private var header: some View {
        HStack(spacing: 9) {
            BrandMark()
                .frame(width: 20, height: 20)
            Text(AppInfo.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.ink)
            Spacer()
            Text(AppInfo.version)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Brand.ink3)
                .accessibilityLabel("Version \(AppInfo.version)")
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brand.ink2)
                .frame(width: 52, alignment: .leading)
            Spacer(minLength: 0)
            control()
        }
        .frame(height: 26)
    }
}

private struct EdgeSegment: View {
    @Binding var edge: ScreenEdge

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ScreenEdge.allCases) { option in
                Button {
                    edge = option
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(edge == option ? Brand.ink : Brand.ink2)
                        .frame(width: 54, height: 22)
                        .background(
                            edge == option ? Brand.hairline : Color.clear,
                            in: RoundedRectangle(cornerRadius: Brand.Radius.control - 2, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(edge == option ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Brand.divider, in: RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous))
        .animation(Brand.fade, value: edge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screen side")
    }
}

private struct DragGrip: View {
    @ObservedObject var state: NotchState
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            GripGlyph()
                .frame(width: 8, height: 12)
            Text(isDragging ? "Moving…" : "Drag to move")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brand.ink2)
        }
        .frame(width: 114, height: 26)
        .background(
            isDragging ? Brand.hairline : Brand.divider,
            in: RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    isDragging = true
                    state.dragChanged(value.translation)
                }
                .onEnded { _ in
                    isDragging = false
                    state.dragEnded()
                }
        )
        .help("Drag to move uNotch anywhere on the screen edge")
        .accessibilityLabel("Drag handle")
        .accessibilityHint("Drag to move the monitor. Release near either edge to dock it.")
    }
}

private struct GripGlyph: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Brand.ink3).frame(width: 2.5, height: 2.5)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HUDButton: View {
    enum Style { case primary, ghost }

    let title: String
    let style: Style
    let isBusy: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .padding(.horizontal, 8)
                .background(background, in: RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { isHovering = $0 }
        .animation(Brand.fade, value: isHovering)
    }

    private var foreground: Color {
        switch style {
        case .primary: Brand.charcoal
        case .ghost: isHovering ? Brand.ink : Brand.ink2
        }
    }

    private var background: Color {
        switch style {
        case .primary:
            isBusy ? Brand.mint.opacity(0.6) : (isHovering ? Brand.paper : Brand.mint)
        case .ghost:
            isHovering ? Brand.hairline : Brand.divider
        }
    }
}

// MARK: - Shared pieces

private struct CompanyLogo: View {
    let source: MonitorSource

    var body: some View {
        Group {
            if let image = OfficialBrandAssets.image(for: source) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: source.symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Brand.ink)
            }
        }
        .accessibilityHidden(true)
    }
}

private enum OfficialBrandAssets {
    private static let claude = appIcon(at: "/Applications/Claude.app")
    private static let codex = NSImage(
        contentsOfFile: "/Applications/ChatGPT.app/Contents/Resources/icon-codex-light.png"
    ) ?? appIcon(at: "/Applications/ChatGPT.app")
    private static let cursor = appIcon(at: "/Applications/Cursor.app")

    static func image(for source: MonitorSource) -> NSImage? {
        switch source {
        case .claude: claude
        case .codex: codex
        case .cursor: cursor
        }
    }

    private static func appIcon(at path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

private struct EdgePressureShape: Shape {
    let edge: ScreenEdge

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if edge == .left {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY),
                control1: CGPoint(x: rect.minX + 0.5, y: rect.minY + rect.height * 0.28),
                control2: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.20)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control1: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.20),
                control2: CGPoint(x: rect.minX + 0.5, y: rect.maxY - rect.height * 0.28)
            )
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.midY),
                control1: CGPoint(x: rect.maxX - 0.5, y: rect.minY + rect.height * 0.28),
                control2: CGPoint(x: rect.minX, y: rect.midY - rect.height * 0.20)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.20),
                control2: CGPoint(x: rect.maxX - 0.5, y: rect.maxY - rect.height * 0.28)
            )
        }

        path.closeSubpath()
        return path
    }
}

struct EdgeRailShape: InsettableShape {
    let edge: ScreenEdge
    let radius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let r = min(radius, rect.height / 2, rect.width / 2)
        var path = Path()

        if edge == .left {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> EdgeRailShape {
        EdgeRailShape(edge: edge, radius: radius, insetAmount: insetAmount + amount)
    }
}

private struct CalloutBubbleShape: Shape {
    let pointerEdge: ScreenEdge

    func path(in rect: CGRect) -> Path {
        let arrow: CGFloat = 10
        let radius = Brand.Radius.callout
        let body = pointerEdge == .left
            ? CGRect(x: rect.minX + arrow, y: rect.minY, width: rect.width - arrow, height: rect.height)
            : CGRect(x: rect.minX, y: rect.minY, width: rect.width - arrow, height: rect.height)
        let middle = rect.midY
        var path = Path()

        if pointerEdge == .left {
            path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
            path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + radius), control: CGPoint(x: body.maxX, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: body.maxX - radius, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
            path.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - radius), control: CGPoint(x: body.minX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX, y: middle + 9))
            path.addLine(to: CGPoint(x: rect.minX, y: middle))
            path.addLine(to: CGPoint(x: body.minX, y: middle - 9))
            path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
            path.addQuadCurve(to: CGPoint(x: body.minX + radius, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        } else {
            path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
            path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + radius), control: CGPoint(x: body.maxX, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: middle - 9))
            path.addLine(to: CGPoint(x: rect.maxX, y: middle))
            path.addLine(to: CGPoint(x: body.maxX, y: middle + 9))
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: body.maxX - radius, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
            path.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - radius), control: CGPoint(x: body.minX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
            path.addQuadCurve(to: CGPoint(x: body.minX + radius, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        }

        path.closeSubpath()
        return path
    }
}

struct GlassEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
