import Foundation

protocol UsageFetching: Sendable {
    func fetchUsage(for source: MonitorSource) async -> UsageSnapshot
    /// Providers whose local CLI is present on this Mac. Cheap file checks; safe to call often.
    func installedSources() -> [MonitorSource]
}

actor CLIUsageFetcher: UsageFetching {
    func fetchUsage(for source: MonitorSource) async -> UsageSnapshot {
        await Task.detached(priority: .utility) {
            switch source {
            case .codex:
                return Self.fetchCodexUsage()
            case .claude:
                return Self.fetchClaudeUsage()
            case .cursor:
                return Self.fetchCursorUsage()
            }
        }.value
    }

    nonisolated func installedSources() -> [MonitorSource] {
        MonitorSource.allCases.filter { Self.executablePath(for: $0) != nil }
    }

    /// One place that knows where each provider's CLI lives.
    static func executablePath(for source: MonitorSource) -> String? {
        let home = NSString(string: "~").expandingTildeInPath
        switch source {
        case .codex:
            return executable(named: "codex", preferredPaths: [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex"
            ])
        case .claude:
            return executable(named: "claude", preferredPaths: [
                "\(home)/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"
            ])
        case .cursor:
            return executable(named: "agent", preferredPaths: [
                "\(home)/.local/bin/agent",
                "/opt/homebrew/bin/agent",
                "/usr/local/bin/agent"
            ])
        }
    }

    private static func fetchCodexUsage() -> UsageSnapshot {
        guard let executable = executablePath(for: .codex) else {
            return .unavailable(source: .codex, message: "Codex CLI not found")
        }

        do {
            let output = try ProcessRunner.codexRateLimits(executable: executable)
            return try UsageCLIParser.codex(output)
        } catch {
            return .failed(source: .codex, message: userFacingMessage(error))
        }
    }

    private static func fetchClaudeUsage() -> UsageSnapshot {
        guard let executable = executablePath(for: .claude) else {
            return .unavailable(source: .claude, message: "Claude CLI not found")
        }

        do {
            let output = try ProcessRunner.run(
                executable: executable,
                arguments: [
                    "-p", "/usage",
                    "--output-format", "json",
                    "--no-session-persistence"
                ],
                timeout: 12
            )
            return try UsageCLIParser.claude(output)
        } catch {
            return .failed(source: .claude, message: userFacingMessage(error))
        }
    }

    private static func fetchCursorUsage() -> UsageSnapshot {
        guard let executable = executablePath(for: .cursor) else {
            return .unavailable(source: .cursor, message: "Cursor Agent CLI not found")
        }

        do {
            let statusOutput = try ProcessRunner.run(
                executable: executable,
                arguments: ["status", "--format", "json"],
                timeout: 8
            )
            guard UsageCLIParser.cursorIsAuthenticated(statusOutput) else {
                return .unavailable(source: .cursor, message: "Sign in with Cursor Agent CLI")
            }
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
                return .unavailable(source: .cursor, message: "Background terminal helper unavailable")
            }

            let output = try ProcessRunner.cursorUsage(executable: executable)
            return try UsageCLIParser.cursor(output)
        } catch {
            return .failed(source: .cursor, message: userFacingMessage(error))
        }
    }

    private static func executable(named name: String, preferredPaths: [String]) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = preferredPaths + [
            "\(home)/.local/bin/\(name)",
            "\(home)/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func userFacingMessage(_ error: Error) -> String {
        if let error = error as? CLIUsageError {
            return error.message
        }
        return "CLI usage read failed"
    }
}

enum UsageCLIParser {
    static func codex(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        let response = data
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(CodexResponse.self, from: Data($0)) }
            .first { $0.id == 2 }

        guard let result = response?.result else {
            throw CLIUsageError("Codex CLI returned no rate-limit data")
        }

        let limits = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
        let windows = [limits.primary, limits.secondary]
            .compactMap { $0 }
            .sorted { ($0.windowDurationMins ?? 0) < ($1.windowDurationMins ?? 0) }
        guard !windows.isEmpty else {
            throw CLIUsageError("Codex CLI returned no usage window")
        }

