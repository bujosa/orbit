import Darwin
import Foundation
import OrbitCore

enum Login {
  static func command(_ provider: Provider) throws -> (String, [String], Data?) {
    switch provider {
    case .claude:
      guard let binary = Paths.nativeClaude else { throw OrbitError.agentMissing }
      return (binary, ["auth", "login", "--claudeai"], nil)
    case .codex:
      guard let binary = Paths.codex else { throw OrbitError.agentMissing }
      return (binary, ["login", "--device-auth"], nil)
    case .grok:
      guard let binary = Paths.grok else { throw OrbitError.agentMissing }
      return (binary, ["login", "--device-auth"], nil)
    case .cursor:
      guard let sdk = Paths.cursorSDK, let node = Paths.node else { throw OrbitError.agentMissing }
      return (
        node, ["-e", CursorBridge.source],
        try JSONSerialization.data(
          withJSONObject: ["sdk": sdk, "action": "login"])
      )
    }
  }

  static func didSucceed(_ provider: Provider) throws {
    if provider == .claude { try retireRecognizedSharedToken(environment: Paths.cleanEnvironment) }
  }
  static func run(_ provider: Provider) throws -> Int32 {
    if provider == .cursor { return try CursorBridge.login() }
    let binary: String?
    let arguments: [String]
    var environment = Paths.cleanEnvironment
    switch provider {
    case .claude:
      binary = Paths.nativeClaude
      arguments = ["auth", "login", "--claudeai"]
      environment.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
      print("This signs this Mac into your Claude subscription independently.")
      print(
        "After success, Orbit archives its recognized shared-token file so the new session can be used."
      )
    case .codex:
      binary = Paths.codex
      arguments = ["login", "--device-auth"]
    case .grok:
      binary = Paths.grok
      arguments = ["login", "--device-auth"]
    case .cursor: fatalError("Handled above")
    }
    guard let binary else { throw OrbitError.agentMissing }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = arguments
    process.environment = environment
    process.standardInput = FileHandle.standardInput
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0 && provider == .claude {
      try retireRecognizedSharedToken(environment: environment)
    }
    return process.terminationStatus
  }

  private static func retireRecognizedSharedToken(environment: [String: String]) throws {
    let file = Paths.home.appendingPathComponent(".t3/claude.env")
    guard FileManager.default.fileExists(atPath: file.path) else { return }
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      attributes[.ownerAccountID] as? UInt32 == getuid(),
      (attributes[.posixPermissions] as? Int ?? 0) & 0o077 == 0
    else { throw OrbitError.unsafeFile }
    let contents = try String(contentsOf: file, encoding: .utf8)
    let lines = contents.split(separator: "\n").map(String.init).filter {
      !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#")
    }
    guard lines.count == 1, lines[0].hasPrefix("export CLAUDE_CODE_OAUTH_TOKEN=") else {
      throw OrbitError.unsafeFile
    }
    let wrapper = Paths.home.appendingPathComponent(".local/bin/claude")
    let wrapperAttributes = try FileManager.default.attributesOfItem(atPath: wrapper.path)
    guard wrapperAttributes[.type] as? FileAttributeType == .typeRegular,
      wrapperAttributes[.ownerAccountID] as? UInt32 == getuid(),
      (wrapperAttributes[.posixPermissions] as? Int ?? 0) & 0o022 == 0
    else { throw OrbitError.unsafeFile }
    let wrapperText = (try? String(contentsOf: wrapper, encoding: .utf8)) ?? ""
    guard
      wrapperText.contains(
        "# Use the existing Claude subscription credential for T3 and local CLI sessions.")
        || wrapperText.contains("# Orbit-managed Claude launcher")
    else { throw OrbitError.unsafeFile }
    guard let native = Paths.nativeClaude else { throw OrbitError.agentMissing }
    let status = try ProcessRunner.runSync(native, ["auth", "status"], environment: environment)
    guard status.exit == 0,
      let object = try JSONSerialization.jsonObject(with: status.stdout) as? [String: Any],
      object["loggedIn"] as? Bool == true
    else { throw OrbitError.unsafeFile }
    let archive = Paths.home.appendingPathComponent(".t3/credentials/archive")
    try FileManager.default.createDirectory(
      at: archive, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    // Preserve the previous credential for deliberate, local recovery; never copy it to Orbit.
    let backup = archive.appendingPathComponent("claude-" + UUID().uuidString + ".env")
    let updated = """
      #!/bin/sh
      # Orbit-managed Claude launcher
      if [ -r "$HOME/.t3/claude.env" ]; then
        set -a
        . "$HOME/.t3/claude.env"
        set +a
      else
        unset CLAUDE_CODE_OAUTH_TOKEN
      fi
      exec \(SSHTransport.shellQuote(native)) "$@"

      """
    try updated.write(to: wrapper, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
    try FileManager.default.moveItem(at: file, to: backup)
    print(
      "Independent Claude session ready. The previous shared credential was kept in a private local archive."
    )
  }
}
