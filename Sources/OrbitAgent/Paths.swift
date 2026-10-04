import Foundation
import OrbitCore

enum Paths {
  static let home = FileManager.default.homeDirectoryForCurrentUser
  static func executable(_ candidates: [String]) -> String? {
    candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }
  static var claude: String? {
    let local = home.appendingPathComponent(".local/bin/claude").path
    let attributes = try? FileManager.default.attributesOfItem(atPath: local)
    // Preserve a device's subscription launcher. Prefer the native installation over a second npm symlink.
    if attributes?[.type] as? FileAttributeType == .typeRegular,
      FileManager.default.isExecutableFile(atPath: local)
    {
      return local
    }
    return executable(["/opt/homebrew/bin/claude", "/usr/local/bin/claude", local])
  }
  static var nativeClaude: String? {
    executable(["/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
  }
  static var codex: String? {
    executable([
      home.appendingPathComponent(".local/bin/codex").path, "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
    ])
  }
  // Prefer the official Grok Build. Never fall back to the unrelated legacy Homebrew CLI.
  static var grok: String? { executable([home.appendingPathComponent(".grok/bin/grok").path]) }
  static var node: String? {
    executable([
      "/opt/homebrew/bin/node", "/usr/local/bin/node",
      home.appendingPathComponent(".local/bin/node").path,
    ])
  }
  static var tailscale: String? {
    executable([
      "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale",
      "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ])
  }

  static var cursorSDK: String? {
    let adjacent = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
      .appendingPathComponent("cursor-runtime/node_modules/@cursor/sdk").path
    let versions = home.appendingPathComponent(".t3/runtime/versions")
    let directories =
      (try? FileManager.default.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil))
      ?? []
    let candidates =
      [
        adjacent,
        home.appendingPathComponent(".local/share/orbit/runtime/node_modules/@cursor/sdk").path,
      ]
      + directories.sorted { $0.lastPathComponent > $1.lastPathComponent }.map {
        $0.appendingPathComponent("node_modules/@cursor/sdk").path
      } + [
        "/Applications/T3 Code.app/Contents/Resources/app.asar.unpacked/node_modules/@cursor/sdk",
        "/Applications/T3 Code Nightly.app/Contents/Resources/app.asar.unpacked/node_modules/@cursor/sdk",
      ]
    return candidates.first { FileManager.default.fileExists(atPath: $0 + "/package.json") }
  }

  static var cleanEnvironment: [String: String] {
    // GUI launches can omit these variables; Claude's macOS credential lookup uses USER.
    return SubscriptionEnvironment.forUser(
      ProcessInfo.processInfo.environment, home: home.path, username: NSUserName())
  }
}
