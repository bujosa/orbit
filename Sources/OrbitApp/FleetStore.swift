import AppKit
import Foundation
import OrbitCore
import SwiftUI
import UserNotifications

struct FleetEntry: Identifiable {
  var device: Device
  var snapshot: DeviceSnapshot?
  var error: String?
  var checking = false
  var verifications: [Provider: AccessCheck] = [:]
  var verifying: Set<Provider> = []
  var id: UUID { device.id }
  var online: Bool {
    guard let snapshot, error == nil else { return false }
    return abs(snapshot.capturedAt.timeIntervalSinceNow) < 120
  }
  var verifiedCount: Int {
    guard online else { return 0 }
    return Provider.allCases.filter { provider in
      snapshot?.providers.first(where: { $0.id == provider })?.auth == .authenticated
        && verifications[provider]?.state == .verified && verifications[provider]?.isFresh() == true
    }.count
  }
  func needsLogin(_ provider: Provider) -> Bool {
    guard online else { return false }
    let auth = snapshot?.providers.first(where: { $0.id == provider })?.auth
    return auth == .loginRequired || auth == .expired
      || (verifications[provider]?.isFresh() == true
        && verifications[provider]?.state == .loginRequired)
  }
}

@MainActor
final class FleetStore: ObservableObject {
  static let shared = FleetStore()
  @Published var entries: [FleetEntry] = []
  @Published var selection: UUID?
  @Published var refreshing = false
  @Published var message: String?
  @Published var lastRefresh: Date?
  @Published var notificationsEnabled = UserDefaults.standard.bool(forKey: "Orbit.notifications")
  private let inventory = InventoryStore()
  private var monitor: Task<Void, Never>?

  var localAgent: String {
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/orbit-agent")
      .path
    if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
    return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
      .appendingPathComponent("orbit-agent").path
  }
  private var client: AgentClient { AgentClient(localAgent: localAgent) }
  var onlineCount: Int { entries.filter(\.online).count }
  var verifiedCount: Int { entries.reduce(0) { $0 + $1.verifiedCount } }
  var attentionCount: Int {
    entries.filter { entry in
      entry.error != nil || (entry.online && entry.snapshot?.t3Running == false)
        || Provider.allCases.contains(where: { entry.needsLogin($0) })
    }.count
  }

