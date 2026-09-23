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
    /// Each limit row after the first: its meter, caption, and the gap above it.
    static let usageLimitRowHeight: CGFloat = 40
    static let usageCalloutTallHeight: CGFloat = 172
    static let usageCalloutTripleHeight: CGFloat = 212
    /// The most rows one provider shows: Claude's 5-hour, weekly, and model limits
    /// plus its Resets available row.
    static let usageLimitMaxCount = 4
    /// The subscription strip (34 pt of cells in a 2 pt well) plus the space above it.
    static let subscriptionStripHeight: CGFloat = 38
    static let subscriptionStripSpacing: CGFloat = 10
    static let settingsCalloutHeight: CGFloat = 188
    static let gap: CGFloat = 8
    /// The ring sits 3 pt into its row, so its centre is 3 + 18 from the row's top.
    static let ringCenterOffset: CGFloat = 21
    /// Where the pointer leaves the callout when nothing forces it lower: level with the
    /// title row, so the bubble reads as coming out of the ring beside its header.
    static let calloutPointerRestY: CGFloat = 32
    /// Half the pointer's height along the edge; the pointer keeps clear of the corners.
    static let calloutPointerHalfHeight: CGFloat = 9
    /// A ring, a limit, and the idle cue turn red at or below this remaining fraction.
    static let lowRemainingCutoff = 0.10

    static func isLowRemaining(_ remaining: Double?) -> Bool {
        guard let remaining else { return false }
        return Int((remaining * 100).rounded()) <= Int((lowRemainingCutoff * 100).rounded())
    }

    /// Mint on the ring being looked at, red at or below 10% whether or not it is,
    /// pale otherwise.
    static func ringAccent(remaining: Double?, selected: Bool) -> Color {
        if isLowRemaining(remaining) { return Brand.alert }
        return selected ? Brand.mint : Brand.paper.opacity(0.58)
    }

    /// A ring at or below 10% is a full circle. Trimming to remaining would hide
    /// the colour at 0% — the case that needs the warning most.
    static func ringFill(remaining: Double?) -> CGFloat {
        if isLowRemaining(remaining) { return 1 }
        return remaining ?? 0
    }

    /// Centre of the ring at `index`, measured from the top of the rail.
    static func ringCenterY(index: Int) -> CGFloat {
        railTopPadding + CGFloat(index) * (ringRowHeight + ringRowSpacing) + ringCenterOffset
    }

    /// Centre of the settings gear, measured from the top of the rail.
    static func gearCenterY(providerCount: Int) -> CGFloat {
        railHeight(providerCount: providerCount) - railFooterHeight / 2
    }

    /// Places a callout so its pointer lands on `anchorY` (a ring or the gear). The
    /// callout's top is the anchor less the pointer's rest position, held inside the
    /// panel; the pointer then sits wherever that leaves the anchor, kept off the corners.
    static func calloutPlacement(
        anchorY: CGFloat,
        calloutHeight: CGFloat,
        panelHeight: CGFloat
    ) -> (offset: CGFloat, pointerY: CGFloat) {
        let offset = min(max(anchorY - calloutPointerRestY, 0), max(panelHeight - calloutHeight, 0))
        let margin = Brand.Radius.callout + calloutPointerHalfHeight
        let pointerY = min(max(anchorY - offset, margin), calloutHeight - margin)
        return (offset, pointerY)
    }

    /// The rail only holds the providers that are installed, so it sizes to them:
    /// 384 pt for five (Grok Bot under Cursor, then Antigravity), 318 for four, 252 for
    /// three, 186 for two, 120 for one.
    static func railHeight(providerCount: Int) -> CGFloat {
        let count = CGFloat(max(providerCount, 1))
        return railTopPadding
            + count * ringRowHeight
            + (count - 1) * ringRowSpacing
            + railTopPadding
            + railFooterHeight
    }

    /// One row's worth per limit. A provider with more than one signed-in subscription
    /// gets the strip under the title, so its callout is taller by the strip's row. A
    /// Resets available row with a Use reset control needs a little more for the
    /// taller action chip.
    static func usageCalloutHeight(
        forLimitCount count: Int,
        subscriptionCount: Int = 1,
        showsRedeemAction: Bool = false
    ) -> CGFloat {
        let base = usageCalloutHeight + CGFloat(max(count, 1) - 1) * usageLimitRowHeight
        let strip = subscriptionCount > 1 ? subscriptionStripHeight + subscriptionStripSpacing : 0
        let redeem: CGFloat = showsRedeemAction ? 10 : 0
        return base + strip + redeem
    }

    /// The tallest usage callout: every row Claude can show under a subscription strip,
    /// with room for a Use reset control.
    static var usageCalloutMaxHeight: CGFloat {
        usageCalloutHeight(
            forLimitCount: usageLimitMaxCount,
            subscriptionCount: 2,
            showsRedeemAction: true
        )
    }

    /// The panel must hold the rail and the tallest callout, whichever is taller. It is
    /// sized for the tallest usage callout up front so a subscription that signs in while
    /// the HUD is open never runs past the panel's edge.
    static func expandedSize(providerCount: Int) -> CGSize {
        CGSize(
            width: railWidth + gap + calloutWidth,
            height: max(
                railHeight(providerCount: providerCount),
                settingsCalloutHeight,
                usageCalloutMaxHeight
            )
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
                MinimalEdgeTab(state: state, monitor: monitor, edge: state.edge)
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
    @ObservedObject var monitor: UsageMonitor
    let edge: ScreenEdge

    var body: some View {
        ZStack {
            GlassEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            if monitor.hasUnseenLowUsage {
                // The whole cue, once, until the HUD is opened.
                Brand.alert
            } else {
                Brand.idleWash
                VStack(spacing: 4) {
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
                    ForEach(monitor.providers) { provider in
                        SourceRingButton(
                            provider: provider,
                            remaining: monitor.remainingFraction(for: provider),
                            isSelected: provider == monitor.selectedProvider && !state.isSettingsOpen,
                            action: {
                                state.isSettingsOpen = false
                                monitor.select(provider)
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

/// The gear in the rail's footer. Hovering it opens settings, the way hovering a ring
/// opens that provider; hovering a ring again is the way back. The gear turns mint
/// while hovered or open — no disc, no card.
private struct SettingsDockButton: View {
    @ObservedObject var state: NotchState
    @State private var isHovering = false

    var body: some View {
        Button {
            state.openSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.isSettingsOpen || isHovering ? Brand.mint : Brand.ink2)
                .rotationEffect(.degrees(state.isSettingsOpen ? 30 : 0))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHoverAlways { hovering in
            isHovering = hovering
            if hovering { state.openSettings() }
        }
        .animation(Brand.fade, value: state.isSettingsOpen)
        .animation(Brand.fade, value: isHovering)
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}

private struct SourceRingButton: View {
    let provider: Provider
    let remaining: Double?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Brand.paper.opacity(0.10), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: HUDMetrics.ringFill(remaining: remaining))
                    .stroke(
                        HUDMetrics.ringAccent(remaining: remaining, selected: isSelected),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(Brand.fill, value: remaining)
                Circle()
                    .fill(isSelected ? Brand.paper.opacity(0.09) : Color.black.opacity(0.08))
                    .padding(6)
                CompanyLogo(provider: provider)
                    .frame(width: 17, height: 17)
            }
            .frame(width: 36, height: 36)

            // The number matches the ring: mint while looked at, red at or below 10%.
            Text(percentText)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(HUDMetrics.ringAccent(remaining: remaining, selected: isSelected))
        }
        // Pinned to the row's top so the ring's centre is a known distance down
        // (`HUDMetrics.ringCenterOffset`), where the callout's pointer aims.
        .padding(.top, HUDMetrics.ringCenterOffset - 18)
        .frame(width: 50, height: HUDMetrics.ringRowHeight, alignment: .top)
        .animation(Brand.fade, value: isSelected)
        .contentShape(Rectangle())
        .onHoverAlways { hovering in
            if hovering { action() }
        }
        .help("Show \(provider.name) usage")
        .accessibilityLabel("\(provider.name), \(percentText) remaining")
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
        HUDMetrics.railHeight(providerCount: monitor.providers.count)
    }

    private var calloutHeight: CGFloat {
        if state.isSettingsOpen { return HUDMetrics.settingsCalloutHeight }
        return HUDMetrics.usageCalloutHeight(
            forLimitCount: monitor.snapshot.limits.count,
            subscriptionCount: monitor.subscriptions(for: monitor.selectedProvider).count,
            showsRedeemAction: monitor.canRedeemAvailableReset || monitor.isRedeemingReset
        )
    }

    private var rail: some View {
        ProviderRailView(state: state, monitor: monitor, edge: state.edge)
            .frame(width: HUDMetrics.railWidth, height: railHeight)
            .animation(reduceMotion ? Brand.fade : Brand.spring, value: monitor.providers.count)
    }

    /// What the callout comes out of: the selected ring, or the gear while settings is open.
    private var anchorY: CGFloat {
        if state.isSettingsOpen {
            return HUDMetrics.gearCenterY(providerCount: monitor.providers.count)
        }
        let index = monitor.providers.firstIndex(of: monitor.selectedProvider) ?? 0
        return HUDMetrics.ringCenterY(index: index)
    }

    private var placement: (offset: CGFloat, pointerY: CGFloat) {
        HUDMetrics.calloutPlacement(
            anchorY: anchorY,
            calloutHeight: calloutHeight,
            panelHeight: HUDMetrics.expandedSize(providerCount: monitor.providers.count).height
        )
    }

    @ViewBuilder
    private var flyout: some View {
        let placement = placement
        Group {
            if state.isSettingsOpen {
                SettingsFlyoutView(state: state, pointerY: placement.pointerY)
                    .frame(width: HUDMetrics.calloutWidth, height: HUDMetrics.settingsCalloutHeight)
                    .transition(.opacity)
            } else {
                UsageFlyoutView(state: state, monitor: monitor, pointerY: placement.pointerY)
                    .frame(width: HUDMetrics.calloutWidth, height: calloutHeight)
                    .transition(.opacity)
            }
        }
        // The callout hangs from the ring it belongs to: its title row is level with the
        // ring and the pointer aims at the ring's centre, sliding down to the gear when
        // settings opens. Switching providers moves it at once, like a tooltip following
        // the pointer; only the settings toggle is animated. Within one provider the
        // top edge stays put while the body grows or shrinks, so the subscription strip
        // does not move under a pointer that is hovering it.
        .offset(y: placement.offset)
        .animation(reduceMotion ? Brand.fade : Brand.spring, value: state.isSettingsOpen)
    }
}

/// Shared glass callout chrome for the usage and settings sections.
private struct CalloutSurface<Content: View>: View {
    let edge: ScreenEdge
    /// Where along the rail-facing edge the pointer sits, from the callout's top.
    let pointerY: CGFloat
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
        .clipShape(CalloutBubbleShape(pointerEdge: edge, pointerY: pointerY))
        .overlay {
            CalloutBubbleShape(pointerEdge: edge, pointerY: pointerY)
                .stroke(Brand.hairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 7, y: 3)
    }
}

private struct UsageFlyoutView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var monitor: UsageMonitor
    let pointerY: CGFloat

    var body: some View {
        CalloutSurface(edge: state.edge, pointerY: pointerY) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if subscriptions.count > 1 {
                    SubscriptionStrip(
                        subscriptions: subscriptions,
                        selected: monitor.snapshot.source,
                        remainingPercent: { monitor.snapshot(for: $0).remainingPercent },
                        isFavorite: monitor.isFavorite,
                        look: { monitor.select(subscription: $0) },
                        favorite: monitor.toggleFavorite
                    )
                    .frame(height: HUDMetrics.subscriptionStripHeight)
                    .padding(.top, HUDMetrics.subscriptionStripSpacing)
                }
                usageLimits
                    .padding(.top, 12)
            }
        }
        .accessibilityLabel("\(monitor.snapshot.source.name) usage details")
    }

    private var subscriptions: [MonitorSource] {
        monitor.subscriptions(for: monitor.selectedProvider)
    }

    /// The title names the provider. Which subscription the limits belong to is the
    /// strip's job, so the title never has to make room for it.
    private var header: some View {
        HStack(spacing: 9) {
            CompanyLogo(provider: monitor.selectedProvider)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(monitor.selectedProvider.name) usage")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                    .frame(height: 18)
                Text(headerDetail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Brand.ink2)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

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
                    UsageLimitRow(
                        limit: limit,
                        isRedeeming: monitor.isRedeemingReset,
                        onRedeem: limit.canRedeem
                            ? { monitor.redeemAvailableReset() }
                            : nil
                    )
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
        if monitor.isRedeemingReset { return "Using reset…" }
        if let message = monitor.resetStatusMessage { return message }
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

/// The signed-in subscriptions of one provider as a segmented strip: every cell the
/// same width, name over percent, so five read as cleanly as two. Hovering a cell
/// looks at it, the same way hovering a ring looks at a provider; clicking one makes
/// it the favourite the provider opens on.
private struct SubscriptionStrip: View {
    let subscriptions: [MonitorSource]
    let selected: MonitorSource
    let remainingPercent: (MonitorSource) -> Int?
    let isFavorite: (MonitorSource) -> Bool
    let look: (MonitorSource) -> Void
    let favorite: (MonitorSource) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(subscriptions) { source in
                SubscriptionCell(
                    source: source,
                    remainingPercent: remainingPercent(source),
                    isSelected: source == selected,
                    isFavorite: isFavorite(source),
                    look: { look(source) },
                    favorite: { favorite(source) }
                )
            }
        }
        .padding(2)
        .background(Brand.divider, in: RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous))
        .animation(Brand.fade, value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(selected.provider.name) subscriptions")
    }
}

private struct SubscriptionCell: View {
    let source: MonitorSource
    let remainingPercent: Int?
    let isSelected: Bool
    let isFavorite: Bool
    let look: () -> Void
    let favorite: () -> Void

    var body: some View {
        Button(action: favorite) {
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(isSelected ? Brand.ink : Brand.ink2)
                            .accessibilityHidden(true)
                    }
                    // Folder names run long and the cell is as wide as its share of the
                    // strip, so the name clips before the number does. The tooltip and
                    // the menu bar menu carry the full name.
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? Brand.ink : Brand.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(percentText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isLow ? Brand.alert : (isSelected ? Brand.mint : Brand.ink2))
            }
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isSelected ? Brand.hairline : Color.clear,
                in: RoundedRectangle(cornerRadius: Brand.Radius.control - 2, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHoverAlways { hovering in
            if hovering { look() }
        }
        .help(isFavorite
            ? "\(source.name) opens first. Click to clear."
            : "Hovering shows \(source.name). Click to make it open first.")
        .accessibilityLabel("\(source.name), \(percentText) remaining\(isFavorite ? ", favourite" : "")")
        .accessibilityHint(isFavorite ? "Clears the favourite" : "Makes this the favourite")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var label: String {
        source.accountLabel ?? source.provider.name
    }

    private var percentText: String {
        remainingPercent.map { "\($0)%" } ?? "—"
    }

    private var isLow: Bool {
        remainingPercent.map { $0 <= Int((HUDMetrics.lowRemainingCutoff * 100).rounded()) } ?? false
    }
}

private struct UsageLimitRow: View {
    let limit: UsageLimit
    var isRedeeming: Bool = false
    var onRedeem: (() -> Void)? = nil

    private var isLow: Bool {
        limit.showsMeter && HUDMetrics.isLowRemaining(limit.remainingFraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.ink2)
                Spacer()
                if let onRedeem {
                    RedeemResetButton(isBusy: isRedeeming, action: onRedeem)
                } else {
                    Text(limit.valueText ?? "\(limit.remainingPercent)% remaining")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isLow ? Brand.alert : Brand.ink)
                }
            }

            if limit.showsMeter {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Brand.paper.opacity(0.12))
                        Capsule()
                            .fill(isLow ? Brand.alert : Brand.mint)
                            .frame(width: max(5, proxy.size.width * limit.remainingFraction))
                            .animation(Brand.fill, value: limit.remainingFraction)
                    }
                }
                .frame(height: 6)
            }

            if let valueText = limit.valueText, onRedeem != nil {
                Text(valueText)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Brand.ink3)
                    .lineLimit(1)
            } else if let resetText = limit.resetText {
                Text(resetText)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Brand.ink3)
                    .lineLimit(1)
            }
        }
    }
}

