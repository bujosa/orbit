import XCTest

@testable import OrbitCore

final class ConnectionTests: XCTestCase {
  func testAuthenticationRejectionRemainsActionableAfterVerificationTTL() {
    let snapshot = DeviceSnapshot(
      hostname: "Example", t3Running: true, tailscaleConnected: true,
      providers: Provider.allCases.map { ProviderStatus(id: $0, auth: .authenticated, note: "") })
    let rejected = AccessCheck(
      provider: .codex, state: .loginRequired,
      checkedAt: Date().addingTimeInterval(-3600), note: "Sign in required")
    let health = ConnectionHealth(snapshot: snapshot, checks: [.codex: rejected])
    XCTAssertTrue(health.loginRequired.contains(.codex))
    XCTAssertTrue(health.needsAttention)
    let accepted = AccessCheck(provider: .codex, state: .verified, note: "Verified")
    XCTAssertFalse(
      ConnectionHealth(snapshot: snapshot, checks: [.codex: accepted]).loginRequired.contains(
        .codex))
  }
  func testChallengesRejectUntrustedHostsCredentialQueriesAndUnsafeRedirects() throws {
    for url in [
      "https://auth.openai.com.evil.test/codex/device",
      "https://auth.openai.com/codex/device?access_token=example",
      "https://user:example@auth.openai.com/codex/device",
      "https://auth.openai.com:443/codex/device",
      "http://auth.openai.com/codex/device", "https://auth.openai.com/unrelated",
    ] { XCTAssertThrowsError(try LoginChallenge(url: url).validate(for: .codex)) }
    XCTAssertThrowsError(
      try LoginChallenge(
        url:
          "https://claude.com/cai/oauth/authorize?redirect_uri=https%3A%2F%2Fevil.test%2Fcallback",
        requiresCodeEntry: true
      ).validate(for: .claude))
    XCTAssertNoThrow(
      try LoginChallenge(
        url:
          "https://cursor.com/loginDeepControl?challenge=example&uuid=example&mode=login&redirectTarget=cli"
      ).validate(for: .cursor))
  }

  func testParserWaitsForCompleteURLAndDeviceCodeAndNeverExportsDiagnostics() throws {
    var parser = LoginOutputParser(provider: .codex)
    XCTAssertNil(
      parser.consume(Data("internal access_token=example\nhttps://auth.openai.com/codex/dev".utf8)))
    let first = parser.consume(Data("ice\n".utf8))
    XCTAssertEqual(first?.url, "https://auth.openai.com/codex/device")
    XCTAssertNil(first?.userCode)
    let second = parser.consume(Data("\u{1B}[32mABCD-EFGHI\u{1B}[0m\n".utf8))
    XCTAssertEqual(second?.userCode, "ABCD-EFGHI")
    XCTAssertNil(parser.consume(Data("unchanged\n".utf8)))
    XCTAssertFalse(
      String(decoding: try Wire.encoder.encode(second), as: UTF8.self).contains("access_token"))
  }

  func testAuthorizationInputCannotBecomeTerminalOrShellCommands() {
    for code in [
      "one\ntwo", "$(touch example)", "\u{1B}[A", "code; command",
      String(repeating: "x", count: 2049),
    ] {
      XCTAssertThrowsError(try LoginInput(action: .code, code: code).validate(for: .claude))
    }
    XCTAssertNoThrow(
      try LoginInput(action: .code, code: "example-code#example-state").validate(for: .claude))
    XCTAssertThrowsError(try LoginInput(action: .code, code: "example").validate(for: .codex))
    XCTAssertThrowsError(try LoginInput(action: .cancel, code: "example").validate(for: .claude))
  }

