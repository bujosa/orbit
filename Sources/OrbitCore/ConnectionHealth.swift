import Foundation

public struct ConnectionHealth: Sendable {
  public let online: Bool
  public let networkReady: Bool
  public let servicesReady: Bool
  public let verifiedProviders: Set<Provider>
  public let loginRequired: Set<Provider>
  public let unavailableProviders: Set<Provider>
  public let failedChecks: Set<Provider>
  public var ready: Bool {
    servicesReady && verifiedProviders.count == Provider.allCases.count
  }
  public var needsAttention: Bool {
    !servicesReady || !loginRequired.isEmpty || !unavailableProviders.isEmpty
      || !failedChecks.isEmpty
  }
  public init(snapshot: DeviceSnapshot?, checks: [Provider: AccessCheck], now: Date = Date()) {
    let age = snapshot.map { now.timeIntervalSince($0.capturedAt) }
    online = age.map { $0 >= -30 && $0 <= 120 } == true
    networkReady = online && snapshot?.tailscaleConnected == true
    servicesReady = networkReady && snapshot?.t3Running == true
    var verified: Set<Provider> = []
    var needsLogin: Set<Provider> = []
    var unavailable: Set<Provider> = []
    var failures: Set<Provider> = []
    if online {
      for provider in Provider.allCases {
        let status = snapshot?.providers.first { $0.id == provider }
        let check = checks[provider]
        let fresh = check?.provider == provider && check?.isFresh(now: now) == true
        let rejected =
          check?.provider == provider && check?.state == .loginRequired
          && (check?.checkedAt.timeIntervalSince(now) ?? 0) <= 30
        if [.loginRequired, .expired].contains(status?.auth)
          || rejected
        {
          needsLogin.insert(provider)
        }
        if [.unavailable, .notInstalled].contains(status?.auth) || status == nil {
          unavailable.insert(provider)
        }
        if fresh && [.failed, .limited].contains(check?.state) { failures.insert(provider) }
        if status?.auth == .authenticated, fresh, check?.state == .verified {
          verified.insert(provider)
        }
      }
    }
    verifiedProviders = verified
    loginRequired = needsLogin
    unavailableProviders = unavailable
    failedChecks = failures
  }
}

public struct LoginTarget: Identifiable, Sendable {
  public let id = UUID()
  public let deviceID: UUID
  public let provider: Provider
  public init(deviceID: UUID, provider: Provider) {
    self.deviceID = deviceID
    self.provider = provider
  }
}

public enum LoginPhase: String, Sendable {
  case preparing, awaitingBrowser, authorizing, verifying, ready, failed, cancelled, expired
  public var running: Bool {
    [.preparing, .awaitingBrowser, .authorizing, .verifying].contains(self)
  }
}

public struct LoginProgress: Identifiable, Sendable {
  public let id = UUID()
  public let deviceID: UUID
  public let provider: Provider
  public private(set) var phase: LoginPhase = .preparing
  public private(set) var challenge: LoginChallenge?
  public private(set) var note = "Starting sign-in on this Mac…"
  public init(deviceID: UUID, provider: Provider) {
    self.deviceID = deviceID
    self.provider = provider
  }
  public mutating func receive(_ event: LoginEvent) throws {
    try event.validate(for: provider)
    guard phase.running, phase != .verifying else { return }
    switch event.kind {
    case .starting: note = "Preparing the official provider sign-in…"
    case .challenge:
      phase = .awaitingBrowser
      challenge = event.challenge
      note = "Complete sign-in in your browser. Orbit is waiting on the selected Mac."
    case .signedIn:
      phase = .verifying
      challenge = nil
      note = "Sign-in finished. Checking the saved session and real model access…"
    case .failed:
      phase = .failed
      challenge = nil
      note = "Sign-in did not complete. Check the provider, update the agent, or try again."
    case .busy:
      phase = .failed
      challenge = nil
      note = "Another sign-in is running on this Mac. Finish or cancel it first."
    case .cancelled: cancel()
    case .expired:
      phase = .expired
      challenge = nil
      note = "This sign-in expired. Start again for a new authorization page."
    }
  }
  public mutating func submittedCode() {
    guard phase == .awaitingBrowser else { return }
    phase = .authorizing
    note = "The code was sent privately to the selected Mac. Waiting for the provider…"
  }
  public mutating func complete(authenticated: Bool, check: AccessCheck?) {
    guard phase == .verifying else { return }
    let verified =
      authenticated && check?.provider == provider && check?.isFresh() == true
      && check?.state == .verified
    phase = verified ? .ready : .failed
    challenge = nil
    note =
      verified
      ? "Signed in and verified. This provider is ready on this Mac."
      : check?.note ?? "Sign-in finished, but the saved session could not be verified. Try again."
  }
  public mutating func cancel() {
    guard phase.running else { return }
    phase = .cancelled
    challenge = nil
    note = "Sign-in stopped. Refresh this Mac to check its saved session."
  }
}
