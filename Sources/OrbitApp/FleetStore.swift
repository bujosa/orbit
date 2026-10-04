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
  var health: ConnectionHealth {
    ConnectionHealth(snapshot: error == nil ? snapshot : nil, checks: verifications)
  }
  var online: Bool {
    health.online
  }
  var verifiedCount: Int {
    health.verifiedProviders.count
  }
  func needsLogin(_ provider: Provider) -> Bool {
    health.loginRequired.contains(provider)
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
  @Published var login: LoginProgress?
  @Published var loginInputError: String?
  @Published private(set) var reconnection = ReconnectionQueue()
  var reconnectQueue: [LoginTarget] { reconnection.pending }
  @Published var reconnecting = false
  @Published var connectingFleet = false
  @Published var connectionNote: String?
  @Published var privacyMode = UserDefaults.standard.bool(forKey: "Orbit.privacyMode")
  @Published var notificationsEnabled = UserDefaults.standard.bool(forKey: "Orbit.notifications")
  private let inventory = InventoryStore()
  private var monitor: Task<Void, Never>?
  private var loginProcess: ManagedLogin?

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
    entries.filter { $0.error != nil || ($0.snapshot != nil && $0.health.needsAttention) }.count
  }
  var readyCount: Int { entries.filter { $0.health.ready }.count }
  var connectionBusy: Bool { connectingFleet || reconnecting || login?.phase.running == true }
  func displayName(_ device: Device) -> String {
    guard privacyMode else { return device.name }
    let number = (entries.firstIndex { $0.id == device.id } ?? 0) + 1
    return "Mac \(number)"
  }
  func setPrivacyMode(_ enabled: Bool) {
    privacyMode = enabled
    UserDefaults.standard.set(enabled, forKey: "Orbit.privacyMode")
  }
  private var connectionSummary: String {
    readyCount == entries.count && !entries.isEmpty
      ? "Every Mac and provider is connected and verified."
      : "\(readyCount) of \(entries.count) Macs ready. Follow the actions below for anything that needs attention."
  }

  init() {
    do {
      entries = try inventory.loadDevices().map { FleetEntry(device: $0) }
      if let state = try? inventory.loadChecks() {
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

  func refresh(_ deviceID: UUID? = nil) async {
    while refreshing {
      guard !Task.isCancelled else { return }
      try? await Task.sleep(for: .milliseconds(100))
    }
    refreshing = true
    // Status is read-only. Keep reachability current even while a provider login is waiting.
    let devices = entries.filter { deviceID == nil || $0.id == deviceID }.map(\.device)
    importSavedChecks()
    for index in entries.indices {
      entries[index].checking = devices.contains { $0.id == entries[index].id }
    }
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
            title: "\(displayName(entries[index].device)) is unreachable",
            body: "Check its power, Tailscale connection, and SSH access.",
            key: id.uuidString + "offline")
        }
        if t3WasRunning && snapshot?.t3Running == false {
          notify(
            title: "T3 is unavailable on \(displayName(entries[index].device))",
            body: "The Mac is reachable, but its T3 service did not respond.",
            key: id.uuidString + "t3")
        }
      }
    }
    refreshing = false
    lastRefresh = Date()
  }

  func verify(_ id: UUID, provider: Provider, afterLogin: UUID? = nil) async {
    let completingLogin = afterLogin != nil && login?.id == afterLogin && login?.phase == .verifying
    guard !connectionBusy || completingLogin else { return }
    guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].online,
      !entries[index].verifying.contains(provider),
      !(login?.phase.running == true && login?.deviceID == id && login?.phase != .verifying)
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
        title: "\(provider.title) needs sign-in",
        body: "Open Orbit to reconnect \(displayName(device)).",
        key: id.uuidString + provider.rawValue)
    }
  }

  func verifyAll(_ id: UUID) async {
    for provider in Provider.allCases { await verify(id, provider: provider) }
  }

  func connectFleet() async {
    guard !connectionBusy, entries.allSatisfy({ $0.verifying.isEmpty }) else { return }
    connectingFleet = true
    connectionNote = "Checking connections and verifying saved sessions…"
    await refresh()
    let ids = entries.filter(\.online).map(\.id)
    await withTaskGroup(of: Void.self) { group in
      for id in ids {
        group.addTask { await self.verifySavedSessions(id) }
      }
    }
    connectingFleet = false
    connectionNote = connectionSummary
  }

  func reconnectAccounts() async {
    guard !connectionBusy, entries.allSatisfy({ $0.verifying.isEmpty }) else { return }
    reconnecting = true
    connectionNote = nil
    await refresh()
    guard reconnecting else { return }
    reconnection = ReconnectionQueue(
      targets: entries.flatMap { entry in
        Provider.allCases.filter { entry.needsLogin($0) }.map {
          LoginTarget(deviceID: entry.id, provider: $0)
        }
      })
    reconnecting = !reconnectQueue.isEmpty
    nextReconnection()
  }

  func nextReconnection() {
    guard login?.phase.running != true else { return }
    if let target = reconnection.next(
      available: Set(entries.map(\.id)), reachable: Set(entries.filter(\.online).map(\.id)))
    {
      let entry = entries.first { $0.id == target.deviceID }!
      connectionNote = nil
      beginLogin(entry.device, provider: target.provider)
      if login?.phase.running == true { return }
    }
    if let waiting = reconnection.waiting,
      let entry = entries.first(where: { $0.id == waiting.deviceID })
    {
      login = nil
      connectionNote =
        "\(displayName(entry.device)) is unreachable. The reconnection queue is paused."
      return
    }
    reconnecting = false
    connectionNote = connectionSummary
  }

  func retryWaitingConnection() async {
    guard reconnecting, let waiting = reconnection.waiting else { return }
    await refresh(waiting.deviceID)
    guard reconnecting, reconnection.waiting?.id == waiting.id else { return }
    nextReconnection()
  }

  func skipWaitingConnection() {
    guard reconnecting, reconnection.waiting != nil else { return }
    reconnection.skipWaiting()
    nextReconnection()
  }

  private func verifySavedSessions(_ id: UUID) async {
    guard let entry = entries.first(where: { $0.id == id }), let snapshot = entry.snapshot,
      entry.online
    else { return }
    _ = await FleetCoordinator(client: client).connect(
      device: entry.device, snapshot: snapshot,
      checks: entry.verifications
    ) { provider, check in
      await self.receiveConnectionCheck(id, provider: provider, check: check)
    }
  }

  private func receiveConnectionCheck(_ id: UUID, provider: Provider, check: AccessCheck?) {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
    if let check {
      entries[index].verifying.remove(provider)
      entries[index].verifications[provider] = check
      persistChecks()
    } else {
      entries[index].verifying.insert(provider)
    }
  }

  func beginLogin(_ device: Device, provider: Provider) {
    guard !connectingFleet, login?.phase.running != true,
      let index = entries.firstIndex(where: { $0.id == device.id }), entries[index].online,
      entries[index].verifying.isEmpty
    else { return }
    if entries[index].verifications[provider]?.state != .loginRequired {
      entries[index].verifications.removeValue(forKey: provider)
    }
    persistChecks()
    login = LoginProgress(deviceID: device.id, provider: provider)
    loginInputError = nil
    let id = login!.id
    do {
      let process = try ManagedLogin(device: device, provider: provider, localAgent: localAgent)
      loginProcess = process
      Task {
        for await event in process.events {
          guard login?.id == id, login?.phase.running == true else { continue }
          do { try login?.receive(event) } catch {
            process.cancel()
            login?.cancel()
            message = "The agent returned an unsupported sign-in response."
          }
          if event.kind == .signedIn {
            await finishLogin(id, device: device, provider: provider)
          }
        }
        if login?.id == id {
          loginProcess = nil
          if login?.phase.running == true { login?.cancel() }
          if login?.phase == .ready, reconnecting { nextReconnection() }
        }
      }
    } catch {
      try? login?.receive(LoginEvent(provider: provider, kind: .failed))
    }
  }

  private func finishLogin(_ id: UUID, device: Device, provider: Provider) async {
    do {
      let snapshot = try await client.snapshot(device)
      guard login?.id == id, login?.phase == .verifying,
        let index = entries.firstIndex(where: { $0.id == device.id })
      else { return }
      entries[index].snapshot = snapshot
      entries[index].error = nil
      let authenticated = snapshot.providers.first { $0.id == provider }?.auth == .authenticated
      if authenticated { await verify(device.id, provider: provider, afterLogin: id) }
      guard login?.id == id else { return }
      login?.complete(
        authenticated: authenticated,
        check: entries.first { $0.id == device.id }?.verifications[provider])
    } catch {
      login?.complete(
        authenticated: false,
        check: AccessCheck(
          provider: provider, state: .failed,
          note: (error as? OrbitError)?.errorDescription
            ?? "The saved session could not be checked."))
    }
  }

  func submitLoginCode(_ code: String) {
    guard login?.phase == .awaitingBrowser, login?.provider == .claude, let process = loginProcess
    else { return }
    do {
      try process.submit(code: code)
      loginInputError = nil
      login?.submittedCode()
    } catch {
      loginInputError =
        "Use only the one-time authorization code from the provider page, then try again."
    }
  }

  func cancelLogin() {
    reconnection.stop()
    reconnecting = false
    loginProcess?.cancel()
    login?.cancel()
  }
  func shutdown() {
    monitor?.cancel()
    cancelLogin()
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
    guard !(login?.phase.running == true && login?.deviceID == id) else {
      message = "Finish or cancel sign-in before removing this Mac."
      return
    }
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

  private func persistChecks() {
    do {
      try inventory.saveChecks(
        entries.map { StoredChecks(deviceID: $0.id, checks: $0.verifications) })
    } catch { message = "Could not save the latest checks locally." }
  }

  private func importSavedChecks() {
    guard let saved = try? inventory.loadChecks() else { return }
    for index in entries.indices {
      guard let incoming = saved.first(where: { $0.deviceID == entries[index].id }) else {
        continue
      }
      entries[index].verifications =
        StoredChecks(
          deviceID: entries[index].id, checks: entries[index].verifications
        ).merging(incoming).checks
    }
  }
}
