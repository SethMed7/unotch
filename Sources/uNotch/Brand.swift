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

/// The screen and side notch use the 1024 grid in `brand/logo/mark.svg`.
/// MenuBarLogo also draws these paths so the template and HUD stay consistent.
struct BrandMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let origin = CGPoint(x: rect.midX - 512 * s, y: rect.midY - 512 * s)
        return Path(roundedRect: CGRect(
            x: origin.x + 176 * s, y: origin.y + 256 * s,
            width: 672 * s, height: 512 * s
        ), cornerRadius: 80 * s)
    }
}

struct BrandNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let ox = rect.midX - 512 * s
        let oy = rect.midY - 512 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        var path = Path()
        path.move(to: p(144, 392))
        path.addLine(to: p(280, 392))
        path.addCurve(to: p(336, 448), control1: p(311, 392), control2: p(336, 417))
        path.addLine(to: p(336, 576))
        path.addCurve(to: p(280, 632), control1: p(336, 607), control2: p(311, 632))
        path.addLine(to: p(144, 632))
        path.closeSubpath()
        return path
    }
}

struct BrandMark: View {
    var ink: Color = Brand.paper
    var notch: Color = Brand.mint

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 1024
            ZStack {
                BrandMarkShape()
                    .stroke(ink, lineWidth: max(64 * s, 1.25))
                BrandNotchShape()
                    .fill(notch)
            }
        }
        .accessibilityHidden(true)
    }
}
