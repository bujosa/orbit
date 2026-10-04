import Darwin
import Foundation
import OrbitCore

private struct ProviderReport: Codable {
  var provider: Provider
  var auth: AuthState
  var access: String
  var checkedAt: Date?
}
private struct DeviceReport: Codable {
  var deviceID: UUID
  var name: String
  var reachable: Bool
  var tailscale: Bool
  var t3: Bool
  var ready: Bool
  var providers: [ProviderReport]
  var error: String?
}
private struct FleetReport: Codable {
  var schemaVersion = 1
  var capturedAt = Date()
  var devices: [DeviceReport]
}

@main
struct OrbitController {
  static func main() async {
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      guard let action = args.first, ["status", "connect", "install-agents"].contains(action),
        args.count <= 2
      else {
        print(
          "Usage: orbitctl status | orbitctl connect <device-name|--all> | orbitctl install-agents <device-name|--all>"
        )
        exit(64)
      }
      if action != "status", args.count != 2 {
        print("Choose a device or --all. Connection checks send small model requests.")
        exit(64)
      }
      let inventory = InventoryStore()
      let allDevices = try inventory.loadDevices()
      let devices =
        args.count == 2 && args[1] != "--all"
        ? allDevices.filter { $0.name.caseInsensitiveCompare(args[1]) == .orderedSame } : allDevices
      guard !devices.isEmpty else { throw OrbitError.invalidDevice }
      var saved = try inventory.loadChecks()
      let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
      let adjacent = executable.deletingLastPathComponent().appendingPathComponent("orbit-agent")
      let bundled = executable.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/orbit-agent")
      let agent =
        FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled.path : adjacent.path
      let client = AgentClient(localAgent: agent)
      var reports: [DeviceReport] = []
      await withTaskGroup(of: (DeviceReport, StoredChecks?).self) { group in
        for device in devices {
          let existing = saved.first { $0.deviceID == device.id }?.checks ?? [:]
          group.addTask {
            do {
              if action == "install-agents" {
                try await AgentInstaller.install(on: device, bundledAgent: agent)
              }
              var snapshot = try await client.snapshot(device)
              let checks =
                action == "connect"
                ? await FleetCoordinator(client: client).connect(
                  device: device, snapshot: snapshot,
                  checks: existing, onCheck: { _, _ in }) : existing
              // Long checks must not make the final status depend on an aging initial snapshot.
              if action == "connect" { snapshot = try await client.snapshot(device) }
              let health = ConnectionHealth(snapshot: snapshot, checks: checks)
              let providers = snapshot.providers.map { status in
                let check = checks[status.id]
                return ProviderReport(
                  provider: status.id, auth: status.auth,
                  access: health.verifiedProviders.contains(status.id)
                    ? "verified"
                    : health.loginRequired.contains(status.id)
                      ? "loginRequired"
                      : check?.isFresh() == true && check?.state != .verified
                        ? check!.state.rawValue : "unverified",
                  checkedAt: check?.checkedAt)
              }
              return (
                DeviceReport(
                  deviceID: device.id, name: device.name, reachable: health.online,
                  tailscale: health.networkReady, t3: snapshot.t3Running, ready: health.ready,
                  providers: providers, error: nil),
                action == "connect" ? StoredChecks(deviceID: device.id, checks: checks) : nil
              )
            } catch {
              return (
                DeviceReport(
                  deviceID: device.id, name: device.name, reachable: false,
                  tailscale: false, t3: false, ready: false, providers: [],
                  error: (error as? OrbitError)?.errorDescription
                    ?? "The agent returned an invalid response."), nil
              )
            }
          }
        }
        for await (report, checks) in group {
          reports.append(report)
          if let checks {
            saved.removeAll { $0.deviceID == checks.deviceID }
            saved.append(checks)
          }
        }
      }
      if action == "connect" { try inventory.saveChecks(saved) }
      reports.sort { $0.name < $1.name }
      let data = try Wire.encoder.encode(FleetReport(devices: reports))
      try FileHandle.standardOutput.write(contentsOf: data + Data([10]))
      if action == "connect" && reports.contains(where: { !$0.ready }) { exit(1) }
      if action == "install-agents" && reports.contains(where: { $0.error != nil }) { exit(1) }
    } catch {
      let message =
        (error as? OrbitError)?.errorDescription ?? "Orbit could not read the local fleet state."
      try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
      exit(1)
    }
  }
}
