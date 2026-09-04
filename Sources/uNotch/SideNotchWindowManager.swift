import AppKit
import Combine
import SwiftUI

final class SideNotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SideNotchWindowManager: NSObject {
    private enum Metrics {
        static let idleSize = NSSize(width: 12, height: 60)
        static let expandedSize = NSSize(width: 358, height: 220)
        static let hoverDebounce: TimeInterval = 0.15
        static let exitDebounce: TimeInterval = 0.22
        static let exitSlop: CGFloat = 5
        static let railWidth: CGFloat = 58
        static let placementDefaultsKey = "uNotch.anchorYFraction"
    }

    private let state: NotchState
    private let panel: SideNotchPanel
    private var cancellables = Set<AnyCancellable>()
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var activeScreen: NSScreen?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dragStartFrame: NSRect?
    private var anchorYFraction: CGFloat?
    private var isDragging = false

    init(state: NotchState) {
        self.state = state
        panel = SideNotchPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.idleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        if UserDefaults.standard.object(forKey: Metrics.placementDefaultsKey) != nil {
            anchorYFraction = CGFloat(UserDefaults.standard.double(forKey: Metrics.placementDefaultsKey))
        }

        configurePanel()
        installContent()
        installDragHandling()
        installPointerMonitors()
        observeState()
        observeScreens()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        expandWorkItem?.cancel()
        collapseWorkItem?.cancel()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }

    func show() {
        activeScreen = screenContainingPointer() ?? NSScreen.main ?? NSScreen.screens.first
        positionPanel(animated: false)
        panel.orderFrontRegardless()
    }

    private func configurePanel() {
        // popUpMenuWindow stays over normal apps without entering the shielding-window tier.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.worksWhenModal = true
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
    }

    private func installContent() {
        let rootView = NotchRootView(state: state)
        let hostingView = TrackingHostingView(rootView: rootView)
        hostingView.onPointerEntered = { [weak self] in self?.pointerEntered() }
        hostingView.onPointerExited = { [weak self] in self?.pointerExited() }
        panel.contentView = hostingView
    }

    private func installDragHandling() {
        state.onDragChanged = { [weak self] translation in
            self?.dragPanel(by: translation)
        }
        state.onDragEnded = { [weak self] in
            self?.finishDraggingPanel()
        }
    }

    private func observeState() {
        Publishers.CombineLatest3(
            state.$isPointerInside.removeDuplicates(),
            state.$isExpanded.removeDuplicates(),
            state.$edge.removeDuplicates()
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            self?.positionPanel(animated: true)
        }
        .store(in: &cancellables)
    }