  func testSignInCannotBecomeReadyWithoutFreshMatchingModelVerification() throws {
    var flow = LoginProgress(deviceID: UUID(), provider: .cursor)
    try flow.receive(
      LoginEvent(
        provider: .cursor, kind: .challenge,
        challenge: LoginChallenge(url: "https://cursor.com/loginDeepControl?challenge=example")))
    try flow.receive(LoginEvent(provider: .cursor, kind: .signedIn))
    XCTAssertEqual(flow.phase, .verifying)
    XCTAssertNil(flow.challenge)
    flow.complete(
      authenticated: true,
      check: AccessCheck(provider: .cursor, state: .failed, note: "Unavailable"))
    XCTAssertEqual(flow.phase, .failed)
    var other = LoginProgress(deviceID: UUID(), provider: .cursor)
    try other.receive(LoginEvent(provider: .cursor, kind: .signedIn))
    other.complete(
      authenticated: true, check: AccessCheck(provider: .codex, state: .verified, note: ""))
    XCTAssertEqual(other.phase, .failed)
    var ready = LoginProgress(deviceID: UUID(), provider: .cursor)
    try ready.receive(LoginEvent(provider: .cursor, kind: .signedIn))
    ready.complete(
      authenticated: true, check: AccessCheck(provider: .cursor, state: .verified, note: ""))
    XCTAssertEqual(ready.phase, .ready)
  }

  func testCancelClearsChallengeAndLateCompletionCannotMarkReady() throws {
    var flow = LoginProgress(deviceID: UUID(), provider: .codex)
    try flow.receive(
      LoginEvent(
        provider: .codex, kind: .challenge,
        challenge: LoginChallenge(
          url: "https://auth.openai.com/codex/device", userCode: "ABCD-EFGHI")))
    flow.cancel()
    try flow.receive(LoginEvent(provider: .codex, kind: .signedIn))
    flow.complete(
      authenticated: true, check: AccessCheck(provider: .codex, state: .verified, note: ""))
    XCTAssertEqual(flow.phase, .cancelled)
    XCTAssertNil(flow.challenge)
  }

  func testFleetReadinessRequiresNetworkServicesAndAllProviderAccess() {
    let now = Date()
    var snapshot = DeviceSnapshot(
      hostname: "Example", t3Running: true, tailscaleConnected: true,
      providers: Provider.allCases.map { ProviderStatus(id: $0, auth: .authenticated, note: "") })
    var checks = Dictionary(
      uniqueKeysWithValues: Provider.allCases.map {
        ($0, AccessCheck(provider: $0, state: .verified, checkedAt: now, note: ""))
      })
    XCTAssertTrue(ConnectionHealth(snapshot: snapshot, checks: checks, now: now).ready)
    checks[.claude] = AccessCheck(provider: .claude, state: .failed, note: "Timeout")
    let failed = ConnectionHealth(snapshot: snapshot, checks: checks, now: now)
    XCTAssertFalse(failed.ready)
    XCTAssertTrue(failed.needsAttention)
    snapshot.tailscaleConnected = false
    XCTAssertFalse(ConnectionHealth(snapshot: snapshot, checks: checks, now: now).ready)
    snapshot.capturedAt = now.addingTimeInterval(-121)
    XCTAssertEqual(
      ConnectionHealth(snapshot: snapshot, checks: checks, now: now).verifiedProviders.count, 0)
  }

  func testManagedLoginStreamsBeforeExitAndCancellationFinishes() async throws {
    let session = try ManagedLogin(
      executable: "/bin/sh",
      arguments: [
        "-c",
        "printf '%s\\n' '{\"schemaVersion\":1,\"provider\":\"codex\",\"kind\":\"starting\"}'; read command",
      ], provider: .codex, timeout: 5)
    let started = expectation(description: "Started before child exits")
    let reader = Task { () -> [LoginEventKind] in
      var kinds: [LoginEventKind] = []
      for await event in session.events {
        kinds.append(event.kind)
        if event.kind == .starting { started.fulfill() }
      }
      return kinds
    }
    await fulfillment(of: [started], timeout: 2)
    session.cancel()
    let kinds = await reader.value
    XCTAssertEqual(kinds, [.starting, .cancelled])
  }