private struct RedeemResetButton: View {
    let isBusy: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(isBusy ? "Using…" : "Use reset")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Brand.charcoal)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    isBusy ? Brand.mint.opacity(0.6) : (isHovering ? Brand.paper : Brand.mint),
                    in: RoundedRectangle(cornerRadius: Brand.Radius.control, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help("Use one available reset on this subscription")
        .accessibilityLabel(isBusy ? "Using reset" : "Use reset")
        .onHoverAlways { isHovering = $0 }
        .animation(Brand.fade, value: isHovering)
    }
}

private struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The still arrow and the turning one are separate views that crossfade.
            // Hovering down the rail flips `isRefreshing` several times a second, and
            // a single rotated arrow would spring back to zero on every flip.
            ZStack {
                if isRefreshing {
                    TurningArrow()
                        .transition(.opacity)
                } else {
                    RefreshGlyph()
                        .transition(.opacity)
                }
            }
            .frame(width: 26, height: 24)
            .background(Brand.paper.opacity(0.07), in: Circle())
            .contentShape(Circle())
            .animation(Brand.fade, value: isRefreshing)
        }
        .buttonStyle(.plain)
        .help("Refresh usage")
        .accessibilityLabel(isRefreshing ? "Refreshing usage" : "Refresh usage")
    }
}