  init() {
    do {
      entries = try inventory.loadDevices().map { FleetEntry(device: $0) }
      let file = inventory.directory.appendingPathComponent("state.json")
      if let data = try? Data(contentsOf: file),
        let state = try? Wire.decoder.decode([SavedChecks].self, from: data)
      {
        for index in entries.indices {
          entries[index].verifications =
            state.first(where: { $0.deviceID == entries[index].id })?.checks ?? [:]
        }
      }
      selection = entries.first?.id
    } catch { message = "Could not read your local inventory. Check its format and permissions." }
    monitor = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refresh()
        try? await Task.sleep(for: .seconds(60))
      }
    }
  }

  func refresh() async {
    guard !refreshing else { return }
    refreshing = true
    for index in entries.indices { entries[index].checking = true }
    let devices = entries.map(\.device)
    let client = client
    await withTaskGroup(of: (UUID, DeviceSnapshot?, String?).self) { group in
      for device in devices {
        group.addTask {
          do { return (device.id, try await client.snapshot(device), nil) } catch {
            return (
              device.id, nil,
              (error as? OrbitError)?.errorDescription ?? "The agent returned an invalid response."
            )
          }
        }
      }
      for await (id, snapshot, error) in group {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { continue }
        let wasOnline = entries[index].online
        let t3WasRunning = entries[index].snapshot?.t3Running == true
        entries[index].snapshot = snapshot
        entries[index].error = error
        entries[index].checking = false
        if wasOnline && error != nil {
          notify(
            title: "\(entries[index].device.name) is unreachable",
            body: "Check its power, Tailscale connection, and SSH access.",
            key: id.uuidString + "offline")
        }
        if t3WasRunning && snapshot?.t3Running == false {
          notify(
            title: "T3 is unavailable on \(entries[index].device.name)",
            body: "The Mac is reachable, but its T3 service did not respond.",
            key: id.uuidString + "t3")
        }
      }
    }
    refreshing = false
    lastRefresh = Date()
  }

  func verify(_ id: UUID, provider: Provider) async {
    guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].online,
      !entries[index].verifying.contains(provider)
    else { return }
    entries[index].verifying.insert(provider)
    let device = entries[index].device
    let result: AccessCheck
    do { result = try await client.verify(device, provider: provider) } catch {
      result = AccessCheck(
        provider: provider, state: .failed,
        note: (error as? OrbitError)?.errorDescription ?? "The access check could not be completed."
      )
    }
    guard let current = entries.firstIndex(where: { $0.id == id }) else { return }
    entries[current].verifying.remove(provider)
    entries[current].verifications[provider] = result
    persistChecks()
    if result.state == .loginRequired {
      notify(
        title: "\(provider.title) needs sign-in", body: "Open Orbit to reconnect \(device.name).",
        key: id.uuidString + provider.rawValue)
    }
  }

  func verifyAll(_ id: UUID) async {
    for provider in Provider.allCases { await verify(id, provider: provider) }
  }

  func add(_ device: Device) throws {
    try device.validate()
    guard
      !entries.contains(where: {
        $0.device.name.caseInsensitiveCompare(device.name) == .orderedSame
      })
    else { throw OrbitError.invalidDevice }
    try inventory.saveDevices(entries.map(\.device) + [device])
    entries.append(FleetEntry(device: device))
    selection = device.id
    Task { await refresh() }
  }

  func remove(_ id: UUID) {
    do {
      let retained = entries.filter { $0.id != id }
      try inventory.saveDevices(retained.map(\.device))
      entries = retained
      if selection == id { selection = entries.first?.id }
      persistChecks()
    } catch { message = "Could not update the local inventory." }
  }

  func installAgent(_ device: Device) async {
    do {
      try await AgentInstaller.install(on: device, bundledAgent: localAgent)
      await refresh()
    } catch {
      message =
        (error as? OrbitError)?.errorDescription ?? "Agent installation failed. Check SSH access."
    }
  }

  func openTerminal(_ device: Device, provider: Provider? = nil) {
    do {
      let command = try SSHTransport.terminalCommand(
        for: device, provider: provider, localAgent: localAgent)
      let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
        of: "\"", with: "\\\"")
      let script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
      Task {
        let result = try? await ProcessRunner.run(
          "/usr/bin/osascript", ["-e", script], timeout: 15)
        if result?.exit != 0 {
          message =
            "Allow Orbit to open Terminal in System Settings → Privacy & Security → Automation."
        }
      }
      if let provider, let index = entries.firstIndex(where: { $0.id == device.id }) {
        entries[index].verifications.removeValue(forKey: provider)
        persistChecks()
      }
    } catch { message = "This device has an invalid SSH configuration." }
  }

  func openT3(_ device: Device) {
    guard (try? device.validate()) != nil, let url = URL(string: device.t3URL),
      !device.t3URL.isEmpty
    else {
      message = "Add this Mac's T3 HTTPS address to its inventory entry."
      return
    }
    NSWorkspace.shared.open(url)
  }

  func enableNotifications(_ enabled: Bool) {
    if !enabled {
      notificationsEnabled = false
      UserDefaults.standard.set(false, forKey: "Orbit.notifications")
      return
    }
    Task {
      let allowed =
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [
          .alert, .sound,
        ])) ?? false
      notificationsEnabled = allowed
      UserDefaults.standard.set(allowed, forKey: "Orbit.notifications")
      if !allowed {
        message = "Notifications are disabled. You can enable them in System Settings."
      }
    }
  }

  private func notify(title: String, body: String, key: String) {
    guard notificationsEnabled else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: "orbit." + key, content: content, trigger: nil))
  }

  private struct SavedChecks: Codable {
    var deviceID: UUID
    var checks: [Provider: AccessCheck]
  }
  private func persistChecks() {
    do {
      try inventory.write(
        Wire.encoder.encode(entries.map { SavedChecks(deviceID: $0.id, checks: $0.verifications) }),
        name: "state.json")
    } catch { message = "Could not save the latest checks locally." }
  }
}
