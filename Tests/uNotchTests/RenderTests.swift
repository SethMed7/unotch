import AppKit
import SwiftUI
import XCTest
@testable import uNotch

@MainActor
final class RenderTests: XCTestCase {
    func testExpandedHUDRendersAtExpectedSize() throws {
        let size = HUDMetrics.expandedSize(providerCount: 3)
        let image = try render(installed: MonitorSource.allCases, settingsOpen: false)
        XCTAssertEqual(image.width, Int(size.width) * 2)
        XCTAssertEqual(image.height, Int(size.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_SNAPSHOT")
    }

    func testSettingsSectionRendersAtExpectedSize() throws {
        let size = HUDMetrics.expandedSize(providerCount: 3)
        let image = try render(installed: MonitorSource.allCases, settingsOpen: true)
        XCTAssertEqual(image.width, Int(size.width) * 2)
        XCTAssertEqual(image.height, Int(size.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_SETTINGS_SNAPSHOT")
    }

    func testSingleProviderRendersInTheShorterPanel() throws {
        let size = HUDMetrics.expandedSize(providerCount: 1)
        let image = try render(installed: [.claude], settingsOpen: false)
        XCTAssertEqual(image.height, Int(size.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_SINGLE_SNAPSHOT")
    }

    private func render(installed: [MonitorSource], settingsOpen: Bool) throws -> CGImage {
        let monitor = UsageMonitor(fetcher: StubFetcher(installed: installed))
        monitor.detectInstalledSources()
        let state = NotchState(monitor: monitor)
        state.edge = .left
        state.isExpanded = true
        state.isPointerNearBottom = true
        state.isSettingsOpen = settingsOpen

        let size = HUDMetrics.expandedSize(providerCount: monitor.sources.count)
        let renderer = ImageRenderer(
            content: NotchRootView(state: state)
                .frame(width: size.width, height: size.height)
                .background(Color(red: 0.03, green: 0.08, blue: 0.10))
        )
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    private func writeSnapshotIfRequested(_ image: CGImage, variable: String) throws {
        guard let outputPath = ProcessInfo.processInfo.environment[variable] else { return }
        let representation = NSBitmapImageRep(cgImage: image)
        try representation.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outputPath))
    }
}
