import AppKit
import Foundation
import Security

/// User-initiated update. Nothing here runs on a timer or at launch.
///
/// Flow: read the latest GitHub release → compare versions → download the
/// arm64 DMG → verify the mounted app is signed by the same Team ID as the
/// running app and passes Gatekeeper → swap bundles → relaunch.
@MainActor
final class AppUpdater: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case downloading
        case installing
        case restarting
        case failed(String)

        var label: String {
            switch self {
            case .idle: "Update & Restart"
            case .checking: "Checking…"
            case .downloading: "Downloading…"
            case .installing: "Installing…"
            case .restarting: "Restarting…"
            case .failed(let message): message
            }
        }

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .installing, .restarting: true
            default: false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle

    private let releaseSource: any ReleaseSource

    init(releaseSource: any ReleaseSource = GitHubReleaseSource()) {
        self.releaseSource = releaseSource
    }

    func updateAndRestart() {
        guard !phase.isBusy else { return }
        Task { await run() }
    }

    private func run() async {
        phase = .checking
        do {
            let release = try await releaseSource.latestRelease()
            let current = AppInfo.version

            guard let bundleURL = AppInfo.appBundleURL else {
                // `swift run` build: nothing to install, just relaunch the executable.
                phase = .restarting
                AppRelauncher.relaunch(executable: Bundle.main.executableURL)
                return
            }

            guard ReleaseVersion.isNewer(release.version, than: current) else {
                phase = .restarting
                AppRelauncher.relaunch(bundle: bundleURL)
                return
            }

            guard let asset = release.assets.first(where: { $0.name.hasSuffix("-arm64.dmg") }) else {
                throw UpdateError("Release has no macOS installer")
            }

            phase = .downloading
            let dmg = try await releaseSource.download(asset)
            defer { try? FileManager.default.removeItem(at: dmg) }

            phase = .installing
            try await Task.detached(priority: .userInitiated) {
                try ReleaseInstaller.install(dmg: dmg, replacing: bundleURL)
            }.value

            phase = .restarting
            AppRelauncher.relaunch(bundle: bundleURL)
        } catch {
            phase = .failed((error as? UpdateError)?.message ?? "Couldn't update")
            try? await Task.sleep(for: .seconds(4))
            if case .failed = phase { phase = .idle }
        }
    }
}

struct UpdateError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

struct Release: Equatable, Sendable {
    struct Asset: Equatable, Sendable {
        let name: String
        let url: URL
    }

    let version: String
    let assets: [Asset]
}

protocol ReleaseSource: Sendable {
    func latestRelease() async throws -> Release
    func download(_ asset: Release.Asset) async throws -> URL
}

struct GitHubReleaseSource: ReleaseSource {
    private var endpoint: URL {
        URL(string: "https://api.github.com/repos/\(AppInfo.repositoryOwner)/\(AppInfo.repositoryName)/releases/latest")!
    }

    func latestRelease() async throws -> Release {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("Couldn't reach GitHub releases")
        }
        return try ReleaseVersion.parseGitHub(data)
    }

    func download(_ asset: Release.Asset) async throws -> URL {
        var request = URLRequest(url: asset.url)
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120

        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("Download failed")
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("app.unotch.utility.update-\(UUID().uuidString).dmg")
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

enum ReleaseVersion {
    static func parseGitHub(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadUrl: URL
            }
            let tagName: String
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw UpdateError("Unexpected release data")
        }
        return Release(
            version: payload.tagName,
            assets: payload.assets.map { Release.Asset(name: $0.name, url: $0.browserDownloadUrl) }
        )
    }

    /// "v1.2.0-beta" → [1, 2, 0]. Anything that doesn't start with digits (e.g. "dev") → [].
    static func components(_ version: String) -> [Int] {
        let parts = version
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "v" || $0 == "V" })
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return [] }
        return parts.compactMap { $0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let l = index < lhs.count ? lhs[index] : 0
            let r = index < rhs.count ? rhs[index] : 0
            if l != r { return l > r }
        }
        return false
    }
}

enum ReleaseInstaller {
    static func install(dmg: URL, replacing installed: URL) throws {
        guard let ownTeam = CodeIdentity.teamIdentifier(of: installed) else {
            throw UpdateError("Updates need the signed release build")
        }

        let mountPoint = try mount(dmg)
        defer { detach(mountPoint) }

        let candidate = mountPoint.appendingPathComponent("\(AppInfo.name).app")
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw UpdateError("Installer is missing \(AppInfo.name).app")
        }
        guard CodeIdentity.teamIdentifier(of: candidate) == ownTeam else {
            throw UpdateError("Update isn't signed by the same developer")
        }
        guard CodeIdentity.passesGatekeeper(candidate) else {
            throw UpdateError("Update failed Gatekeeper assessment")
        }

        let fm = FileManager.default
        let parent = installed.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(".\(AppInfo.name).app.updating")
        let previous = parent.appendingPathComponent(".\(AppInfo.name).app.previous")
        try? fm.removeItem(at: staged)
        try? fm.removeItem(at: previous)

        do {
            try fm.copyItem(at: candidate, to: staged)
            try fm.moveItem(at: installed, to: previous)
            try fm.moveItem(at: staged, to: installed)
            try? fm.removeItem(at: previous)
        } catch {
            try? fm.removeItem(at: staged)
            if !fm.fileExists(atPath: installed.path), fm.fileExists(atPath: previous.path) {
                try? fm.moveItem(at: previous, to: installed)
            }
            throw UpdateError("Couldn't write to \(parent.lastPathComponent)")
        }
    }

    private static func mount(_ dmg: URL) throws -> URL {
        guard let output = try? Shell.run(
            "/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-readonly", "-noverify", "-plist", dmg.path],
            timeout: 60
        ) else {
            throw UpdateError("Couldn't open the installer")
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw UpdateError("Couldn't open the installer")
        }
        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    private static func detach(_ mountPoint: URL) {
        _ = try? Shell.run("/usr/bin/hdiutil", ["detach", "-quiet", mountPoint.path], timeout: 30)
    }
}

enum CodeIdentity {
    static func teamIdentifier(of bundle: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        let validity = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, validity, nil) == errSecSuccess else {
            return nil
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func passesGatekeeper(_ bundle: URL) -> Bool {
        (try? Shell.run("/usr/sbin/spctl", ["--assess", "--type", "execute", bundle.path], timeout: 30)) != nil
    }
}

enum AppRelauncher {
    /// Waits for this process to exit, then reopens the bundle. The helper is a
    /// plain `sh` child so it survives our termination.
    static func relaunch(bundle: URL) {
        spawn("sleep 1; /usr/bin/open \"$0\"", bundle.path)
        NSApplication.shared.terminate(nil)
    }

    static func relaunch(executable: URL?) {
        guard let executable else {
            NSApplication.shared.terminate(nil)
            return
        }
        spawn("sleep 1; exec \"$0\"", executable.path)
        NSApplication.shared.terminate(nil)
    }

    private static func spawn(_ script: String, _ argument: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, argument]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

enum Shell {
    /// Runs a fixed-argument system tool. Throws on non-zero exit; stderr is discarded.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> Data {
        try ProcessRunner.run(executable: executable, arguments: arguments, timeout: timeout)
    }
}