  func testManagedLoginRejectsFalseSuccessNonzeroExitAndWrongProvider() async throws {
    for (provider, exit) in [("codex", 1), ("cursor", 0)] {
      let session = try ManagedLogin(
        executable: "/bin/sh",
        arguments: [
          "-c",
          "printf '%s\\n' '{\"schemaVersion\":1,\"provider\":\"\(provider)\",\"kind\":\"signedIn\"}'; exit \(exit)",
        ], provider: .codex)
      var kinds: [LoginEventKind] = []
      for await event in session.events { kinds.append(event.kind) }
      XCTAssertEqual(kinds, [.failed])
    }
  }

  func testManagedLoginRelaysCodePrivatelyAndOnlyCompletesAfterProcessSuccess() async throws {
    let starting =
      #"{"schemaVersion":1,"provider":"claude","kind":"challenge","challenge":{"url":"https://claude.com/cai/oauth/authorize?code=true","requiresCodeEntry":true}}"#
    let signedIn = #"{"schemaVersion":1,"provider":"claude","kind":"signedIn"}"#
    let script =
      "printf '%s\\n' \(SSHTransport.shellQuote(starting)); read command; case \"$command\" in *example-code*) printf '%s\\n' \(SSHTransport.shellQuote(signedIn));; *) exit 1;; esac"
    let session = try ManagedLogin(
      executable: "/bin/sh", arguments: ["-c", script], provider: .claude, timeout: 5)
    var kinds: [LoginEventKind] = []
    for await event in session.events {
      kinds.append(event.kind)
      if event.kind == .challenge { try session.submit(code: "example-code") }
    }
    XCTAssertEqual(kinds, [.challenge, .signedIn])
  }

  func testManagedLoginDeadlineIsReportedAsExpired() async throws {
    let session = try ManagedLogin(
      executable: "/bin/sleep", arguments: ["5"], provider: .codex, timeout: 0.05)
    var kinds: [LoginEventKind] = []
    for await event in session.events { kinds.append(event.kind) }
    XCTAssertEqual(kinds, [.expired])
  }

  func testFleetConnectionSkipsVerifiedAndMissingLoginsAndUsesActualAgentChecks() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let agent = directory.appendingPathComponent("agent")
    let log = directory.appendingPathComponent("calls")
    let codex = String(
      decoding: try Wire.encoder.encode(
        AccessCheck(provider: .codex, state: .verified, note: "Verified")), as: UTF8.self)
    let grok = String(
      decoding: try Wire.encoder.encode(
        AccessCheck(provider: .grok, state: .limited, note: "Usage limited")), as: UTF8.self)
    let script =
      "#!/bin/sh\nprintf '%s\\n' \"$2\" >> \(SSHTransport.shellQuote(log.path))\ncase \"$2\" in\ncodex) printf '%s\\n' \(SSHTransport.shellQuote(codex));;\ngrok) printf '%s\\n' \(SSHTransport.shellQuote(grok));;\n*) exit 1;;\nesac\n"
    try script.write(to: agent, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
    let device = Device(name: "Example", isLocal: true)
    let snapshot = DeviceSnapshot(
      hostname: "Example", t3Running: true, tailscaleConnected: true,
      providers: Provider.allCases.map {
        ProviderStatus(id: $0, auth: $0 == .claude ? .loginRequired : .authenticated, note: "")
      })
    let results = await FleetCoordinator(client: AgentClient(localAgent: agent.path)).connect(
      device: device, snapshot: snapshot,
      checks: [.cursor: AccessCheck(provider: .cursor, state: .verified, note: "")],
      onCheck: { _, _ in })
    XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), "codex\ngrok\n")
    XCTAssertEqual(results[.codex]?.state, .verified)
    XCTAssertEqual(results[.grok]?.state, .limited)
    XCTAssertNil(results[.claude])
    XCTAssertFalse(ConnectionHealth(snapshot: snapshot, checks: results).ready)
  }
}
