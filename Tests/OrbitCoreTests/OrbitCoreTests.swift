import XCTest

@testable import OrbitCore

final class OrbitCoreTests: XCTestCase {
  func testGUIChildReceivesAccountIdentityWithoutInheritedUserVariables() throws {
    let environment = SubscriptionEnvironment.forUser(
      ["OPENAI_API_KEY": "example"], home: "/tmp/example", username: "example-user")
    let result = try ProcessRunner.runSync(
      "/bin/sh", ["-c", "printf '%s:%s' \"$USER\" \"$LOGNAME\""], environment: environment)
    XCTAssertEqual(result.text, "example-user:example-user")
    XCTAssertEqual(environment["HOME"], "/tmp/example")
    XCTAssertNil(environment["OPENAI_API_KEY"])
  }
  func testControllerCredentialOverridesCannotShadowDeviceSubscription() {
    var source = [
      "HOME": "/tmp/example", "OPENAI_API_KEY": "example", "CLAUDE_CODE_OAUTH_TOKEN": "example",
      "CURSOR_API_KEY": "example",
    ]
    source["CLAUDE_CONFIG_DIR"] = "/tmp/wrong-account"
    source["CODEX_HOME"] = "/tmp/wrong-account"
    let environment = SubscriptionEnvironment.sanitized(source)
    XCTAssertEqual(environment, ["HOME": "/tmp/example"])
  }
  func testRejectsSSHArgumentAndShellInjection() {
    for alias in [
      "-oProxyCommand=bad", "mac; touch /tmp/bad", "mac\nother", "$(whoami)", "mac@evil",
    ] {
      XCTAssertThrowsError(try Device(name: "Studio", sshAlias: alias).validate())
    }
    XCTAssertThrowsError(
      try Device(name: "Studio", sshAlias: "studio", address: "host -oProxyCommand=bad").validate())
  }

  func testPinsKnownHostAndRefusesUnattendedTrust() throws {
    let device = Device(
      name: "Studio", sshAlias: "studio", address: "100.100.100.100", hostKeyAlias: "192.0.2.10")
    let arguments = try SSHTransport.arguments(for: device)
    XCTAssertTrue(arguments.contains("StrictHostKeyChecking=yes"))
    XCTAssertTrue(arguments.contains("BatchMode=yes"))
    XCTAssertTrue(arguments.contains("HostKeyAlias=192.0.2.10"))
    XCTAssertTrue(arguments.contains("HostName=100.100.100.100"))
    XCTAssertEqual(arguments.last, "studio")
  }

  func testTerminalEscapesAPathContainingShellMetacharacters() throws {
    let path = "/tmp/a'$(touch injected)/orbit-agent"
    let command = try SSHTransport.terminalCommand(
      for: Device(name: "Local", isLocal: true), provider: .codex, localAgent: path)
    let result = try ProcessRunner.runSync(
      "/bin/sh", ["-c", "set -- \(command); printf '%s' \"$1\""])
    XCTAssertEqual(result.text, path)
  }

  func testRejectsSecretBearingAndNonWebURLs() {
    for url in [
      "file:///etc/passwd", "javascript:alert(1)", "http://public.example",
      "https://user:secret@example.test", "https://example.test/?token=secret",
    ] {
      XCTAssertThrowsError(try Device(name: "Local", isLocal: true, t3URL: url).validate())
    }
    XCTAssertNoThrow(
      try Device(name: "Local", isLocal: true, t3URL: "http://127.0.0.1:3000").validate())
  }

  func testSavedAuthenticationCannotCountAsVerifiedAccess() {
    let result = SafeStatus.access(
      provider: .claude, exit: 0, output: "loggedIn: true", timedOut: false)
    XCTAssertEqual(result.state, .failed)
    XCTAssertEqual(
      SafeStatus.access(provider: .claude, exit: 0, output: "ORBIT_OK", timedOut: false).state,
      .verified)
    XCTAssertNotEqual(
      SafeStatus.access(provider: .claude, exit: 1, output: "ORBIT_OK", timedOut: false).state,
      .verified)
  }