    private func installPointerMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.reconcilePointer(at: NSEvent.mouseLocation)
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.reconcilePointer(at: NSEvent.mouseLocation)
            }
            return event
        }
    }

    private func observeScreens() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationBecameActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        activeScreen = screenContainingPointer() ?? NSScreen.main ?? NSScreen.screens.first
        positionPanel(animated: false)
    }

    @objc private func applicationBecameActive() {
        activeScreen = screenContainingPointer() ?? NSScreen.main ?? activeScreen
        positionPanel(animated: false)
        panel.orderFrontRegardless()
    }

    private func pointerEntered() {
        guard !isDragging else { return }
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        activeScreen = screenContainingPointer() ?? NSScreen.main ?? activeScreen
        state.isPointerInside = true

        guard !state.isExpanded, expandWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.state.isPointerInside else { return }
            self.expandWorkItem = nil
            self.state.monitor.refresh()
            self.state.isExpanded = true
        }
        expandWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.hoverDebounce, execute: workItem)
    }

    private func pointerExited() {
        guard !isDragging else { return }
        expandWorkItem?.cancel()
        expandWorkItem = nil
        guard collapseWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil

            // Resizing a tracked NSPanel can synthesize mouseExited even when the
            // pointer never left. Re-check against the settled panel frame before
            // changing presentation state so expansion cannot oscillate.
            let pointer = NSEvent.mouseLocation
            if self.panel.frame.insetBy(
                dx: -Metrics.exitSlop,
                dy: -Metrics.exitSlop
            ).contains(pointer) {
                return
            }

            self.state.isPointerInside = false
            self.state.isExpanded = false
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.exitDebounce, execute: workItem)
    }

    private func reconcilePointer(at point: NSPoint) {
        guard !isDragging else { return }

        let isInside = panel.frame.insetBy(
            dx: -Metrics.exitSlop,
            dy: -Metrics.exitSlop
        ).contains(point)

        if isInside {
            pointerEntered()
            updateHoveredProvider(at: point)
        } else if state.isPointerInside {
            hoveredSource = nil
            pointerExited()
        }
    }

    private var hoveredSource: MonitorSource?

    private func updateHoveredProvider(at screenPoint: NSPoint) {
        guard state.isExpanded else {
            hoveredSource = nil
            return
        }

        let local = panel.convertPoint(fromScreen: screenPoint)
        let railMinX = state.edge == .left ? 0 : panel.frame.width - Metrics.railWidth
        guard local.x >= railMinX, local.x <= railMinX + Metrics.railWidth,
              local.y >= 0, local.y <= panel.frame.height else {
            hoveredSource = nil
            return
        }

        let distanceFromTop = panel.frame.height - local.y
        guard let source = ProviderHoverGeometry.source(
            distanceFromTop: distanceFromTop,
            railHeight: panel.frame.height
        ) else { return }
        guard source != hoveredSource else { return }

        hoveredSource = source
        state.monitor.refresh(source)
    }

    private func dragPanel(by translation: CGSize) {
        if dragStartFrame == nil {
            dragStartFrame = panel.frame
            isDragging = true
            expandWorkItem?.cancel()
            collapseWorkItem?.cancel()
            expandWorkItem = nil
            collapseWorkItem = nil
        }
        guard let dragStartFrame else { return }

        panel.setFrameOrigin(NSPoint(
            x: dragStartFrame.minX + translation.width,
            y: dragStartFrame.minY - translation.height
        ))
    }

    private func finishDraggingPanel() {
        guard isDragging else { return }
        isDragging = false
        dragStartFrame = nil

        let screen = screenContainingPanel() ?? screenContainingPointer() ?? NSScreen.main
        guard let screen else { return }
        activeScreen = screen

        let newEdge: ScreenEdge = panel.frame.midX <= screen.frame.midX ? .left : .right
        let fraction = (panel.frame.maxY - screen.frame.minY) / screen.frame.height
        anchorYFraction = min(max(fraction, 0.08), 0.98)
        UserDefaults.standard.set(Double(anchorYFraction ?? 0.9), forKey: Metrics.placementDefaultsKey)
        state.edge = newEdge
        positionPanel(animated: false)

        let pointerIsInside = panel.frame.insetBy(dx: -Metrics.exitSlop, dy: -Metrics.exitSlop)
            .contains(NSEvent.mouseLocation)
        state.isPointerInside = pointerIsInside
        if pointerIsInside {
            pointerEntered()
        } else {
            state.isExpanded = false
        }
    }

    private func positionPanel(animated _: Bool) {
        guard let screen = activeScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let size: NSSize
        switch state.presentation {
        case .idle: size = Metrics.idleSize
        case .expanded: size = Metrics.expandedSize
        }

        let screenFrame = screen.frame
        let x = state.edge == .left ? screenFrame.minX : screenFrame.maxX - size.width
        let defaultTopAnchor = min(screen.visibleFrame.maxY, screenFrame.maxY) - 8
        let storedTopAnchor = anchorYFraction.map { screenFrame.minY + screenFrame.height * $0 }
        let topAnchor = min(
            max(storedTopAnchor ?? defaultTopAnchor, screenFrame.minY + size.height + 8),
            screenFrame.maxY - 8
        )
        let y = max(screenFrame.minY + 8, topAnchor - size.height)
        let targetFrame = NSRect(x: x, y: y, width: size.width, height: size.height)

        // Keep AppKit geometry deterministic. SwiftUI animates the visible rail
        // and flyout; animating the NSPanel frame itself causes tracking-area
        // churn and was the source of the hover flicker.
        panel.setFrame(targetFrame, display: true)
    }

    private func screenContainingPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    private func screenContainingPanel() -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(panel.frame).area < rhs.frame.intersection(panel.frame).area
        }
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}

enum ProviderHoverGeometry {
    static func source(distanceFromTop: CGFloat, railHeight: CGFloat) -> MonitorSource? {
        guard railHeight > 0, distanceFromTop >= 0, distanceFromTop <= railHeight else {
            return nil
        }

        let rowHeight = railHeight / CGFloat(MonitorSource.allCases.count)
        let index = min(
            MonitorSource.allCases.count - 1,
            max(0, Int(distanceFromTop / rowHeight))
        )
        return MonitorSource.allCases[index]
    }
}

private final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
    }

}
