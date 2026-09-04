import AppKit
import SwiftUI

enum NotchTokens {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let ink = Color.white.opacity(0.96)
    static let secondaryInk = Color.white.opacity(0.72)
    static let tertiaryInk = Color.white.opacity(0.50)
    static let hairline = Color.white.opacity(0.16)
    static let divider = Color.white.opacity(0.10)
    static let glassTint = Color.black.opacity(0.18)
    static let glassTintStrong = Color.black.opacity(0.26)
    static let progress = Color.white.opacity(0.68)
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
                MinimalEdgeTab(state: state, monitor: monitor, edge: state.edge)
                    .frame(width: 7, height: 52)
                    .transition(.opacity)
            case .expanded:
                ExpandedNotchView(state: state, monitor: monitor)
                    .transition(.opacity.combined(with: .move(edge: transitionEdge)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : NotchTokens.spring, value: state.presentation)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("uNotch usage monitor")
    }

    private var transitionEdge: Edge { state.edge == .left ? .leading : .trailing }
    private var edgeAlignment: Alignment { state.edge == .left ? .leading : .trailing }
}

private struct MinimalEdgeTab: View {
    @ObservedObject var state: NotchState
    @ObservedObject var monitor: UsageMonitor
    let edge: ScreenEdge

    var body: some View {
        ZStack {
            GlassEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            Color.white.opacity(0.035)

            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 15)
                .blur(radius: 0.25)
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
            NotchTokens.glassTintStrong

            VStack(spacing: 10) {
                ForEach(MonitorSource.allCases) { source in
                    SourceRingButton(
                        source: source,
                        remaining: monitor.remainingFraction(for: source),
                        isSelected: source == monitor.snapshot.source,
                        action: { monitor.select(source) }
                    )
                }
            }
            .padding(.vertical, 11)
        }
        .clipShape(EdgeRailShape(edge: edge, radius: 24))
        .overlay {
            EdgeRailShape(edge: edge, radius: 24)
                .strokeBorder(NotchTokens.hairline, lineWidth: 1)
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

private struct SourceRingButton: View {
    let source: MonitorSource
    let remaining: Double?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: remaining ?? 0)
                    .stroke(
                        NotchTokens.progress.opacity(isSelected ? 1 : 0.58),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.09) : Color.black.opacity(0.08))
                    .padding(6)
                CompanyLogo(source: source)
                    .frame(width: 17, height: 17)
            }
            .frame(width: 36, height: 36)

            Text(percentText)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchTokens.secondaryInk)
        }
        .frame(width: 50, height: 56)
        .background(
            Color.white.opacity(isSelected ? 0.055 : 0),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
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

    var body: some View {
        HStack(spacing: 8) {
            if state.edge == .left {
                rail
                flyout
            } else {
                flyout
                rail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: state.edge == .left ? .leading : .trailing)
    }

    private var rail: some View {
        ProviderRailView(state: state, monitor: monitor, edge: state.edge)
            .frame(width: 58, height: 220)
    }

    private var flyout: some View {
        UsageFlyoutView(state: state, monitor: monitor)
            .frame(width: 292, height: monitor.snapshot.limits.count > 1 ? 172 : 132)
    }
}

private struct UsageFlyoutView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        ZStack {
            GlassEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            NotchTokens.glassTint

            VStack(alignment: .leading, spacing: 0) {
                header
                usageLimits
                    .padding(.top, 12)
            }
            .padding(.leading, state.edge == .left ? 24 : 16)
            .padding(.trailing, state.edge == .right ? 24 : 16)
            .padding(.vertical, 14)
        }
        .clipShape(CalloutBubbleShape(pointerEdge: state.edge))
        .overlay {
            CalloutBubbleShape(pointerEdge: state.edge)
                .stroke(NotchTokens.hairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 7, y: 3)
        .accessibilityLabel("\(monitor.snapshot.source.name) usage details")
    }

    private var header: some View {
        HStack(spacing: 9) {
            CompanyLogo(source: monitor.snapshot.source)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(monitor.snapshot.source.name) usage")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTokens.ink)
                Text(headerDetail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTokens.secondaryInk)
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
                .foregroundStyle(NotchTokens.secondaryInk)
                Capsule()
                    .fill(Color.white.opacity(0.10))
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
                    .foregroundStyle(NotchTokens.secondaryInk)
                Spacer()
                Text("\(limit.remainingPercent)% remaining")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NotchTokens.ink)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(NotchTokens.progress)
                        .frame(width: max(5, proxy.size.width * limit.remainingFraction))
                        .animation(.easeOut(duration: 0.28), value: limit.remainingFraction)
                }
            }
            .frame(height: 6)

            if let resetText = limit.resetText {
                Text(resetText)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(NotchTokens.tertiaryInk)
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
                .foregroundStyle(NotchTokens.secondaryInk)
                .frame(width: 26, height: 24)
                .background(Color.white.opacity(0.07), in: Circle())
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
                    .foregroundStyle(NotchTokens.ink)
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
        let radius: CGFloat = 15
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
