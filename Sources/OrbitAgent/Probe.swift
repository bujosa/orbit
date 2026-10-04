import Foundation
import OrbitCore

enum Probe {
  static func snapshot() async -> DeviceSnapshot {
    async let claude = claudeStatus()
    async let codex = codexStatus()
    async let cursor = cursorStatus()
    async let grok = grokStatus()
    async let network = tailscaleStatus()
    let t3 = await t3Status()
    return await DeviceSnapshot(
      hostname: ProcessInfo.processInfo.hostName, t3Running: t3.running,
      t3Version: t3.version, tailscaleConnected: network,
      providers: [claude, codex, grok, cursor])
  }

  static func missing(_ provider: Provider) -> ProviderStatus {
    ProviderStatus(
      id: provider, auth: .notInstalled, note: "Install \(provider.title) on this Mac.")
  }

  static func claudeStatus() async -> ProviderStatus {
    guard let binary = Paths.claude else { return missing(.claude) }
    guard
      let result = try? await ProcessRunner.run(
        binary, ["auth", "status"], environment: Paths.cleanEnvironment),
      let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any]
    else {
      return ProviderStatus(
        id: .claude, auth: .unavailable, note: "Claude did not return its sign-in status.")
    }
    let subscriptionToken = object["authMethod"] as? String == "oauth_token"
    let loggedIn = object["loggedIn"] as? Bool == true
    return ProviderStatus(
      id: .claude, auth: loggedIn ? .authenticated : .loginRequired,
      account: SafeStatus.maskedEmail(object["email"] as? String),
      plan: (object["subscriptionType"] as? String)?.capitalized
        ?? (subscriptionToken ? "Subscription token" : nil),
      renewal: subscriptionToken ? .manual : .providerManaged,
      note: loggedIn
        ? "A saved session exists. Verify access to test it."
        : "Sign in with your Claude subscription.")
  }

  static func codexStatus() async -> ProviderStatus {
    guard let binary = Paths.codex else { return missing(.codex) }
    guard
      let result = try? await ProcessRunner.run(
        binary, ["login", "status"], environment: Paths.cleanEnvironment)
    else {
      return ProviderStatus(
        id: .codex, auth: .unavailable, note: "Codex did not return its sign-in status.")
    }
    let loggedIn = result.exit == 0 && !result.timedOut
    let chatGPT = result.diagnostic.lowercased().contains("chatgpt")
    return ProviderStatus(
      id: .codex, auth: loggedIn ? .authenticated : .loginRequired,
      plan: loggedIn ? (chatGPT ? "ChatGPT subscription" : "API credential") : nil,
      renewal: chatGPT ? .providerManaged : .unknown,
      note: loggedIn
        ? "A saved session exists. Verify access to test it." : "Sign in with your ChatGPT account."
    )
  }

  static func grokStatus() async -> ProviderStatus {
    guard Paths.grok != nil else { return missing(.grok) }
    let file = Paths.home.appendingPathComponent(".grok/auth.json")
    guard let data = try? Data(contentsOf: file),
      let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let record = dictionary.values.compactMap({ $0 as? [String: Any] }).first(where: {
        $0["key"] != nil
      })
    else {
      return ProviderStatus(
        id: .grok, auth: .loginRequired, note: "Sign in with your Grok account.")
    }
    // Only safe metadata leaves the agent; refresh and access tokens stay here.
    let expiry: Date? = {
      if let value = record["expires_at"] as? Double {
        return Date(timeIntervalSince1970: value > 1e12 ? value / 1000 : value)
      }
      if let value = record["expires_at"] as? String {
        return ISO8601DateFormatter().date(from: value)
      }
      return nil
    }()
    let refreshable = record["refresh_token"] != nil
    return ProviderStatus(
      id: .grok,
      auth: !refreshable && expiry.map({ $0 < Date() }) == true ? .expired : .authenticated,
      account: SafeStatus.maskedEmail(record["email"] as? String), plan: "Grok account",
      expiresAt: expiry, renewal: refreshable ? .providerManaged : .unknown,
      note: "A saved session exists. Verify access to test it.")
  }

  static func cursorStatus() async -> ProviderStatus {
    let object = await CursorBridge.run(action: "status")
    let expiry = (object["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
    return ProviderStatus(
      id: .cursor,
      auth: AuthState(rawValue: object["auth"] as? String ?? "unavailable") ?? .unavailable,
      account: object["account"] as? String, plan: "Cursor account", expiresAt: expiry,
      renewal: .manual, note: object["note"] as? String ?? "Cursor status unavailable.")
  }

  static func tailscaleStatus() async -> Bool {
    guard let binary = Paths.tailscale,
      let result = try? await ProcessRunner.run(binary, ["status", "--json"], timeout: 8),
      let dictionary = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any]
    else { return false }
    return dictionary["BackendState"] as? String == "Running"
  }

  static func t3Status() async -> (running: Bool, version: String?) {
    let runtime = Paths.home.appendingPathComponent(".t3/userdata/server-runtime.json")
    guard let data = try? Data(contentsOf: runtime),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let port = object["port"] as? Int, (1...65535).contains(port),
      let url = URL(string: "http://127.0.0.1:\(port)/.well-known/t3/environment")
    else { return (false, nil) }
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    guard let (body, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let descriptor = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    else { return (false, nil) }
    return (true, descriptor["serverVersion"] as? String ?? descriptor["version"] as? String)
  }

  static func verify(_ provider: Provider) async -> AccessCheck {
    if provider == .cursor {
      let result = await CursorBridge.run(action: "verify")
      if result["ready"] as? Bool == true {
        return AccessCheck(
          provider: provider, state: .verified, note: "A real model request succeeded.")
      }
      if ["expired", "loginRequired"].contains(result["auth"] as? String ?? "") {
        return AccessCheck(
          provider: provider, state: .loginRequired,
          note: "Cursor rejected this session. Sign in again.")
      }
      return AccessCheck(
        provider: provider, state: result["limited"] as? Bool == true ? .limited : .failed,
        note: "Cursor access could not be verified.")
    }
    let binary: String?
    let arguments: [String]
    let prompt = "Reply exactly ORBIT_OK. Do not use tools or modify files."
    switch provider {
    case .claude:
      binary = Paths.claude
      arguments = [
        "-p", prompt, "--tools", "", "--no-session-persistence",
        "--output-format", "json", "--settings", "{\"disableAllHooks\":true}", "--mcp-config",
        "{\"mcpServers\":{}}", "--strict-mcp-config",
      ]
    case .codex:
      binary = Paths.codex
      arguments = [
        "exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", prompt,
      ]
    case .grok:
      binary = Paths.grok
      arguments = [
        "--single", prompt, "--permission-mode", "plan", "--no-subagents", "--max-turns", "1",
        "--output-format", "plain", "--disable-web-search", "--tools", "",
      ]
    case .cursor: fatalError("Handled above")
    }
    guard let binary else {
      return AccessCheck(provider: provider, state: .failed, note: "Install this provider first.")
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "orbit-check-" + UUID().uuidString)
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: directory) }
      let result = try await ProcessRunner.run(
        binary, arguments, timeout: 100, environment: Paths.cleanEnvironment, cwd: directory)
      var text = result.exit == 0 ? result.text : result.diagnostic
      if provider == .claude,
        let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any]
      {
        text = object["result"] as? String ?? text
      }
      return SafeStatus.access(
        provider: provider, exit: result.exit, output: text, timedOut: result.timedOut)
    } catch {
      return AccessCheck(
        provider: provider, state: .failed, note: "The access check could not be started.")
    }
  }
}
