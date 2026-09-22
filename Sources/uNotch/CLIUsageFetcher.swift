import Foundation

protocol UsageFetching: Sendable {
    func fetchUsage(for source: MonitorSource) async -> UsageSnapshot
    /// Subscriptions whose local CLI is present on this Mac, including extra sign-ins
    /// of the same CLI. Cheap file checks; safe to call often.
    func installedSources() -> [MonitorSource]
    /// Spends one banked Codex reset credit for this sign-in. Other providers return
    /// `.unsupported`. Callers refresh usage after a conclusive outcome.
    func redeemCodexReset(for source: MonitorSource) async -> CodexResetResult
}

extension UsageFetching {
    func redeemCodexReset(for source: MonitorSource) async -> CodexResetResult {
        .unsupported
    }
}

/// What Codex's `account/rateLimitResetCredit/consume` reported, or why it could not.
enum CodexResetResult: Equatable, Sendable {
    case reset
    case nothingToReset
    case noCredit
    case alreadyRedeemed
    case failed(String)
    case unsupported

    var didConsume: Bool {
        switch self {
        case .reset, .alreadyRedeemed: true
        default: false
        }
    }

    var statusMessage: String? {
        switch self {
        case .reset, .alreadyRedeemed: nil
        case .nothingToReset: "Nothing to reset"
        case .noCredit: "No resets available"
        case .failed(let message): message
        case .unsupported: "Reset is only available for Codex"
        }
    }
}