private struct RefreshGlyph: View {
    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Brand.ink2)
    }
}

/// The arrow turning while a read is in flight. Its angle is read off the clock, so
/// there is no animation to interrupt, unwind, or leave running when the read ends.
private struct TurningArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let period: TimeInterval = 0.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let turn = elapsed.truncatingRemainder(dividingBy: Self.period) / Self.period
            RefreshGlyph()
                .rotationEffect(.degrees(reduceMotion ? 0 : turn * 360))
        }
    }
}

// MARK: - Settings section

private struct SettingsFlyoutView: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var updater: AppUpdater
    let pointerY: CGFloat

    init(state: NotchState, pointerY: CGFloat) {
        self.state = state
        self.updater = state.updater
        self.pointerY = pointerY
    }

    var body: some View {
        CalloutSurface(edge: state.edge, pointerY: pointerY) {
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
        .onHoverAlways { hovering in
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
        .onHoverAlways { isHovering = $0 }
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
    let provider: Provider

    var body: some View {
        Group {
            if let image = OfficialBrandAssets.image(for: provider) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    // App icons carry a margin inside their tile; a bare mark gets the
                    // same so it reads at the same size.
                    .scaleEffect(provider == .antigravity ? 0.82 : 1)
            } else {
                Image(systemName: provider.symbol)
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
    private static let grokBot = appIcon(at: "/Applications/Grok Bot.app")
    /// The CLI is all Antigravity needs, so its mark ships with uNotch.
    private static let antigravity = BundledProviderLogos.antigravity

    static func image(for provider: Provider) -> NSImage? {
        switch provider {
        case .claude: claude
        case .codex: codex
        case .cursor: cursor
        case .grokBot: grokBot
        case .antigravity: antigravity
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
    /// The pointer's centre along the rail-facing edge, from the top. Kept off the
    /// rounded corners whatever is passed in.
    var pointerY: CGFloat

    var animatableData: CGFloat {
        get { pointerY }
        set { pointerY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let arrow: CGFloat = 10
        let radius = Brand.Radius.callout
        let half = HUDMetrics.calloutPointerHalfHeight
        let body = pointerEdge == .left
            ? CGRect(x: rect.minX + arrow, y: rect.minY, width: rect.width - arrow, height: rect.height)
            : CGRect(x: rect.minX, y: rect.minY, width: rect.width - arrow, height: rect.height)
        let middle = rect.minY + min(max(pointerY, radius + half), rect.height - radius - half)
        var path = Path()

        if pointerEdge == .left {
            path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
            path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + radius), control: CGPoint(x: body.maxX, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: body.maxX - radius, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
            path.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - radius), control: CGPoint(x: body.minX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX, y: middle + half))
            path.addLine(to: CGPoint(x: rect.minX, y: middle))
            path.addLine(to: CGPoint(x: body.minX, y: middle - half))
            path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
            path.addQuadCurve(to: CGPoint(x: body.minX + radius, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        } else {
            path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
            path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + radius), control: CGPoint(x: body.maxX, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: middle - half))
            path.addLine(to: CGPoint(x: rect.maxX, y: middle))
            path.addLine(to: CGPoint(x: body.maxX, y: middle + half))
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

extension View {
    /// Hover that works while another app is active. SwiftUI's `onHover` tracks only
    /// while uNotch is the active app, and a menu bar app hovered from someone else's
    /// window never is; this tracks with `.activeAlways`, the way the panel itself does.
    func onHoverAlways(_ action: @escaping (Bool) -> Void) -> some View {
        background(AlwaysHoverTracker(onChange: action))
    }
}

private struct AlwaysHoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class HoverTrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var trackingAreaReference: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingAreaReference = area
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }

        /// Clicks belong to the SwiftUI control this sits behind.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
