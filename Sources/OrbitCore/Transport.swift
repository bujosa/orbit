import Foundation

public enum SSHTransport {
  public static func arguments(for device: Device, interactive: Bool = false) throws -> [String] {
    try device.validate()
    var arguments = [
      "-o", "StrictHostKeyChecking=\(interactive ? "ask" : "yes")", "-o", "ConnectTimeout=8", "-o",
      "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2",
    ]
    if interactive { arguments += ["-t"] } else { arguments += ["-o", "BatchMode=yes", "-T"] }
    if !device.address.isEmpty { arguments += ["-o", "HostName=\(device.address)"] }
    if !device.hostKeyAlias.isEmpty { arguments += ["-o", "HostKeyAlias=\(device.hostKeyAlias)"] }
    arguments += [device.sshAlias]
    return arguments
  }

  public static func shellQuote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }

  public static func terminalCommand(
    for device: Device, provider: Provider? = nil, localAgent: String
  ) throws -> String {
    try device.validate()
    let action = provider.map { "login \($0.rawValue)" } ?? "shell"
    if device.isLocal {
      return provider == nil ? "/bin/zsh -l" : shellQuote(localAgent) + " " + action
    }
    let arguments = try arguments(for: device, interactive: true)
    let remote =
      provider == nil ? "exec /bin/zsh -l" : "exec \"$HOME/.local/bin/orbit-agent\" " + action
    return (["/usr/bin/ssh"] + arguments + [remote]).map(shellQuote).joined(separator: " ")
  }
}

public struct AgentClient: Sendable {
  public var localAgent: String
  public init(localAgent: String) { self.localAgent = localAgent }

  private func call(_ device: Device, action: String, timeout: TimeInterval) async throws
    -> CommandResult
  {
    if device.isLocal {
      return try await ProcessRunner.run(
        localAgent, action.split(separator: " ").map(String.init), timeout: timeout)
    }
    let arguments =
      try SSHTransport.arguments(for: device) + ["exec \"$HOME/.local/bin/orbit-agent\" " + action]
    let result = try await ProcessRunner.run("/usr/bin/ssh", arguments, timeout: timeout)
    if result.exit == 127 { throw OrbitError.agentMissing }
    if result.exit == 255 { throw OrbitError.offline }
    return result
  }

  public func snapshot(_ device: Device) async throws -> DeviceSnapshot {
    let result = try await call(device, action: "snapshot", timeout: 50)
    guard result.exit == 0, !result.timedOut else { throw OrbitError.offline }
    let snapshot = try Wire.decoder.decode(DeviceSnapshot.self, from: result.stdout)
    try snapshot.validate()
    return snapshot
  }

  public func verify(_ device: Device, provider: Provider) async throws -> AccessCheck {
    let result = try await call(device, action: "verify \(provider.rawValue)", timeout: 120)
    guard result.exit == 0, !result.timedOut else { throw OrbitError.offline }
    let check = try Wire.decoder.decode(AccessCheck.self, from: result.stdout)
    guard check.provider == provider, check.isFresh() else { throw OrbitError.incompatibleAgent }
    return check
  }
}
