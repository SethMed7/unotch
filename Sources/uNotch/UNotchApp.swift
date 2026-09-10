import AppKit
import SwiftUI

@main
struct UNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit uNotch") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windowManager: SideNotchWindowManager?
    private var statusItem: NSStatusItem?
    private var monitor: UsageMonitor?
    private var state: NotchState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let monitor = UsageMonitor()
        let state = NotchState(monitor: monitor)
        self.monitor = monitor
        self.state = state
        windowManager = SideNotchWindowManager(state: state)
        windowManager?.show()
        configureStatusItem()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarLogo.makeImage()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "uNotch usage"
        item.button?.setAccessibilityLabel("uNotch usage monitor")

        let menu = NSMenu(title: "uNotch")
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildStatusMenu(menu)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        for source in monitor?.sources ?? MonitorSource.allCases {
            let value = monitor?.remainingFraction(for: source).map {
                "\(Int(($0 * 100).rounded()))% remaining"
            } ?? "Waiting for CLI"
            let item = NSMenuItem(title: "\(source.name)  ·  \(value)", action: nil, keyEquivalent: "")
            item.image = StatusMenuBrandAssets.image(for: source)
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(
            title: "Refresh Usage",
            action: #selector(refreshUsage),
            keyEquivalent: "r"
        )
        refresh.target = self
        refresh.isEnabled = true
        menu.addItem(refresh)

        let edgeItem = NSMenuItem(title: "Screen Edge", action: nil, keyEquivalent: "")
        let edgeMenu = NSMenu(title: "Screen Edge")
        for edge in ScreenEdge.allCases {
            let item = NSMenuItem(
                title: edge.label,
                action: #selector(selectEdge(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = edge.rawValue
            item.state = state?.edge == edge ? .on : .off
            item.isEnabled = true
            edgeMenu.addItem(item)
        }
        edgeItem.submenu = edgeMenu
        edgeItem.isEnabled = true
        menu.addItem(edgeItem)

        menu.addItem(.separator())
        let update = NSMenuItem(
            title: state?.updater.phase.label ?? "Update & Restart",
            action: #selector(updateAndRestart),
            keyEquivalent: ""
        )
        update.target = self
        update.isEnabled = !(state?.updater.phase.isBusy ?? false)
        menu.addItem(update)

        let version = NSMenuItem(title: "\(AppInfo.name) \(AppInfo.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit uNotch",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)
    }

    @objc private func refreshUsage() {
        monitor?.refreshAll()
    }

    @objc private func selectEdge(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let edge = ScreenEdge(rawValue: rawValue) else { return }
        state?.edge = edge
    }

    @objc private func updateAndRestart() {
        state?.updater.updateAndRestart()
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}

/// The shared screen-and-notch paths as a template image that macOS tints.
private enum MenuBarLogo {
    static func makeImage() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(max(1.25, 64 * side / 1024))
            context.addPath(BrandMarkShape().path(in: rect).cgPath)
            context.strokePath()
            context.addPath(BrandNotchShape().path(in: rect).cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

private enum StatusMenuBrandAssets {
    static func image(for source: MonitorSource) -> NSImage? {
        let path: String
        switch source {
        case .claude: path = "/Applications/Claude.app"
        case .codex: path = "/Applications/ChatGPT.app"
        case .cursor: path = "/Applications/Cursor.app"
        }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
