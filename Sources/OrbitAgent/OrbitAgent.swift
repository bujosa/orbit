import Darwin
import Foundation
import OrbitCore

@main
struct OrbitAgent {
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    do {
      switch arguments.first {
      case "snapshot": try emit(await Probe.snapshot())
      case "verify":
        guard arguments.count == 2, let provider = Provider(rawValue: arguments[1]) else {
          throw OrbitError.invalidDevice
        }
        try emit(await Probe.verify(provider))
      case "login":
        guard arguments.count == 2, let provider = Provider(rawValue: arguments[1]) else {
          throw OrbitError.invalidDevice
        }
        exit(try Login.run(provider))
      case "--version": print("orbit-agent 0.1.0 (schema 1)")
      default:
        print("Usage: orbit-agent snapshot | verify <claude|codex|grok|cursor> | login <provider>")
        exit(64)
      }
    } catch {
      // Errors are fixed messages, never subprocess stderr or credential contents.
      let message =
        (error as? OrbitError)?.errorDescription ?? "Orbit could not complete this operation."
      FileHandle.standardError.write(Data((message + "\n").utf8))
      exit(1)
    }
  }

  static func emit<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try Wire.encoder.encode(value))
    print("")
  }
}
