import AppKit
import SwiftUI

/// Brand tokens. Canon: `brand/BRAND.md` + `brand/tokens.json`. Change there first.
enum Brand {
    static let charcoal = Color(red: 0.082, green: 0.098, blue: 0.106) // #15191B
    static let paper = Color(red: 0.957, green: 0.969, blue: 0.965) // #F4F7F6
    static let mint = Color(red: 0.231, green: 0.886, blue: 0.608) // #3BE29B

    /// Ink is paper at opacity so the desktop behind the glass tints the type.
    static let ink = paper.opacity(0.96)
    static let ink2 = paper.opacity(0.72)
    static let ink3 = paper.opacity(0.50)
    static let hairline = paper.opacity(0.16)
    static let divider = paper.opacity(0.10)

    static let glassTint = Color.black.opacity(0.18)
    static let glassTintStrong = Color.black.opacity(0.26)
    static let idleWash = paper.opacity(0.035)

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let fill = Animation.easeOut(duration: 0.28)
    static let fade = Animation.easeOut(duration: 0.12)

    enum Radius {
        static let chip: CGFloat = 6
        static let control: CGFloat = 11
        static let callout: CGFloat = 15
        static let rail: CGFloat = 24
    }
}

/// Bundle facts the UI and updater need. Falls back sensibly under `swift run`.
enum AppInfo {
    static let name = "uNotch"
    static let repositoryOwner = "SethMed7"
    static let repositoryName = "unotch"
    static let repositoryURL = URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// The `.app` bundle when running as an installed app, nil under `swift run`.
    static var appBundleURL: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }
}

/// The brand mark drawn in code so the menu bar, HUD, and icon share one geometry.
/// Coordinates follow the 1024 grid in `brand/logo/mark.svg`.
struct BrandMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let ox = rect.midX - 512 * s
        let oy = rect.midY - 512 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var path = Path()
        path.move(to: p(310, 308))
        path.addLine(to: p(310, 558))
        path.addCurve(to: p(714, 558), control1: p(310, 760), control2: p(714, 760))
        path.addLine(to: p(714, 308))
        return path
    }
}

struct BrandMark: View {
    var ink: Color = Brand.paper
    var point: Color = Brand.mint

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let s = side / 1024
            // Optical floor: below ~48 pt the point and stroke thin out, so clamp them
            // (BRAND.md: "if the point disappears at 16 px, the mark has been drawn wrong").
            let stroke = max(84 * s, 1.6)
            let radius = max(39 * s, 1.4)
            ZStack {
                BrandMarkShape()
                    .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                Circle()
                    .fill(point)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: proxy.size.width / 2 + (714 - 512) * s, y: proxy.size.height / 2 + (256 - 512) * s)
            }
        }
        .accessibilityHidden(true)
    }
}
