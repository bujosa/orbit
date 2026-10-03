import Foundation

public enum SubscriptionEnvironment {
  public static func forUser(_ inherited: [String: String], home: String, username: String)
    -> [String: String]
  {
    var environment = sanitized(inherited)
    environment["HOME"] = home
    environment["USER"] = username
    environment["LOGNAME"] = username
    environment["SHELL"] = "/bin/zsh"
    environment["PATH"] =
      "\(home)/.local/bin:\(home)/.grok/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    return environment
  }

  public static func sanitized(_ inherited: [String: String]) -> [String: String] {
    // Keep terminal/system context, but never inherit a provider identity or credential override.
    let allowed: Set<String> = [
      "HOME", "USER", "LOGNAME", "PATH", "SHELL", "TMPDIR", "LANG", "LC_ALL",
      "TERM", "COLORTERM", "SSH_AUTH_SOCK", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY",
      "https_proxy", "http_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR",
    ]
    return inherited.filter { allowed.contains($0.key) }
  }
}