  func testAuthFailureAndLimitsAreSeparateAndDiagnosticsAreNotForwarded() {
    let secret = "sensitive-value-that-must-stay-local"
    let rejected = SafeStatus.access(
      provider: .codex, exit: 1, output: "401 Failed to authenticate \(secret)", timedOut: false)
    XCTAssertEqual(rejected.state, .loginRequired)
    XCTAssertFalse(rejected.note.contains(secret))
    XCTAssertEqual(
      SafeStatus.access(provider: .grok, exit: 1, output: "429 rate limit", timedOut: false).state,
      .limited)
    XCTAssertEqual(
      SafeStatus.access(provider: .cursor, exit: 0, output: "ORBIT_OK", timedOut: true).state,
      .failed)
  }

  func testOldAndFutureChecksDoNotAppearCurrent() {
    let now = Date(timeIntervalSince1970: 10_000)
    XCTAssertFalse(
      AccessCheck(
        provider: .codex, state: .verified, checkedAt: now.addingTimeInterval(-901), note: ""
      ).isFresh(now: now))
    XCTAssertFalse(
      AccessCheck(
        provider: .codex, state: .verified, checkedAt: now.addingTimeInterval(31), note: ""
      ).isFresh(now: now))
    XCTAssertTrue(
      AccessCheck(
        provider: .codex, state: .verified, checkedAt: now.addingTimeInterval(-100), note: ""
      ).isFresh(now: now))
  }

  func testSnapshotRejectsUnsupportedSchemaAndMissingProvider() {
    var snapshot = DeviceSnapshot(
      hostname: "test", t3Running: true, tailscaleConnected: true,
      providers: Provider.allCases.map { ProviderStatus(id: $0, auth: .authenticated, note: "") })
    XCTAssertNoThrow(try snapshot.validate())
    snapshot.schemaVersion = 2
    XCTAssertThrowsError(try snapshot.validate())
    snapshot.schemaVersion = 1
    snapshot.providers.removeLast()
    XCTAssertThrowsError(try snapshot.validate())
  }

  func testInventoryIsPrivateAndRejectsDuplicateIdentity() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = InventoryStore(directory: root)
    let device = Device(name: "Local", isLocal: true)
    try store.saveDevices([device])
    XCTAssertEqual(try store.loadDevices(), [device])
    let attributes = try FileManager.default.attributesOfItem(
      atPath: root.appendingPathComponent("devices.json").path)
    XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    XCTAssertThrowsError(try store.saveDevices([device, device]))
    XCTAssertThrowsError(try store.write(Data(), name: "../outside.json"))
  }

  func testInventoryRefusesSymlinkWrite() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let outside = root.appendingPathComponent("outside")
    try Data("preserve".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("devices.json"), withDestinationURL: outside)
    XCTAssertThrowsError(
      try InventoryStore(directory: root).saveDevices([Device(name: "Local", isLocal: true)]))
    XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "preserve")
  }

  func testRunnerTimesOutAndCapturesBothStreams() throws {
    let result = try ProcessRunner.runSync("/bin/sh", ["-c", "printf hello; printf problem >&2"])
    XCTAssertEqual(result.text, "hello")
    XCTAssertEqual(String(decoding: result.stderr, as: UTF8.self), "problem")
    let timeout = try ProcessRunner.runSync("/bin/sleep", ["5"], timeout: 0.1)
    XCTAssertTrue(timeout.timedOut)
    XCTAssertNotEqual(timeout.exit, 0)
  }

  func testEmailMaskingDoesNotExposeTheMailbox() {
    XCTAssertEqual(SafeStatus.maskedEmail("someone@example.test"), "s•••@example.test")
    XCTAssertNil(SafeStatus.maskedEmail("invalid"))
  }
}
