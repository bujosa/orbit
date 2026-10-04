import AppKit
import OrbitCore
import SwiftUI

private let connectionMint = Color(red: 0.48, green: 0.91, blue: 0.72)

struct ConnectionCenterView: View {
  @ObservedObject var store: FleetStore
  @Environment(\.dismiss) private var dismiss
  @State private var authorizationCode = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 7) {
          Text("Connection center").font(.system(size: 25, weight: .semibold))
          Text("Sign in once per Mac. Track every connection here.")
            .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        Spacer()
        Toggle(
          "Privacy mode",
          isOn: Binding(get: { store.privacyMode }, set: { store.setPrivacyMode($0) })
        )
        .toggleStyle(.switch).font(.system(size: 11))
        Button("Done") { dismiss() }.disabled(
          store.login?.phase.running == true || store.reconnecting
        )
        .keyboardShortcut(.cancelAction)
      }
      HStack {
        Image(systemName: "checkmark.shield").foregroundStyle(connectionMint)
        Text("\(store.readyCount) of \(store.entries.count) Macs ready").font(.headline)
        Spacer()
        Button("Reconnect needed accounts") { Task { await store.reconnectAccounts() } }
          .disabled(
            store.connectingFleet || store.reconnecting || store.login?.phase.running == true
              || store.entries.contains { !$0.verifying.isEmpty }
              || !store.entries.contains { !$0.health.loginRequired.isEmpty })
        if store.reconnecting, store.login == nil {
          ProgressView().controlSize(.small)
          Button("Stop queue") { store.cancelLogin() }
        }
        if store.connectingFleet { ProgressView().controlSize(.small) }
        Button(store.connectingFleet ? "Connecting…" : "Check & verify fleet") {
          Task { await store.connectFleet() }
        }.buttonStyle(.borderedProminent).tint(connectionMint)
          .disabled(
            store.connectionBusy || store.entries.isEmpty
              || store.entries.contains { !$0.verifying.isEmpty })
      }
      if let note = store.connectionNote {
        Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let login = store.login { loginCard(login) }
          ForEach(store.entries) { entry in deviceCard(entry) }
        }
      }
      Text(
        "Verification sends a small model request. Passwords stay on the official provider page. Sign-in instructions and one-time codes are temporary and are never saved in Orbit."
      )
      .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
    }
    .padding(26).frame(width: 860, height: 690).preferredColorScheme(.dark)
    .interactiveDismissDisabled(store.login?.phase.running == true || store.reconnecting)
    .onChange(of: store.login?.phase) { _, _ in authorizationCode = "" }
    .onChange(of: store.login?.id) { _, _ in authorizationCode = "" }
    .onChange(of: store.privacyMode) { _, _ in authorizationCode = "" }
  }

  private func loginCard(_ login: LoginProgress) -> some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack {
        Image(systemName: login.phase == .ready ? "checkmark.circle.fill" : login.provider.symbol)
          .foregroundStyle(login.phase == .ready ? connectionMint : .white)
        Text(
          "\(login.provider.title) · \(store.entries.first { $0.id == login.deviceID }.map { store.displayName($0.device) } ?? "Mac")"
        )
        .font(.headline)
        Spacer()
        if login.phase.running { ProgressView().controlSize(.small) }
      }
      Text(login.note).font(.system(size: 13)).foregroundStyle(.secondary)
      if store.reconnecting {
        HStack {
          Text("Accounts remaining after this sign-in: \(store.reconnectQueue.count)")
            .font(.system(size: 11)).foregroundStyle(.secondary)
          Spacer()
          Button("Stop queue") {
            authorizationCode = ""
            store.cancelLogin()
          }
        }
      }
      if login.phase == .awaitingBrowser, store.privacyMode {
        Text("Turn off privacy mode to see the provider page and temporary sign-in code.")
          .font(.system(size: 12)).foregroundStyle(.secondary)
      }
      if let challenge = login.challenge, login.phase == .awaitingBrowser, !store.privacyMode {
        HStack(spacing: 16) {
          Button("Open provider sign-in") {
            guard (try? challenge.validate(for: login.provider)) != nil,
              let url = URL(string: challenge.url)
            else { return }
            NSWorkspace.shared.open(url)
          }.buttonStyle(.borderedProminent).tint(connectionMint)
          if let code = challenge.userCode {
            Text(code).font(.system(size: 20, weight: .semibold, design: .monospaced))
              .textSelection(.enabled)
          }
        }
        if challenge.requiresCodeEntry {
          Text("If Claude shows an authorization code, paste it below to finish on this Mac.")
            .font(.system(size: 12)).foregroundStyle(.secondary)
          HStack {
            SecureField("One-time authorization code", text: $authorizationCode)
              .textFieldStyle(.roundedBorder).onSubmit { submitCode() }
            Button("Finish sign-in", action: submitCode).disabled(authorizationCode.isEmpty)
          }
          if let error = store.loginInputError {
            Text(error).font(.system(size: 12)).foregroundStyle(.orange)
          }
        } else if challenge.userCode != nil {
          Text(
            "Enter this one-time code on the provider page. Orbit will detect completion automatically."
          )
          .font(.system(size: 12)).foregroundStyle(.secondary)
        }
      }
      if login.phase.running {
        Button("Cancel sign-in", role: .cancel) {
          authorizationCode = ""
          store.cancelLogin()
        }
      } else if login.phase != .ready,
        let device = store.entries.first(where: { $0.id == login.deviceID })?.device
      {
        HStack {
          Button("Try sign-in again") { store.beginLogin(device, provider: login.provider) }
            .disabled(store.connectingFleet)
          Button("Verify current session") {
            Task { await store.verify(device.id, provider: login.provider) }
          }
          .disabled(
            store.connectionBusy || store.entries.first { $0.id == device.id }?.online != true)
          if store.reconnecting {
            Button("Skip this account") { store.nextReconnection() }
          }
        }
      }
    }
    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
    .background(connectionMint.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(connectionMint.opacity(0.18)))
  }

  private func submitCode() {
    let code = authorizationCode
    authorizationCode = ""
    store.submitLoginCode(code)
  }

  private func deviceCard(_ entry: FleetEntry) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: entry.health.ready ? "checkmark.circle.fill" : "desktopcomputer")
          .foregroundStyle(entry.health.ready ? connectionMint : .secondary)
        Text(store.displayName(entry.device)).font(.headline)
        Spacer()
        Text(
          entry.checking
            ? "Checking…"
            : entry.health.ready
              ? "Ready"
              : entry.online
                ? (entry.health.needsAttention ? "Needs attention" : "Needs verification")
                : "Unreachable"
        )
        .font(.system(size: 11)).foregroundStyle(entry.health.ready ? connectionMint : .secondary)
      }
      HStack(spacing: 18) {
        service("Mac", ready: entry.online)
        service("Tailscale", ready: entry.health.networkReady)
        service("T3", ready: entry.online && entry.snapshot?.t3Running == true)
      }
      if let error = entry.error {
        Text(error).font(.system(size: 12)).foregroundStyle(.orange)
        HStack {
          Button("Open Terminal") { store.openTerminal(entry.device) }
          if !entry.device.isLocal {
            Button("Install / update agent") { Task { await store.installAgent(entry.device) } }
          }
        }
      } else {
        ForEach(Provider.allCases) { provider in
          let status = entry.snapshot?.providers.first { $0.id == provider }
          HStack {
            Image(systemName: provider.symbol).frame(width: 20)
            Text(provider.title).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(providerLabel(provider, entry: entry)).font(.system(size: 11))
              .foregroundStyle(
                entry.health.verifiedProviders.contains(provider) ? connectionMint : .secondary)
            if entry.verifying.contains(provider) { ProgressView().controlSize(.mini) }
            Button(entry.needsLogin(provider) ? "Connect" : "Sign in") {
              store.beginLogin(entry.device, provider: provider)
            }.disabled(
              !entry.online || status?.auth == .notInstalled || store.connectingFleet
                || store.reconnecting || store.login?.phase.running == true
                || !entry.verifying.isEmpty)
            Button("Verify") { Task { await store.verify(entry.id, provider: provider) } }
              .disabled(
                !entry.online || status?.auth == .notInstalled || store.connectingFleet
                  || store.reconnecting || store.login?.phase.running == true
                  || entry.verifying.contains(provider))
          }
        }
      }
    }
    .padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }

  private func providerLabel(_ provider: Provider, entry: FleetEntry) -> String {
    guard entry.online else { return "Not connected" }
    if entry.health.verifiedProviders.contains(provider) { return "Verified" }
    if entry.needsLogin(provider) { return "Sign in required" }
    if entry.health.failedChecks.contains(provider) {
      return entry.verifications[provider]?.state == .limited ? "Usage limited" : "Check failed"
    }
    if entry.snapshot?.providers.first(where: { $0.id == provider })?.auth == .notInstalled {
      return "Install provider"
    }
    return entry.health.unavailableProviders.contains(provider)
      ? "Unavailable" : "Needs verification"
  }

  private func service(_ title: String, ready: Bool) -> some View {
    Label(title, systemImage: ready ? "checkmark.circle.fill" : "circle")
      .font(.system(size: 11)).foregroundStyle(ready ? connectionMint : .secondary)
  }
}
