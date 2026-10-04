import Foundation

public enum AgentInstaller {
  public static func install(on device: Device, bundledAgent: String) async throws {
    guard !device.isLocal else { return }
    let payload = try Data(contentsOf: URL(fileURLWithPath: bundledAgent))
    let name = "orbit-agent-" + UUID().uuidString
    let command = """
      set -eu
      umask 077
      base="$HOME/.local/share/orbit"
      dest="$HOME/.local/bin/orbit-agent"
      for dir in "$base" "$base/agents"; do
        if [ -L "$dir" ]; then exit 73; fi
      done
      if [ -e "$dest" ] || [ -L "$dest" ]; then
        case "$(readlink "$dest")" in "$base/agents/"*) ;; *) exit 73 ;; esac
      fi
      mkdir -p "$base/agents" "$HOME/.local/bin"
      target="$base/agents/\(name)"
      cat > "$target"
      chmod 755 "$target"
      "$target" --version >/dev/null
        ln -s "$target" "$target.launcher"
        mv -f "$target.launcher" "$dest"
      """
    let result = try await ProcessRunner.run(
      "/usr/bin/ssh", try SSHTransport.arguments(for: device) + [command], timeout: 45,
      stdin: payload)
    if result.exit == 73 { throw OrbitError.unsafeFile }
    guard result.exit == 0, !result.timedOut else { throw OrbitError.offline }
  }
}
