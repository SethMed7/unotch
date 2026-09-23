import CryptoKit
import Foundation

protocol UsageFetching: Sendable {
    func fetchUsage(for source: MonitorSource) async -> UsageSnapshot
    /// Subscriptions whose local CLI is present on this Mac, including extra sign-ins
    /// of the same CLI. Cheap file checks; safe to call often.
    func installedSources() -> [MonitorSource]
    /// Spends one available reset for this sign-in: a banked Codex credit, or a Claude
    /// limit reset the account has been granted. Providers without resets return
    /// `.unsupported`. Callers refresh usage after a conclusive outcome.
    func redeemReset(for source: MonitorSource) async -> ResetResult
}

extension UsageFetching {
    func redeemReset(for source: MonitorSource) async -> ResetResult {
        .unsupported
    }
}

/// What a reset request reported, or why it could not be sent. Codex answers through
/// `account/rateLimitResetCredit/consume`; Claude through `reset_rate_limits`.
enum ResetResult: Equatable, Sendable {
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
        case .unsupported: "No resets for this subscription"
        }
    }
}

actor CLIUsageFetcher: UsageFetching {
    /// What Claude's usage endpoint last said about a sign-in's limit resets: the row
    /// for the HUD, the grant a claim must name, and when it was read.
    private struct ClaudeResets {
        var limit: UsageLimit?
        var grantID: String?
        var readAt: Date
    }

    /// Claude's usage endpoint answers about one read a minute per account, and Claude
    /// Code's own `/usage` shares that budget through a 60-second snapshot. The CLI
    /// stays the every-minute reader so that snapshot keeps being refreshed; the
    /// endpoint is asked directly — the only place resets are reported — every
    /// `claudeResetsInterval`, and again right after a reset is used.
    private var claudeResets: [MonitorSource: ClaudeResets] = [:]
    /// After a rate-limited direct read, that sign-in waits this long before asking
    /// again; the last known resets row stays on the HUD meanwhile.
    private var claudeDirectBackoffUntil: [MonitorSource: Date] = [:]
    /// `claude --version`, looked up once it answers. The usage endpoint offers resets
    /// only to a current Claude Code, so the direct read identifies the install it
    /// acts for.
    private var claudeCLIVersion: String?

    private static let claudeResetsInterval: TimeInterval = 10 * 60
    private static let claudeResetsKeptFor: TimeInterval = 30 * 60
    private static let claudeDirectBackoff: TimeInterval = 5 * 60
    /// The endpoint opens one slot per account every minute or two, and a refused
    /// call costs nothing, so a due read tries every `claudeDirectRetryDelay` until it
    /// lands or `claudeDirectAttempts` are spent.
    private static let claudeDirectAttempts = 8
    private static let claudeDirectRetryDelay: TimeInterval = 20

    /// `agy --version`, looked up once it answers. Antigravity's quota endpoint only
    /// answers a request that names the Antigravity client.
    private var antigravityCLIVersion: String?
    /// When uNotch last started `agy` to refresh its sign-in. A refresh that did not
    /// help (signed out, offline) is not retried for `antigravityRefreshSpacing`.
    private var antigravityRefreshedAt: Date?
    private static let antigravityRefreshSpacing: TimeInterval = 10 * 60

    func fetchUsage(for source: MonitorSource) async -> UsageSnapshot {
        if source.provider == .claude {
            return await fetchClaude(for: source)
        }
        if source.provider == .antigravity {
            return await fetchAntigravity(for: source)
        }
        return await Task.detached(priority: .utility) {
            switch source.provider {
            case .codex:
                return Self.fetchCodexUsage(for: source)
            case .claude:
                return Self.fetchClaudeCLIUsage(for: source)
            case .cursor:
                return Self.fetchCursorUsage(for: source)
            case .grokBot:
                return Self.fetchGrokBotUsage(for: source)
            case .antigravity:
                return Self.fetchAntigravityUsage(for: source, cliVersion: nil, mayRefreshToken: false).snapshot
            }
        }.value
    }

    func redeemReset(for source: MonitorSource) async -> ResetResult {
        switch source.provider {
        case .codex:
            return await Task.detached(priority: .utility) {
                Self.redeemCodexReset(for: source)
            }.value
        case .claude:
            guard let version = await claudeVersion() else { return .failed("Claude CLI not found") }
            let known = claudeResets[source]?.grantID
            let result = await Task.detached(priority: .utility) {
                Self.redeemClaudeReset(for: source, grantID: known, cliVersion: version)
            }.value
            // Whatever the answer, the next read asks the endpoint so the row is current.
            claudeResets[source] = nil
            claudeDirectBackoffUntil[source] = nil
            return result
        case .cursor, .grokBot, .antigravity:
            return .unsupported
        }
    }

    private func fetchClaude(for source: MonitorSource) async -> UsageSnapshot {
        let now = Date()
        let known = claudeResets[source]
        let due = known.map { now.timeIntervalSince($0.readAt) >= Self.claudeResetsInterval } ?? true
        let backedOff = (claudeDirectBackoffUntil[source] ?? .distantPast) > now

        if due, !backedOff, let version = await claudeVersion() {
            // Live Claude Code sessions and Claude Desktop share this account's slots,
            // so the first try is often refused. Keep trying on a short cadence;
            // nothing else of ours asks for this sign-in meanwhile.
            for attempt in 0..<Self.claudeDirectAttempts {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(Self.claudeDirectRetryDelay))
                }
                let direct = await Task.detached(priority: .utility) {
                    Self.fetchClaudeDirectUsage(for: source, cliVersion: version)
                }.value
                if case .loaded(let snapshot, let limit, let grantID) = direct {
                    claudeResets[source] = ClaudeResets(limit: limit, grantID: grantID, readAt: Date())
                    return snapshot
                }
                guard case .rateLimited = direct else { break }
            }
            // Still rate limited, or a token the CLI has to refresh first: leave the
            // endpoint alone for a while rather than asking again every minute.
            claudeDirectBackoffUntil[source] = Date().addingTimeInterval(Self.claudeDirectBackoff)
        }

        var snapshot = await Task.detached(priority: .utility) {
            Self.fetchClaudeCLIUsage(for: source)
        }.value
        if snapshot.state == .loaded, let known,
           now.timeIntervalSince(known.readAt) < Self.claudeResetsKeptFor,
           let limit = known.limit {
            snapshot.limits.append(limit)
        }
        return snapshot
    }

    private func fetchAntigravity(for source: MonitorSource) async -> UsageSnapshot {
        if antigravityCLIVersion == nil {
            antigravityCLIVersion = await Task.detached(priority: .utility) { Self.antigravityVersion() }.value
        }
        let version = antigravityCLIVersion
        let mayRefresh = antigravityRefreshedAt.map {
            Date().timeIntervalSince($0) >= Self.antigravityRefreshSpacing
        } ?? true
        let read = await Task.detached(priority: .utility) {
            Self.fetchAntigravityUsage(for: source, cliVersion: version, mayRefreshToken: mayRefresh)
        }.value
        if read.refreshed { antigravityRefreshedAt = Date() }
        return read.snapshot
    }

    private func claudeVersion() async -> String? {
        if let cached = claudeCLIVersion { return cached }
        let version = await Task.detached(priority: .utility) { Self.claudeCLIVersion() }.value
        claudeCLIVersion = version
        return version
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
        case .grokBot, .antigravity:
            // Antigravity is read from the one keychain item `agy` signs in to by
            // default; a second `agy` sign-in is not looked for.
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
        case .antigravity:
            return executable(named: "agy", preferredPaths: [
                "\(home)/.local/bin/agy",
                "/opt/homebrew/bin/agy",
                "/usr/local/bin/agy"
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

    private static func redeemCodexReset(for source: MonitorSource) -> ResetResult {
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

    enum ClaudeDirectRead {
        /// Usage plus, when the account has any, the Resets available row and the
        /// grant a claim would name.
        case loaded(UsageSnapshot, resets: UsageLimit?, grantID: String?)
        case rateLimited
        case unavailable
    }

    private static let claudeUsagePath = "/api/oauth/usage?cedar_ember=1&skip_spend=1"

    /// Claude's usage straight from the endpoint Claude Code's `/usage` asks, with the
    /// OAuth token Claude Code keeps in the login keychain. Asked with `cedar_ember=1`,
    /// the answer also lists the limit resets the account holds — the CLI never prints
    /// those. An expired token or a signed-out folder comes back unavailable; the CLI
    /// read that follows refreshes the token and tells signed-out apart.
    private static func fetchClaudeDirectUsage(for source: MonitorSource, cliVersion: String) -> ClaudeDirectRead {
        guard let token = claudeKeychainToken(for: source) else { return .unavailable }
        guard let reply = try? ProcessRunner.claudeAPI(
            path: claudeUsagePath,
            token: token,
            userAgent: claudeUserAgent(cliVersion: cliVersion)
        ) else { return .unavailable }
        if reply.status == 429 || UsageCLIParser.claudeIsRateLimited(reply.data) {
            return .rateLimited
        }
        guard reply.status == 200,
              let parsed = try? UsageCLIParser.claudeAPI(reply.data, source: source) else {
            return .unavailable
        }
        return .loaded(parsed.snapshot, resets: parsed.resets, grantID: parsed.grantID)
    }

    /// One Claude limit reset, sent the way Claude Code's own "Use an available limit
    /// reset" does: `reset_rate_limits` on the sign-in's organization, naming the grant.
    /// Without a grant from the last read, the status is read once more first.
    private static func redeemClaudeReset(
        for source: MonitorSource,
        grantID: String?,
        cliVersion: String
    ) -> ResetResult {
        guard let token = claudeKeychainToken(for: source) else {
            return .failed("Sign in with Claude Code")
        }
        let userAgent = claudeUserAgent(cliVersion: cliVersion)
        do {
            var grant = grantID
            if grant == nil {
                let status = try ProcessRunner.claudeAPI(path: claudeUsagePath, token: token, userAgent: userAgent)
                guard status.status == 200, !UsageCLIParser.claudeIsRateLimited(status.data) else {
                    return .failed(status.status == 401 || status.status == 403
                        ? "Sign in with Claude Code" : "Claude is rate limited, try again shortly")
                }
                grant = try UsageCLIParser.claudeAPI(status.data, source: source).grantID
            }
            guard let grant else { return .noCredit }

            let profile = try ProcessRunner.claudeAPI(path: "/api/oauth/profile", token: token, userAgent: userAgent)
            guard profile.status == 200,
                  let organization = UsageCLIParser.claudeOrganizationID(profile.data) else {
                return .failed(profile.status == 401 || profile.status == 403
                    ? "Sign in with Claude Code" : "Claude reset failed")
            }

            let body = try JSONSerialization.data(withJSONObject: [
                "program": "cedar_ember",
                "grant_id": grant,
                "request_id": UUID().uuidString
            ])
            let reply = try ProcessRunner.claudeAPI(
                path: "/api/organizations/\(organization)/reset_rate_limits",
                token: token,
                userAgent: userAgent,
                body: body
            )
            return UsageCLIParser.claudeReset(reply)
        } catch {
            return .failed(userFacingMessage(error))
        }
    }

    /// The endpoint offers limit resets only to a current Claude Code, so the request
    /// carries the installed CLI's own client string, followed by uNotch's.
    static func claudeUserAgent(cliVersion: String) -> String {
        "claude-cli/\(cliVersion) (external, cli) \(AppInfo.name)/\(AppInfo.version)"
    }

    /// `claude --version` prints `2.1.280 (Claude Code)`; only the number is wanted.
    private static func claudeCLIVersion() -> String? {
        guard let executable = executablePath(for: .claude),
              let output = try? ProcessRunner.run(executable: executable, arguments: ["--version"], timeout: 8)
        else { return nil }
        return UsageCLIParser.claudeVersion(output)
    }

    /// The OAuth token Claude Code stores in the login keychain: `Claude Code-credentials`
    /// for the default sign-in, with `-<first 8 hex of SHA-256 of the folder path>` for a
    /// `CLAUDE_CONFIG_DIR` one. Read into memory for the request and never stored.
    private static func claudeKeychainToken(for source: MonitorSource) -> String? {
        guard let data = try? ProcessRunner.run(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", claudeKeychainService(for: source), "-w"],
            timeout: 4
        ),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let oauth = object["claudeAiOauth"] as? [String: Any],
        let token = oauth["accessToken"] as? String else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func claudeKeychainService(for source: MonitorSource) -> String {
        guard let directory = source.configDirectory else { return "Claude Code-credentials" }
        let digest = SHA256.hash(data: Data(directory.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(suffix)"
    }

    private static func fetchClaudeCLIUsage(for source: MonitorSource) -> UsageSnapshot {
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

    /// Antigravity's usage straight from the endpoint `agy`'s own `/usage` panel asks,
    /// with the OAuth token `agy` keeps in the login keychain. That token lasts an hour
    /// and only `agy` can renew it, so once it is stale uNotch runs `agy models` — the
    /// lightest command that signs in, and one that runs no model — then reads the
    /// renewed token. That is at most one launch an hour while `agy` is signed in.
    /// `refreshed` reports whether `agy` was launched.
    private static func fetchAntigravityUsage(
        for source: MonitorSource,
        cliVersion: String?,
        mayRefreshToken: Bool
    ) -> (snapshot: UsageSnapshot, refreshed: Bool) {
        guard let executable = executablePath(for: .antigravity) else {
            return (.unavailable(source: source, message: "Antigravity CLI not found"), false)
        }
        let signedOut = UsageSnapshot.unavailable(source: source, message: "Sign in with the Antigravity CLI")
        // No keychain item: never signed in, or signed out. Launching `agy` cannot help.
        guard var token = antigravityKeychainToken() else { return (signedOut, false) }

        var refreshed = false
        func refresh() -> Bool {
            guard mayRefreshToken, !refreshed else { return false }
            refreshed = true
            _ = try? ProcessRunner.run(
                executable: executable,
                arguments: ["models"],
                timeout: 30,
                requiresCleanExit: false
            )
            guard let renewed = antigravityKeychainToken() else { return false }
            token = renewed
            return true
        }

        // Renew first when it is due; the reply then tells signed out (401) from offline.
        if token.isStale() { _ = refresh() }
        let userAgent = antigravityUserAgent(cliVersion: cliVersion ?? "0")
        do {
            var reply = try ProcessRunner.antigravityAPI(
                method: "retrieveUserQuotaSummary",
                token: token.accessToken,
                userAgent: userAgent
            )
            // A token revoked before its expiry: one renewal, one more try.
            if reply.status == 401, refresh() {
                reply = try ProcessRunner.antigravityAPI(
                    method: "retrieveUserQuotaSummary",
                    token: token.accessToken,
                    userAgent: userAgent
                )
            }
            if reply.status == 401 { return (signedOut, refreshed) }
            guard reply.status == 200 else {
                return (.failed(source: source, message: "Antigravity usage read failed"), refreshed)
            }
            return (try UsageCLIParser.antigravity(reply.data, source: source), refreshed)
        } catch {
            return (.failed(source: source, message: userFacingMessage(error)), refreshed)
        }
    }

    /// The endpoint turns away any client that does not name itself as Antigravity —
    /// with a 403 that claims there is no license, which is misleading — so the request
    /// carries the installed `agy`'s client string, followed by uNotch's.
    static func antigravityUserAgent(cliVersion: String) -> String {
        "antigravity/\(cliVersion) darwin/arm64 \(AppInfo.name)/\(AppInfo.version)"
    }

    /// `agy --version` prints only the number. It does not start the language server.
    private static func antigravityVersion() -> String? {
        guard let executable = executablePath(for: .antigravity),
              let output = try? ProcessRunner.run(executable: executable, arguments: ["--version"], timeout: 8)
        else { return nil }
        let version = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty || version.contains(" ") ? nil : version
    }

    /// The sign-in `agy` stores in the login keychain as service `gemini`, account
    /// `antigravity`. Read into memory for the request and never stored.
    private static func antigravityKeychainToken() -> AntigravityToken? {
        guard let data = try? ProcessRunner.run(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"],
            timeout: 4
        ) else { return nil }
        return UsageCLIParser.antigravityToken(data)
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

    static func codexReset(_ data: Data) throws -> ResetResult {
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

    /// Claude's usage endpoint: the 5-hour and weekly windows, any model-scoped weekly
    /// limit, and — when asked with `cedar_ember=1` — the limit resets the account holds.
    /// The rows match what `/usage` prints. A grant with resets left that is usable now
    /// puts **Use reset** on the Resets available row; one the account has spent shows
    /// 0 resets, like Codex.
    static func claudeAPI(
        _ data: Data,
        source: MonitorSource = .claude,
        now: Date = Date()
    ) throws -> (snapshot: UsageSnapshot, resets: UsageLimit?, grantID: String?) {
        guard let root = jsonObject(data) else {
            throw CLIUsageError("Claude usage returned no plan limits")
        }
        var limits: [UsageLimit] = []
        if let window = root["five_hour"] as? [String: Any], let used = percentValue(window["utilization"]) {
            limits.append(UsageLimit(
                label: "5-hour limit",
                remainingFraction: 1 - used / 100,
                resetDescription: claudeResetDescription(window["resets_at"])
            ))
        }
        if let window = root["seven_day"] as? [String: Any], let used = percentValue(window["utilization"]) {
            limits.append(UsageLimit(
                label: "Weekly limit",
                remainingFraction: 1 - used / 100,
                resetDescription: claudeResetDescription(window["resets_at"])
            ))
        }
        for entry in root["limits"] as? [[String: Any]] ?? [] {
            guard entry["kind"] as? String == "weekly_scoped",
                  let scope = entry["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String, !name.isEmpty,
                  let used = percentValue(entry["percent"]),
                  !limits.contains(where: { $0.label == name }) else { continue }
            limits.append(UsageLimit(
                label: name,
                remainingFraction: 1 - used / 100,
                resetDescription: claudeResetDescription(entry["resets_at"]),
                contributesToSummary: false
            ))
        }
        guard !limits.isEmpty else {
            throw noClaudeLimits
        }

        var grantID: String?
        var resetsRow: UsageLimit?
        if let resets = root["cedar_ember"] as? [String: Any],
           flag(resets["eligible"]),
           let grants = resets["grants"] as? [[String: Any]], !grants.isEmpty {
            func isUsable(_ grant: [String: Any]) -> Bool {
                guard let id = grant["id"] as? String, !id.isEmpty,
                      let left = percentValue(grant["resets_left"]), left > 0,
                      !flag(grant["paused"]), flag(grant["usable_now"]) else { return false }
                if let ends = date(from: grant["ends_at"]), ends <= now { return false }
                if let starts = date(from: grant["starts_at"]), starts > now { return false }
                return !flag(grant["use_requires_limit"]) || flag(resets["at_limit"])
            }
            // The claim must name the grant the server would spend next.
            let next = resets["next_grant_id"] as? String
            let usable = grants.first { $0["id"] as? String == next && isUsable($0) }
                ?? grants.first(where: isUsable)
            grantID = usable?["id"] as? String
            let count = grants.reduce(0) { $0 + Int(percentValue($1["resets_left"]) ?? 0) }
            var text = switch count {
            case 0: "0 resets"
            case 1: "1 available"
            default: "\(count) available"
            }
            if grantID != nil, let ends = date(from: usable?["ends_at"]) {
                text += " until \(ends.formatted(.dateTime.month(.abbreviated).day()))"
            }
            resetsRow = UsageLimit(
                label: "Resets available",
                remainingFraction: grantID == nil ? 0 : 1,
                valueText: text,
                showsMeter: false,
                contributesToSummary: false,
                canRedeem: grantID != nil
            )
        }

        let snapshot = UsageSnapshot(
            source: source,
            limits: limits + [resetsRow].compactMap { $0 },
            updatedAt: now,
            state: .loaded
        )
        return (snapshot, resetsRow, grantID)
    }

    /// A reset time written the way `claude /usage` prints one — `Resets Sep 22 at
    /// 7:40pm (America/New_York)` — so a direct read and a CLI read look alike.
    static func claudeResetDescription(_ value: Any?, timeZone: TimeZone = .current) -> String? {
        guard let date = date(from: value) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var style = Date.FormatStyle(locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone)
        let day = date.formatted(style.month(.abbreviated).day())
        style = calendar.component(.minute, from: date) == 0
            ? style.hour(.defaultDigits(amPM: .abbreviated))
            : style.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)
        let time = date.formatted(style).filter { !$0.isWhitespace }.lowercased()
        return "Resets \(day) at \(time) (\(timeZone.identifier))"
    }

    /// The version number out of `claude --version`.
    static func claudeVersion(_ data: Data) -> String? {
        firstMatch(in: String(decoding: data, as: UTF8.self), pattern: #"([0-9]+\.[0-9]+\.[0-9]+)"#)
    }

    /// The usage endpoint refuses bursts with a JSON `rate_limit_error`, sometimes
    /// behind a 200. Claude Code treats that body as rate limited too.
    static func claudeIsRateLimited(_ data: Data) -> Bool {
        guard let error = jsonObject(data)?["error"] as? [String: Any] else { return false }
        return error["type"] as? String == "rate_limit_error"
    }

    static func claudeOrganizationID(_ data: Data) -> String? {
        guard let organization = jsonObject(data)?["organization"] as? [String: Any],
              let id = organization["uuid"] as? String, !id.isEmpty else { return nil }
        return id
    }

    /// `reset_rate_limits` answers with a `result`; HTTP failures explain themselves.
    static func claudeReset(_ reply: HTTPReply) -> ResetResult {
        switch reply.status {
        case 401, 403: return .failed("Sign in with Claude Code")
        case 429: return .failed("Claude is rate limited, try again shortly")
        case 200..<300: break
        default: return .failed("Claude reset failed")
        }
        switch jsonObject(reply.data)?["result"] as? String {
        case "reset": return .reset
        case "already_used": return .alreadyRedeemed
        case "not_limited": return .nothingToReset
        case "ineligible": return .noCredit
        case "cooldown": return .failed("Reset is cooling down")
        case "unavailable": return .failed("Reset unavailable right now")
        default: return .failed("Claude returned an unknown reset outcome")
        }
    }

    /// `retrieveUserQuotaSummary`: model groups (Gemini; Claude and GPT), each with a
    /// 5-hour and a weekly bucket. The HUD shows plain usage, not a row per model
    /// group: one 5-hour and one weekly row, each the lowest across the groups, with
    /// that bucket's reset time. The ring follows the lower of the two.
    static func antigravity(
        _ data: Data,
        source: MonitorSource = .antigravity,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        guard let root = jsonObject(data), let groups = root["groups"] as? [[String: Any]] else {
            throw CLIUsageError("Antigravity usage returned no plan limits")
        }
        var lowest: [String: (remaining: Double, resetAt: Date?)] = [:]
        for bucket in groups.flatMap({ $0["buckets"] as? [[String: Any]] ?? [] }) {
            guard let window = (bucket["window"] as? String)?.lowercased() else { continue }
            // Protobuf JSON leaves out a zero, so a bucket without the field is empty.
            let remaining = percentValue(bucket["remainingFraction"]) ?? 0
            if let known = lowest[window], known.remaining <= remaining { continue }
            lowest[window] = (remaining, date(from: bucket["resetTime"]))
        }
        let limits = [("5h", "5-hour limit"), ("weekly", "Weekly limit")].compactMap { window, label in
            lowest[window].map { UsageLimit(label: label, remainingFraction: $0.remaining, resetAt: $0.resetAt) }
        }
        guard !limits.isEmpty else {
            throw CLIUsageError("Antigravity usage returned no plan limits")
        }
        return UsageSnapshot(source: source, limits: limits, updatedAt: now, state: .loaded)
    }

    /// `agy`'s keychain item: `go-keyring-base64:` and base64 of
    /// `{"token": {"access_token", "expiry", …}, …}`. Only the access token and its
    /// expiry are kept.
    static func antigravityToken(_ data: Data) -> AntigravityToken? {
        var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "go-keyring-base64:"
        if text.hasPrefix(prefix) {
            guard let decoded = Data(base64Encoded: String(text.dropFirst(prefix.count))) else { return nil }
            text = String(decoding: decoded, as: UTF8.self)
        }
        guard let root = jsonObject(Data(text.utf8)),
              let token = root["token"] as? [String: Any],
              let access = token["access_token"] as? String, !access.isEmpty else { return nil }
        return AntigravityToken(accessToken: access, expiry: date(from: token["expiry"]))
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

struct AntigravityToken: Equatable, Sendable {
    let accessToken: String
    let expiry: Date?

    /// Stale a couple of minutes early, so it cannot lapse mid-request. No expiry at all
    /// is not stale; a 401 settles that.
    func isStale(now: Date = Date()) -> Bool {
        guard let expiry else { return false }
        return expiry <= now.addingTimeInterval(120)
    }
}

struct HTTPReply: Equatable, Sendable {
    let status: Int
    let data: Data
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

    /// One request to Claude's account API with a Claude Code OAuth token. GET without
    /// a body, POST with one. The status comes back with the body so callers can tell
    /// an expired token or a rate limit from a real answer.
    static func claudeAPI(path: String, token: String, userAgent: String, body: Data? = nil) throws -> HTTPReply {
        guard let url = URL(string: "https://api.anthropic.com\(path)") else {
            throw CLIUsageError("Claude usage read failed")
        }

        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let capture = HTTPCapture()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            capture.finish(data: data, response: response, error: error)
        }
        task.resume()
        guard capture.wait(timeout: 10) else {
            task.cancel()
            throw CLIUsageError("Claude usage read timed out")
        }
        guard !capture.transportFailed, let http = capture.response as? HTTPURLResponse else {
            throw CLIUsageError("Claude usage read failed")
        }
        return HTTPReply(status: http.statusCode, data: capture.data ?? Data())
    }

    /// One call to Antigravity's Cloud Code API (`v1internal:<method>`) with `agy`'s
    /// OAuth token, posting an empty body. The status comes back with the body so an
    /// expired token can be told from a real answer.
    static func antigravityAPI(method: String, token: String, userAgent: String) throws -> HTTPReply {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:\(method)") else {
            throw CLIUsageError("Antigravity usage read failed")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let capture = HTTPCapture()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            capture.finish(data: data, response: response, error: error)
        }
        task.resume()
        guard capture.wait(timeout: 10) else {
            task.cancel()
            throw CLIUsageError("Antigravity usage read timed out")
        }
        guard !capture.transportFailed, let http = capture.response as? HTTPURLResponse else {
            throw CLIUsageError("Antigravity usage read failed")
        }
        return HTTPReply(status: http.statusCode, data: capture.data ?? Data())
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
