import Foundation

public enum LoginEventKind: String, Codable, Sendable {
  case starting, challenge, signedIn, failed, cancelled, expired, busy
  public var terminal: Bool { ![.starting, .challenge].contains(self) }
}

/// Short-lived authorization instructions. Never persist these in inventory, history, or logs.
public struct LoginChallenge: Codable, Equatable, Sendable {
  public var url: String
  public var userCode: String?
  public var requiresCodeEntry: Bool
  public init(url: String, userCode: String? = nil, requiresCodeEntry: Bool = false) {
    self.url = url
    self.userCode = userCode
    self.requiresCodeEntry = requiresCodeEntry
  }

  public func validate(for provider: Provider) throws {
    guard url.utf8.count <= 8192, let components = URLComponents(string: url),
      components.scheme == "https", components.user == nil, components.password == nil,
      components.port == nil, components.fragment == nil,
      let host = components.host?.lowercased()
    else { throw OrbitError.incompatibleAgent }
    let endpoints: [Provider: [String: Set<String>]] = [
      .claude: [
        "claude.com": ["/cai/oauth/authorize", "/oauth/authorize"],
        "claude.ai": ["/oauth/authorize"], "console.anthropic.com": ["/oauth/authorize"],
        "platform.claude.com": ["/oauth/authorize"],
      ],
      .codex: ["auth.openai.com": ["/codex/device"]],
      .grok: [
        "accounts.x.ai": ["/oauth2/device"], "auth.x.ai": ["/oauth2/device", "/device"],
        "accounts.spacex.ai": ["/oauth2/device"],
      ],
      .cursor: ["cursor.com": ["/loginDeepControl"]],
    ]
    guard endpoints[provider]?[host]?.contains(components.path) == true else {
      throw OrbitError.incompatibleAgent
    }
    let allowed: [Provider: Set<String>] = [
      .claude: [
        "client_id", "code", "code_challenge", "code_challenge_method", "redirect_uri",
        "response_type", "scope", "state", "email",
      ],
      .codex: [], .grok: ["user_code"],
      .cursor: ["challenge", "uuid", "mode", "redirectTarget"],
    ]
    let items = components.queryItems ?? []
    guard items.allSatisfy({ allowed[provider]?.contains($0.name) == true }),
      Set(items.map(\.name)).count == items.count,
      requiresCodeEntry == (provider == .claude)
    else { throw OrbitError.incompatibleAgent }
    if let redirect = items.first(where: { $0.name == "redirect_uri" })?.value {
      guard let target = URL(string: redirect), target.user == nil, target.password == nil,
        ["localhost", "127.0.0.1", "console.anthropic.com", "platform.claude.com", "claude.com"]
          .contains(target.host ?? "")
      else { throw OrbitError.incompatibleAgent }
    }
    if let userCode {
      guard [.codex, .grok].contains(provider), Self.validUserCode(userCode) else {
        throw OrbitError.incompatibleAgent
      }
    }
  }

  public static func validUserCode(_ value: String) -> Bool {
    value.range(of: #"^[A-Z0-9]{4,6}-[A-Z0-9]{4,6}$"#, options: .regularExpression) != nil
  }
}

public struct LoginEvent: Codable, Sendable {
  public var schemaVersion = 1
  public var provider: Provider
  public var kind: LoginEventKind
  public var challenge: LoginChallenge?
  public init(provider: Provider, kind: LoginEventKind, challenge: LoginChallenge? = nil) {
    self.provider = provider
    self.kind = kind
    self.challenge = challenge
  }
  public func validate(for expected: Provider) throws {
    guard schemaVersion == 1, provider == expected,
      (kind == .challenge) == (challenge != nil)
    else { throw OrbitError.incompatibleAgent }
    try challenge?.validate(for: provider)
  }
}

public struct LoginInput: Codable, Sendable {
  public enum Action: String, Codable, Sendable { case code, cancel }
  public var action: Action
  public var code: String?
  public init(action: Action, code: String? = nil) {
    self.action = action
    self.code = code
  }
  public func validate(for provider: Provider) throws {
    switch action {
    case .cancel: guard code == nil else { throw OrbitError.invalidDevice }
    case .code:
      guard provider == .claude, let code,
        code.range(of: #"^[A-Za-z0-9._~#\-]{1,2048}$"#, options: .regularExpression) != nil
      else { throw OrbitError.invalidDevice }
    }
  }
}

/// Inspects bounded local CLI output; exposes only allowlisted authorization challenges.
public struct LoginOutputParser {
  private let provider: Provider
  private var buffer = ""
  private var previous: LoginChallenge?
  public init(provider: Provider) { self.provider = provider }
  public mutating func consume(_ data: Data) -> LoginChallenge? {
    buffer += String(decoding: data, as: UTF8.self)
    buffer = String(buffer.suffix(24_000))
    let plain = buffer.replacingOccurrences(
      of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
    guard
      let regex = try? NSRegularExpression(pattern: #"https://[^\s\x1B<>\"']+(?=[\s\x1B<>\"'])"#)
    else {
      return nil
    }
    for match in regex.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
      guard let range = Range(match.range, in: plain) else { continue }
      let url = String(plain[range])
      var code = URLComponents(string: url)?.queryItems?.first { $0.name == "user_code" }?.value
      if code == nil, [.codex, .grok].contains(provider),
        let codeRange = plain.range(
          of: #"\b[A-Z0-9]{4,6}-[A-Z0-9]{4,6}\b"#, options: .regularExpression)
      {
        code = String(plain[codeRange])
      }
      let challenge = LoginChallenge(
        url: url, userCode: code, requiresCodeEntry: provider == .claude)
      if (try? challenge.validate(for: provider)) != nil, challenge != previous {
        previous = challenge
        return challenge
      }
    }
    return nil
  }
}
