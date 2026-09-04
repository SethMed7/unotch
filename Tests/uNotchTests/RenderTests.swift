import AppKit
import SwiftUI
import XCTest
@testable import uNotch

@MainActor
final class RenderTests: XCTestCase {
    func testExpandedHUDRendersAtExpectedSize() throws {
        let monitor = UsageMonitor()
        let state = NotchState(monitor: monitor)
        state.edge = .left
        state.isExpanded = true

        let renderer = ImageRenderer(
            content: NotchRootView(state: state)
                .frame(width: 358, height: 220)
                .background(Color(red: 0.03, green: 0.08, blue: 0.10))
        )
        renderer.scale = 2

        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 716)
        XCTAssertEqual(image.height, 440)

        if let outputPath = ProcessInfo.processInfo.environment["UNOTCH_SNAPSHOT"] {
            let representation = NSBitmapImageRep(cgImage: image)
            try representation.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outputPath))
        }
    }
}