        return UsageSnapshot(
            source: .codex,
            limits: windows.map { window in
                UsageLimit(
                    label: label(forWindowMinutes: window.windowDurationMins),
                    remainingFraction: 1 - (Double(window.usedPercent) / 100),
                    resetAt: window.resetsAt.map {
                        Date(timeIntervalSince1970: TimeInterval($0))
                    }
                )
            },
            updatedAt: now,
            state: .loaded
        )
    }

    static func claude(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let envelope = try JSONDecoder().decode(ClaudeUsageEnvelope.self, from: data)
        let lines = envelope.result.split(separator: "\n").map(String.init)
        let limits = [
            parseClaudeLine(lines, prefix: "Current session:", label: "5-hour limit"),
            parseClaudeLine(lines, prefix: "Current week (all models):", label: "Weekly limit")
        ].compactMap { $0 }
        guard !limits.isEmpty else {
            throw CLIUsageError("Claude CLI returned no plan limits")
        }

        return UsageSnapshot(
            source: .claude,
            limits: limits,
            updatedAt: now,
            state: .loaded
        )
    }

    static func cursor(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let text = String(decoding: data, as: UTF8.self)
        guard let match = firstMatch(in: text, pattern: #"Included\s+([0-9]+)% used"#),
              let used = Int(match) else {
            throw CLIUsageError("Cursor Agent returned no included usage")
        }

        let reset = firstMatch(
            in: text,
            pattern: #"Resets\s+([A-Za-z]{3}\s+[0-9]{1,2})"#
        ).map { "Resets \($0)" }
        return UsageSnapshot(
            source: .cursor,
            limits: [
                UsageLimit(
                    label: "Monthly included",
                    remainingFraction: 1 - (Double(used) / 100),
                    resetDescription: reset
                )
            ],
            updatedAt: now,
            state: .loaded
        )
    }

    static func cursorIsAuthenticated(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(CursorStatus.self, from: data).isAuthenticated) == true
    }

    private static func parseClaudeLine(
        _ lines: [String],
        prefix: String,
        label: String
    ) -> UsageLimit? {
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }),
              let usedRange = line.range(of: #"[0-9]+% used"#, options: .regularExpression),
              let used = Int(line[usedRange].dropLast("% used".count)) else {
            return nil
        }

        let resetDescription = line.range(of: "resets ").map {
            "Resets " + line[$0.upperBound...]
        }
        return UsageLimit(
            label: label,
            remainingFraction: 1 - (Double(used) / 100),
            resetDescription: resetDescription
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func label(forWindowMinutes minutes: Int?) -> String {
        guard let minutes else { return "Plan limit" }
        if minutes >= 7 * 24 * 60 { return "Weekly limit" }
        if minutes >= 24 * 60 { return "\(minutes / (24 * 60))-day limit" }
        if minutes >= 60 { return "\(minutes / 60)-hour limit" }
        return "\(minutes)-minute limit"
    }
}

private struct CodexResponse: Decodable {
    let id: Int?
    let result: CodexRateLimitResult?
}

private struct CodexRateLimitResult: Decodable {
    let rateLimits: CodexRateLimits
    let rateLimitsByLimitId: [String: CodexRateLimits]?
}

private struct CodexRateLimits: Decodable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int?
}

private struct ClaudeUsageEnvelope: Decodable {
    let result: String
}

private struct CursorStatus: Decodable {
    let isAuthenticated: Bool
}

struct CLIUsageError: Error, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        additionalEnvironment: [String: String] = [:]
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let didExit = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !additionalEnvironment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(
                additionalEnvironment,
                uniquingKeysWith: { _, newValue in newValue }
            )
        }
        process.standardOutput = output
        // Provider CLIs can include account identifiers and local paths in error
        // output. uNotch never needs that detail, so do not capture or surface it.
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in didExit.signal() }

        try process.run()
        guard didExit.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            throw CLIUsageError("CLI usage read timed out")
        }

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw CLIUsageError("CLI usage read failed")
        }
        return stdout
    }

    static func codexRateLimits(executable: String) throws -> Data {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let capture = OutputCapture(targetResponseID: 2)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty || capture.append(data) {
                capture.signal()
            }
        }

        try process.run()
        let requests = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"unotch","title":"uNotch","version":"\#(AppInfo.version)"}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"account/rateLimits/read","params":null}"#
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(requests.utf8))

        guard capture.wait(timeout: 10) else {
            output.fileHandleForReading.readabilityHandler = nil
            input.fileHandleForWriting.closeFile()
            process.terminate()
            throw CLIUsageError("Codex CLI usage read timed out")
        }

        output.fileHandleForReading.readabilityHandler = nil
        input.fileHandleForWriting.closeFile()
        if process.isRunning {
            process.terminate()
        }
        guard !capture.exceededLimit else {
            throw CLIUsageError("Codex CLI returned too much data")
        }
        return capture.data
    }

    static func cursorUsage(executable: String) throws -> Data {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("app.unotch.utility.cursor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let script = """
        log_user 1
        set timeout 12
        set agent_path $env(UNOTCH_CURSOR_AGENT)
        set workspace $env(UNOTCH_CURSOR_WORKSPACE)
        spawn -noecho /bin/zsh -c {stty rows 50 columns 200; exec "$1" --workspace "$2" --trust} unotch-agent $agent_path $workspace
        after 1200
        send -- "/usage"
        after 300
        send -- "\\033\\[13;1u"
        expect {
          -re "Esc to close" { }
          timeout { exit 2 }
        }
        send -- "\\033"
        after 150
        """
        return try run(
            executable: "/usr/bin/expect",
            arguments: ["-c", script],
            timeout: 15,
            additionalEnvironment: [
                "UNOTCH_CURSOR_AGENT": executable,
                "UNOTCH_CURSOR_WORKSPACE": workspace.path
            ]
        )
    }
}

private final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let targetResponseID: Int
    private let byteLimit = 1_048_576
    private var storage = Data()
    private var hasSignaled = false
    private var didExceedLimit = false

    init(targetResponseID: Int) {
        self.targetResponseID = targetResponseID
    }

    var data: Data {
        lock.withLock { storage }
    }

    var exceededLimit: Bool {
        lock.withLock { didExceedLimit }
    }

    func append(_ data: Data) -> Bool {
        lock.withLock {
            guard storage.count + data.count <= byteLimit else {
                didExceedLimit = true
                return true
            }
            storage.append(data)
            return storage.split(separator: 0x0A).contains { line in
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                else { return false }
                return object["id"] as? Int == targetResponseID
            }
        }
    }

    func signal() {
        lock.withLock {
            guard !hasSignaled else { return }
            hasSignaled = true
            semaphore.signal()
        }
    }

    func wait(timeout: TimeInterval) -> Bool {
        semaphore.wait(timeout: .now() + timeout) == .success
    }
}