actor CLIUsageFetcher: UsageFetching {
    func fetchUsage(for source: MonitorSource) async -> UsageSnapshot {
        await Task.detached(priority: .utility) {
            switch source.provider {
            case .codex:
                return Self.fetchCodexUsage(for: source)
            case .claude:
                return Self.fetchClaudeUsage(for: source)
            case .cursor:
                return Self.fetchCursorUsage(for: source)
            case .grokBot:
                return Self.fetchGrokBotUsage(for: source)
            }
        }.value
    }

    func redeemCodexReset(for source: MonitorSource) async -> CodexResetResult {
        guard source.provider == .codex else { return .unsupported }
        return await Task.detached(priority: .utility) {
            Self.redeemCodexReset(for: source)
        }.value
    }

    nonisolated func installedSources() -> [MonitorSource] {
        MonitorSource.defaults
            .filter { Self.executablePath(for: $0.provider) != nil }
            .flatMap { source in
                let extras = Self.configDirectories(for: source.provider).map {
                    MonitorSource(provider: source.provider, configDirectory: $0)
                }
                let accounts = [source] + extras
                // Grok Bot is part of a Cursor plan, so each Cursor sign-in brings its own.
                guard source.provider == .cursor else { return accounts }
                let grok = accounts.map {
                    MonitorSource(provider: .grokBot, configDirectory: $0.configDirectory)
                }
                return accounts + grok
            }
    }

    /// Extra sign-ins of one CLI, e.g. `alias cc-dev='CLAUDE_CONFIG_DIR=~/.claude-dev claude'`,
    /// `CODEX_HOME=~/.codex-work codex`, or `CURSOR_CONFIG_DIR=~/.cursor-agent2`. Everyone
    /// names these differently, so the
    /// folder name means nothing; what marks one is what the CLI leaves inside it.
    /// Looks one level into the home folder and `~/.config`. Only names are checked;
    /// nothing is read.
    static func configDirectories(
        for provider: Provider,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        let manager = FileManager.default
        func has(_ name: String, in folder: URL) -> Bool {
            manager.fileExists(atPath: folder.appendingPathComponent(name).path)
        }

        let isSignIn: (URL) -> Bool
        switch provider {
        case .claude:
            // Claude Code keeps `.claude.json` inside a directory only when
            // `CLAUDE_CONFIG_DIR` points at it; the default keeps it beside `~/.claude`.
            isSignIn = { has(".claude.json", in: $0) }
        case .codex:
            // `auth.json` alone is too common a name (Composer has one), so it must sit
            // beside a name only Codex writes. Generic ones like `sessions` do not count:
            // a wrong guess would have Codex fill a stranger's folder with its databases.
            // `~/.codex` is the default, not an extra.
            let defaultHome = home.appendingPathComponent(".codex").resolvingSymlinksInPath().path
            isSignIn = { folder in
                folder.resolvingSymlinksInPath().path != defaultHome
                    && has("auth.json", in: folder)
                    && ["config.toml", "version.json", "installation_id"]
                        .contains { has($0, in: folder) }
            }
        case .cursor:
            // `cli-config.json` is what Agent writes when `CURSOR_CONFIG_DIR` points here.
            // `~/.cursor` is the default login, not an extra.
            let defaultHome = home.appendingPathComponent(".cursor").resolvingSymlinksInPath().path
            isSignIn = { folder in
                folder.resolvingSymlinksInPath().path != defaultHome
                    && has("cli-config.json", in: folder)
            }
        case .grokBot:
            return []
        }

        let parents = [home, home.appendingPathComponent(".config", isDirectory: true)]
        var found: [String] = []
        for parent in parents {
            let names = ((try? manager.contentsOfDirectory(atPath: parent.path)) ?? []).sorted()
            for name in names where parent != home || !privacyProtectedFolders.contains(name) {
                let folder = parent.appendingPathComponent(name, isDirectory: true)
                guard isSignIn(folder) else { continue }
                // Two aliases can reach one folder through a symlink; it is one sign-in.
                let path = folder.resolvingSymlinksInPath().path
                if !found.contains(path) { found.append(path) }
            }
        }
        return found
    }

    /// macOS asks the user for permission when an app so much as looks inside these.
    /// No one keeps a CLI config there, so they are never touched.
    private static let privacyProtectedFolders: Set<String> = [
        "Applications", "Desktop", "Documents", "Downloads", "Library",
        "Movies", "Music", "Pictures", "Public"
    ]

    /// One place that knows where each provider's CLI lives.
    static func executablePath(for provider: Provider) -> String? {
        let home = NSString(string: "~").expandingTildeInPath
        switch provider {
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
        case .cursor, .grokBot:
            return executable(named: "agent", preferredPaths: [
                "\(home)/.local/bin/agent",
                "/opt/homebrew/bin/agent",
                "/usr/local/bin/agent"
            ])
        }
    }

    private static func fetchCodexUsage(for source: MonitorSource) -> UsageSnapshot {
        guard let executable = executablePath(for: .codex) else {
            return .unavailable(source: source, message: "Codex CLI not found")
        }

        let environment = source.configDirectory.map { ["CODEX_HOME": $0] } ?? [:]
        do {
            let output = try ProcessRunner.codexAppServer(
                executable: executable,
                method: "account/rateLimits/read",
                paramsJSON: "null",
                additionalEnvironment: environment
            )
            return try UsageCLIParser.codex(output, source: source)
        } catch {
            // `codex login status` answers from local files and says it with its exit
            // code: 1 is "not logged in". Worth one quick launch after a failed read.
            if let status = try? ProcessRunner.exitStatus(
                executable: executable,
                arguments: ["login", "status"],
                timeout: 6,
                additionalEnvironment: environment
            ), status == 1 {
                return .unavailable(source: source, message: "Sign in with Codex CLI")
            }
            return .failed(source: source, message: userFacingMessage(error))
        }
    }

    private static func redeemCodexReset(for source: MonitorSource) -> CodexResetResult {
        guard let executable = executablePath(for: .codex) else {
            return .failed("Codex CLI not found")
        }

        let environment = source.configDirectory.map { ["CODEX_HOME": $0] } ?? [:]
        let key = UUID().uuidString
        do {
            let output = try ProcessRunner.codexAppServer(
                executable: executable,
                method: "account/rateLimitResetCredit/consume",
                paramsJSON: #"{"idempotencyKey":"\#(key)"}"#,
                additionalEnvironment: environment
            )
            return try UsageCLIParser.codexReset(output)
        } catch {
            return .failed(userFacingMessage(error))
        }
    }

    private static func fetchClaudeUsage(for source: MonitorSource) -> UsageSnapshot {
        guard let executable = executablePath(for: .claude) else {
            return .unavailable(source: source, message: "Claude CLI not found")
        }

        let environment = source.configDirectory.map { ["CLAUDE_CONFIG_DIR": $0] } ?? [:]
        do {
            let output = try ProcessRunner.run(
                executable: executable,
                arguments: [
                    "-p", "/usage",
                    "--output-format", "json",
                    "--no-session-persistence"
                ],
                timeout: 12,
                additionalEnvironment: environment
            )
            return try UsageCLIParser.claude(output, source: source)
        } catch {
            // A signed-out CLI still answers `/usage`, just with no limits. Only then is
            // it worth a second launch to tell "sign in" apart from a real read failure.
            // `auth status` reports signed-out as JSON on a failing exit.
            if error as? CLIUsageError == UsageCLIParser.noClaudeLimits,
               let status = try? ProcessRunner.run(
                executable: executable,
                arguments: ["auth", "status"],
                timeout: 8,
                additionalEnvironment: environment,
                requiresCleanExit: false
            ), UsageCLIParser.claudeIsSignedOut(status) {
                return .unavailable(source: source, message: "Sign in with Claude Code")
            }
            return .failed(source: source, message: userFacingMessage(error))
        }
    }

    private static func fetchCursorUsage(for source: MonitorSource) -> UsageSnapshot {
        guard executablePath(for: .cursor) != nil else {
            return .unavailable(source: source, message: "Cursor Agent CLI not found")
        }

        // A second folder does not get its own keychain item. Its session is the file
        // store, and `agent status` would only describe the keychain login.
        if source.configDirectory != nil {
            guard let token = cursorExtraToken(for: source) else {
                return .unavailable(source: source, message: "Sign in with Cursor Agent CLI")
            }
            return fetchCursorDashboard(source: source, token: token)
        }

        guard let executable = executablePath(for: .cursor) else {
            return .unavailable(source: source, message: "Cursor Agent CLI not found")
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

            if let token = cursorKeychainToken(),
               let period = try? ProcessRunner.cursorDashboard(
                method: "GetCurrentPeriodUsage",
                token: token
               ),
               let snapshot = try? UsageCLIParser.cursorDashboard(period: period) {
                return snapshot
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

    /// Grok Bot's allowance is Cursor's `GetSandUsageStatus` (Grok Bot's bundle is
    /// `com.anysphere.sand`), read with that Cursor sign-in's token. No token means no
    /// Cursor sign-in; a plan without Grok Bot answers with no included allowance, and
    /// that subscription stays off the strip. The ring stays off the rail until one
    /// sign-in includes it.
    private static func fetchGrokBotUsage(for source: MonitorSource) -> UsageSnapshot {
        guard executablePath(for: .cursor) != nil else {
            return .unavailable(source: source, message: "Cursor Agent CLI not found")
        }
        let token = source.configDirectory == nil
            ? cursorKeychainToken()
            : cursorExtraToken(for: source)
        guard let token else {
            return .unavailable(source: source, message: "Sign in with Cursor Agent CLI")
        }
        do {
            let sand = try ProcessRunner.cursorDashboard(method: "GetSandUsageStatus", token: token)
            return try UsageCLIParser.grokBot(sand, source: source)
        } catch {
            return .failed(source: source, message: userFacingMessage(error))
        }
    }

    /// Usage for one session token. A failed read stays failed: falling through to
    /// `agent /usage` would report the keychain login under this subscription's name.
    private static func fetchCursorDashboard(source: MonitorSource, token: String) -> UsageSnapshot {
        do {
            let period = try ProcessRunner.cursorDashboard(
                method: "GetCurrentPeriodUsage",
                token: token
            )
            return try UsageCLIParser.cursorDashboard(period: period, source: source)
        } catch {
            return .failed(source: source, message: userFacingMessage(error))
        }
    }

    /// The session for a `CURSOR_CONFIG_DIR` folder. People only set that variable;
    /// the folder name is the whole configuration. The token is whatever that
    /// sign-in stored: `auth.json` in the folder, a keychain item named after the
    /// folder, or the default file store when its subject is the folder's auth id.
    /// The Mac's keychain login (`cursor-access-token`) is the default subscription,
    /// never also an extra.
    private static func cursorExtraToken(for source: MonitorSource) -> String? {
        guard let directory = source.configDirectory else { return nil }
        let folder = URL(fileURLWithPath: directory)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let named = cursorKeychainName(forConfigDirectory: directory)
        return cursorSessionToken(
            keychainToken: cursorKeychainToken(),
            directoryToken: cursorFileToken(at: folder.appendingPathComponent("auth.json")),
            defaultFileToken: cursorFileToken(
                at: home.appendingPathComponent(".cursor").appendingPathComponent("auth.json")
            ),
            authId: cursorAuthId(in: folder),
            directoryKeychainToken: named.flatMap {
                cursorKeychainToken(service: $0.service, account: $0.account)
            }
        )
    }

    /// `~/.cursor-agent2` → keychain service `cursor-agent2-access-token`, account
    /// `cursor-agent2-user`. nil for the default `~/.cursor` login.
    static func cursorKeychainName(forConfigDirectory path: String) -> (service: String, account: String)? {
        let folder = URL(fileURLWithPath: path).lastPathComponent
        let name = String(folder.drop { $0 == "." })
        guard !name.isEmpty, name != "cursor" else { return nil }
        return ("\(name)-access-token", "\(name)-user")
    }

    static func cursorSessionToken(
        keychainToken: String?,
        directoryToken: String?,
        defaultFileToken: String?,
        authId: String?,
        directoryKeychainToken: String? = nil
    ) -> String? {
        let keychainSubject = keychainToken.flatMap(cursorTokenSubject)
        func isAnotherAccount(_ token: String) -> Bool {
            guard let subject = cursorTokenSubject(token) else { return keychainToken == nil }
            return subject != keychainSubject
        }

        if let directoryToken {
            return isAnotherAccount(directoryToken) ? directoryToken : nil
        }
        if let directoryKeychainToken {
            return isAnotherAccount(directoryKeychainToken) ? directoryKeychainToken : nil
        }
        guard let defaultFileToken,
              let authId, !authId.isEmpty,
              cursorTokenSubject(defaultFileToken) == authId,
              isAnotherAccount(defaultFileToken) else { return nil }
        return defaultFileToken
    }

    /// `sub` from a Cursor session JWT. nil when the token is not one.
    static func cursorTokenSubject(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = object["sub"] as? String,
              !subject.isEmpty else { return nil }
        return subject
    }

    private static func cursorFileToken(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["accessToken"] as? String else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cursorAuthId(in folder: URL) -> String? {
        let url = folder.appendingPathComponent("cli-config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = object["authInfo"] as? [String: Any],
              let authId = info["authId"] as? String,
              !authId.isEmpty else { return nil }
        return authId
    }

    /// The Cursor Agent CLI stores its default session in the login keychain. Reading
    /// it lets uNotch call the same free dashboard usage RPCs the Agent `/usage`
    /// screen uses, including Grok Bot. The token is never stored.
    private static func cursorKeychainToken(
        service: String = "cursor-access-token",
        account: String = "cursor-user"
    ) -> String? {
        guard let data = try? ProcessRunner.run(
            executable: "/usr/bin/security",
            arguments: [
                "find-generic-password",
                "-s", service,
                "-a", account,
                "-w"
            ],
            timeout: 4
        ) else { return nil }
        let token = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
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
    static let noClaudeLimits = CLIUsageError("Claude CLI returned no plan limits")

    static func codex(
        _ data: Data,
        source: MonitorSource = .codex,
        now: Date = Date()
    ) throws -> UsageSnapshot {
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

        var parsedLimits = windows.map { window in
            UsageLimit(
                label: label(forWindowMinutes: window.windowDurationMins),
                remainingFraction: 1 - (Double(window.usedPercent) / 100),
                resetAt: window.resetsAt.map {
                    Date(timeIntervalSince1970: TimeInterval($0))
                }
            )
        }
        if let count = result.rateLimitResetCredits?.availableCount {
            let text = switch count {
            case 0: "0 resets"
            case 1: "1 available"
            default: "\(count) available"
            }
            parsedLimits.append(
                UsageLimit(
                    label: "Resets available",
                    remainingFraction: count > 0 ? 1 : 0,
                    valueText: text,
                    showsMeter: false,
                    contributesToSummary: false,
                    canRedeem: count > 0
                )
            )
        }

        return UsageSnapshot(
            source: source,
            limits: parsedLimits,
            updatedAt: now,
            state: .loaded
        )
    }

    static func codexReset(_ data: Data) throws -> CodexResetResult {
        let decoder = JSONDecoder()
        let response = data
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(CodexConsumeResponse.self, from: Data($0)) }
            .first { $0.id == 2 }
        if let message = response?.error?.message, !message.isEmpty {
            throw CLIUsageError(message)
        }
        guard let outcome = response?.result?.outcome else {
            throw CLIUsageError("Codex CLI returned no reset outcome")
        }
        switch outcome {
        case "reset": return .reset
        case "nothingToReset": return .nothingToReset
        case "noCredit": return .noCredit
        case "alreadyRedeemed": return .alreadyRedeemed
        default: throw CLIUsageError("Codex CLI returned an unknown reset outcome")
        }
    }

    static func claude(
        _ data: Data,
        source: MonitorSource = .claude,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        let envelope = try JSONDecoder().decode(ClaudeUsageEnvelope.self, from: data)
        let lines = envelope.result.split(separator: "\n").map(String.init)
        let limits = [
            parseClaudeLine(lines, prefix: "Current session:", label: "5-hour limit"),
            parseClaudeLine(
                lines,
                prefix: "Current week (all models):",
                label: "Weekly limit"
            ),
            parseClaudeLine(
                lines,
                prefix: "Current week (Fable):",
                label: "Fable",
                contributesToSummary: false
            )
        ].compactMap { $0 }
        guard !limits.isEmpty else {
            throw noClaudeLimits
        }

        return UsageSnapshot(
            source: source,
            limits: limits,
            updatedAt: now,
            state: .loaded
        )
    }

    static func cursor(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let text = String(decoding: data, as: UTF8.self)
        let reset = firstMatch(
            in: text,
            pattern: #"Resets\s+([A-Za-z]{3}\s+[0-9]{1,2})"#
        ).map { "Resets \($0)" }

        var limits: [UsageLimit] = []
        if let used = firstIntMatch(in: text, pattern: #"Auto[:\s]+([0-9]+)% used"#) {
            limits.append(
                UsageLimit(
                    label: "Cursor Models",
                    remainingFraction: 1 - (Double(used) / 100),
                    resetDescription: reset
                )
            )
        }
        if let used = firstIntMatch(in: text, pattern: #"API[:\s]+([0-9]+)% used"#) {
            limits.append(
                UsageLimit(
                    label: "Other Models",
                    remainingFraction: 1 - (Double(used) / 100),
                    resetDescription: reset,
                    contributesToSummary: false
                )
            )
        }
        if limits.isEmpty, let used = firstIntMatch(in: text, pattern: #"Included\s+([0-9]+)% used"#) {
            limits.append(
                UsageLimit(
                    label: "Monthly included",
                    remainingFraction: 1 - (Double(used) / 100),
                    resetDescription: reset
                )
            )
        }
        guard !limits.isEmpty else {
            throw CLIUsageError("Cursor Agent returned no included usage")
        }

        return UsageSnapshot(
            source: .cursor,
            limits: limits,
            updatedAt: now,
            state: .loaded
        )
    }

    static func cursorDashboard(
        period: Data,
        source: MonitorSource = .cursor,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        guard let root = jsonObject(period),
              let planUsage = root["planUsage"] as? [String: Any] else {
            throw CLIUsageError("Cursor dashboard returned no plan usage")
        }

        let reset = resetDescription(fromMillis: root["billingCycleEnd"])
        var limits: [UsageLimit] = []
        if let used = percentValue(planUsage["autoPercentUsed"]) {
            limits.append(
                UsageLimit(
                    label: "Cursor Models",
                    remainingFraction: 1 - used / 100,
                    resetDescription: reset
                )
            )
        }
        if let used = percentValue(planUsage["apiPercentUsed"]) {
            limits.append(
                UsageLimit(
                    label: "Other Models",
                    remainingFraction: 1 - used / 100,
                    resetDescription: reset,
                    contributesToSummary: false
                )
            )
        }
        if limits.isEmpty, let used = percentValue(planUsage["totalPercentUsed"]) {
            limits.append(
                UsageLimit(
                    label: "Monthly included",
                    remainingFraction: 1 - used / 100,
                    resetDescription: reset
                )
            )
        }
        guard !limits.isEmpty else {
            throw CLIUsageError("Cursor dashboard returned no usage window")
        }

        return UsageSnapshot(
            source: source,
            limits: limits,
            updatedAt: now,
            state: .loaded
        )
    }

    /// Grok Bot's own allowance from `GetSandUsageStatus`. A plan with no included
    /// allowance — pooled enterprise, or none at all — is a conclusive "not here", so
    /// it comes back unavailable rather than failed and the ring stays hidden.
    static func grokBot(
        _ data: Data,
        source: MonitorSource = .grokBot,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        guard let json = jsonObject(data) else {
            throw CLIUsageError("Cursor dashboard returned no Grok Bot usage")
        }
        guard !flag(json["usesPooledEnterpriseAllowance"]),
              !flag(json["includedLimitZero"]),
              flag(json["hasNonZeroIncludedLimit"]),
              let used = percentValue(json["usagePercent"]) else {
            return .unavailable(source: source, message: "Not included in this Cursor plan")
        }

        return UsageSnapshot(
            source: source,
            limits: [
                UsageLimit(
                    label: "Grok Bot",
                    remainingFraction: 1 - used / 100,
                    resetAt: date(from: json["nextResetTimestampUtc"])
                )
            ],
            updatedAt: now,
            state: .loaded
        )
    }

    static func cursorIsAuthenticated(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(CursorStatus.self, from: data).isAuthenticated) == true
    }

    /// True only when `claude auth status` clearly says so; unreadable output is not proof.
    static func claudeIsSignedOut(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(ClaudeAuthStatus.self, from: data).loggedIn) == false
    }

    private static func parseClaudeLine(
        _ lines: [String],
        prefix: String,
        label: String,
        contributesToSummary: Bool = true
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
            resetDescription: resetDescription,
            contributesToSummary: contributesToSummary
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

    private static func firstIntMatch(in text: String, pattern: String) -> Int? {
        firstMatch(in: text, pattern: pattern).flatMap(Int.init)
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func percentValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: number
        case let number as Int: Double(number)
        case let number as NSNumber: number.doubleValue
        case let text as String: Double(text)
        default: nil
        }
    }

    private static func flag(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: flag
        case let number as NSNumber: number.boolValue
        default: false
        }
    }

    private static func resetDescription(fromMillis value: Any?) -> String? {
        guard let date = date(fromMillis: value) else { return nil }
        return "Resets \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private static func date(fromMillis value: Any?) -> Date? {
        let millis: Double?
        switch value {
        case let number as Double: millis = number
        case let number as Int: millis = Double(number)
        case let number as NSNumber: millis = number.doubleValue
        case let text as String: millis = Double(text)
        default: millis = nil
        }
        guard let millis, millis > 0 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    private static func date(from value: Any?) -> Date? {
        if let date = date(fromMillis: value) { return date }
        guard let text = value as? String, !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: text)
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

private struct CodexConsumeResponse: Decodable {
    let id: Int?
    let result: CodexConsumeResult?
    let error: CodexRPCError?
}

private struct CodexConsumeResult: Decodable {
    let outcome: String?
}

private struct CodexRPCError: Decodable {
    let message: String?
}

private struct CodexRateLimitResult: Decodable {
    let rateLimits: CodexRateLimits
    let rateLimitsByLimitId: [String: CodexRateLimits]?
    let rateLimitResetCredits: CodexResetCredits?
}

private struct CodexResetCredits: Decodable {
    let availableCount: Int?
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

private struct ClaudeAuthStatus: Decodable {
    let loggedIn: Bool
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
        additionalEnvironment: [String: String] = [:],
        requiresCleanExit: Bool = true
    ) throws -> Data {
        let result = try launch(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            additionalEnvironment: additionalEnvironment
        )
        guard result.status == 0 || !requiresCleanExit else {
            throw CLIUsageError("CLI usage read failed")
        }
        return result.output
    }

    /// For CLIs that answer a yes/no question with their exit code.
    static func exitStatus(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        additionalEnvironment: [String: String] = [:]
    ) throws -> Int32 {
        try launch(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            additionalEnvironment: additionalEnvironment
        ).status
    }

    private static func launch(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        additionalEnvironment: [String: String]
    ) throws -> (output: Data, status: Int32) {
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
        return (stdout, process.terminationStatus)
    }

    static func codexAppServer(
        executable: String,
        method: String,
        paramsJSON: String,
        additionalEnvironment: [String: String] = [:]
    ) throws -> Data {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let capture = OutputCapture(targetResponseID: 2)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        if !additionalEnvironment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(
                additionalEnvironment,
                uniquingKeysWith: { _, newValue in newValue }
            )
        }
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
            #"{"id":2,"method":"\#(method)","params":\#(paramsJSON)}"#
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(requests.utf8))

        guard capture.wait(timeout: 10) else {
            output.fileHandleForReading.readabilityHandler = nil
            input.fileHandleForWriting.closeFile()
            process.terminate()
            throw CLIUsageError("Codex CLI timed out")
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

    static func cursorDashboard(method: String, token: String) throws -> Data {
        guard let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/\(method)") else {
            throw CLIUsageError("Cursor dashboard usage read failed")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        let capture = HTTPCapture()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            capture.finish(data: data, response: response, error: error)
        }
        task.resume()
        guard capture.wait(timeout: 10) else {
            task.cancel()
            throw CLIUsageError("Cursor dashboard usage read timed out")
        }
        if capture.transportFailed {
            throw CLIUsageError("Cursor dashboard usage read failed")
        }
        guard let http = capture.response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let data = capture.data else {
            throw CLIUsageError("Cursor dashboard usage read failed")
        }
        return data
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

private final class HTTPCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var storage: Data?
    private var urlResponse: URLResponse?
    private var failed = false
    private var hasSignaled = false

    var data: Data? { lock.withLock { storage } }
    var response: URLResponse? { lock.withLock { urlResponse } }
    var transportFailed: Bool { lock.withLock { failed } }

    func finish(data: Data?, response: URLResponse?, error: Error?) {
        lock.withLock {
            storage = data
            urlResponse = response
            failed = error != nil
            guard !hasSignaled else { return }
            hasSignaled = true
            semaphore.signal()
        }
    }

    func wait(timeout: TimeInterval) -> Bool {
        semaphore.wait(timeout: .now() + timeout) == .success
    }
}
