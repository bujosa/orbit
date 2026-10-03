import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
  case claude, codex, grok, cursor
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .claude: return "Claude Code"
    case .codex: return "Codex"
    case .grok: return "Grok Build"
    case .cursor: return "Cursor"
    }
  }
  public var symbol: String {
    switch self {
    case .claude: return "sparkle"
    case .codex: return "terminal"
    case .grok: return "bolt"
    case .cursor: return "cursorarrow"
    }
  }
}

public enum AuthState: String, Codable, Sendable {
  case authenticated, loginRequired, expired, unavailable, notInstalled
}

public enum Renewal: String, Codable, Sendable {
  case providerManaged, manual, unknown
  public var label: String {
    switch self {
    case .providerManaged: return "Provider-managed session"
    case .manual: return "Sign in again when this credential expires"
    case .unknown: return "Renewal details unavailable"
    }
  }
}

public struct ProviderStatus: Codable, Identifiable, Sendable, Equatable {
  public var id: Provider
  public var auth: AuthState
  public var account: String?
  public var plan: String?
  public var expiresAt: Date?
  public var renewal: Renewal
  public var note: String

  public init(
    id: Provider, auth: AuthState, account: String? = nil, plan: String? = nil,
    expiresAt: Date? = nil, renewal: Renewal = .unknown, note: String
  ) {
    self.id = id
    self.auth = auth
    self.account = account
    self.plan = plan
    self.expiresAt = expiresAt
    self.renewal = renewal
    self.note = note
  }
}

public struct Device: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var name: String
  public var isLocal: Bool
  public var sshAlias: String
  public var address: String
  public var hostKeyAlias: String
  public var t3URL: String

  public init(
    id: UUID = UUID(), name: String, isLocal: Bool = false, sshAlias: String = "",
    address: String = "", hostKeyAlias: String = "", t3URL: String = ""
  ) {
    self.id = id
    self.name = name
    self.isLocal = isLocal
    self.sshAlias = sshAlias
    self.address = address
    self.hostKeyAlias = hostKeyAlias
    self.t3URL = t3URL
  }

  public func validate() throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else {
      throw OrbitError.invalidDevice
    }
    if !isLocal {
      for value in [sshAlias, address, hostKeyAlias] where !value.isEmpty {
        guard
          value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._:\-]{0,253}$"#,
            options: .regularExpression) != nil
        else { throw OrbitError.invalidDevice }
      }
      guard !sshAlias.isEmpty else { throw OrbitError.invalidDevice }
    }
    if !t3URL.isEmpty {
      guard let url = URL(string: t3URL), url.user == nil, url.password == nil,
        url.query == nil, url.fragment == nil,
        url.scheme == "https"
          || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? ""))
      else {
        throw OrbitError.invalidDevice
      }
    }
  }
}

public struct DeviceSnapshot: Codable, Sendable {
  public var schemaVersion: Int
  public var capturedAt: Date
  public var hostname: String
  public var t3Running: Bool
  public var t3Version: String?
  public var tailscaleConnected: Bool
  public var providers: [ProviderStatus]

  public init(
    capturedAt: Date = Date(), hostname: String, t3Running: Bool,
    t3Version: String? = nil, tailscaleConnected: Bool, providers: [ProviderStatus]
  ) {
    self.schemaVersion = 1
    self.capturedAt = capturedAt
    self.hostname = hostname
    self.t3Running = t3Running
    self.t3Version = t3Version
    self.tailscaleConnected = tailscaleConnected
    self.providers = providers
  }

  public func validate() throws {
    guard schemaVersion == 1, Set(providers.map(\.id)).count == providers.count,
      Set(providers.map(\.id)) == Set(Provider.allCases)
    else { throw OrbitError.incompatibleAgent }
    guard abs(capturedAt.timeIntervalSinceNow) < 300 else { throw OrbitError.staleSnapshot }
  }
}

public enum AccessState: String, Codable, Sendable { case verified, loginRequired, limited, failed }

public struct AccessCheck: Codable, Sendable {
  public var provider: Provider
  public var state: AccessState
  public var checkedAt: Date
  public var note: String

  public init(provider: Provider, state: AccessState, checkedAt: Date = Date(), note: String) {
    self.provider = provider
    self.state = state
    self.checkedAt = checkedAt
    self.note = note
  }

  public func isFresh(now: Date = Date()) -> Bool {
    let age = now.timeIntervalSince(checkedAt)
    return age >= -30 && age <= 900
  }
}

public enum OrbitError: Error, LocalizedError {
  case invalidDevice, incompatibleAgent, staleSnapshot, offline, agentMissing, unsafeFile
  public var errorDescription: String? {
    switch self {
    case .invalidDevice: return "Check the device name, SSH alias, address, and HTTPS URL."
    case .incompatibleAgent:
      return "The agent returned an incompatible response. Update its installation."
    case .staleSnapshot: return "The device clock or snapshot is out of date."
    case .offline: return "Could not reach this Mac. Check Tailscale, power, and SSH access."
    case .agentMissing: return "Install orbit-agent on this Mac, then refresh."
    case .unsafeFile: return "Orbit refused to change an unrecognized or unsafe credential file."
    }
  }
}

public enum Wire {
  public static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
  public static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

public enum SafeStatus {
  public static func maskedEmail(_ value: String?) -> String? {
    guard let value, let at = value.firstIndex(of: "@"), at != value.startIndex else { return nil }
    let suffix = value[value.index(after: at)...]
    guard !suffix.isEmpty else { return nil }
    return "\(value.first!)•••@\(suffix)"
  }

  public static func access(provider: Provider, exit: Int32, output: String, timedOut: Bool)
    -> AccessCheck
  {
    if !timedOut && exit == 0
      && output.trimmingCharacters(in: .whitespacesAndNewlines) == "ORBIT_OK"
    {
      return AccessCheck(
        provider: provider, state: .verified, note: "A real model request succeeded.")
    }
    let text = output.lowercased()
    if text.contains("401") || text.contains("failed to authenticate")
      || text.contains("not logged in") || text.contains("login required")
      || text.contains("oauth access token is invalid")
    {
      return AccessCheck(
        provider: provider, state: .loginRequired,
        note: "The provider rejected this session. Sign in again.")
    }
    if text.contains("429") || text.contains("usage limit") || text.contains("rate limit")
      || text.contains("quota")
    {
      return AccessCheck(
        provider: provider, state: .limited, note: "The provider reported a usage or rate limit.")
    }
    return AccessCheck(
      provider: provider, state: .failed,
      note: timedOut
        ? "The provider did not respond in time."
        : "Access could not be verified. Try again or open the provider.")
  }
}
