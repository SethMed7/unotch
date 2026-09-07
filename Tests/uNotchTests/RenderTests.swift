import AppKit
import SwiftUI
import XCTest
@testable import uNotch

@MainActor
final class RenderTests: XCTestCase {
    func testExpandedHUDRendersAtExpectedSize() throws {
        let image = try render(settingsOpen: false)
        XCTAssertEqual(image.width, Int(HUDMetrics.expandedSize.width) * 2)
        XCTAssertEqual(image.height, Int(HUDMetrics.expandedSize.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_SNAPSHOT")
    }

    func testSettingsSectionRendersAtExpectedSize() throws {
        let image = try render(settingsOpen: true)
        XCTAssertEqual(image.width, Int(HUDMetrics.expandedSize.width) * 2)
        XCTAssertEqual(image.height, Int(HUDMetrics.expandedSize.height) * 2)
        try writeSnapshotIfRequested(image, variable: "UNOTCH_SETTINGS_SNAPSHOT")
    }

    private func render(settingsOpen: Bool) throws -> CGImage {
        let monitor = UsageMonitor()
        let state = NotchState(monitor: monitor)
        state.edge = .left
        state.isExpanded = true
        state.isPointerNearBottom = true
        state.isSettingsOpen = settingsOpen

        let renderer = ImageRenderer(
            content: NotchRootView(state: state)
                .frame(width: HUDMetrics.expandedSize.width, height: HUDMetrics.expandedSize.height)
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
