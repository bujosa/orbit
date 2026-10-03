import OrbitCore
import SwiftUI

private let mint = Color(red: 0.48, green: 0.91, blue: 0.72)
private let canvas = Color(red: 0.055, green: 0.067, blue: 0.075)
private let panel = Color(red: 0.092, green: 0.108, blue: 0.122)

struct FleetView: View {
  @ObservedObject var store: FleetStore
  @State private var adding = false
  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider().overlay(.white.opacity(0.05))
      ScrollView {
        VStack(alignment: .leading, spacing: 26) {
          header
          HStack(spacing: 14) {
            metric(
              "Macs online", value: "\(store.onlineCount) / \(store.entries.count)",
              symbol: "desktopcomputer", color: mint)
            metric(
              "Access verified", value: "\(store.verifiedCount)", symbol: "checkmark.shield",
              color: mint)
            metric(
              "Need attention", value: "\(store.attentionCount)", symbol: "exclamationmark.circle",
              color: .orange)
          }
          if let entry = store.entries.first(where: { $0.id == store.selection }) {
            deviceDetail(entry)
          } else {
            ContentUnavailableView(
              "Your fleet starts here", systemImage: "desktopcomputer",
              description: Text("Add a Mac to check its connection and coding accounts."))
          }
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield").font(.title3).foregroundStyle(mint)
            VStack(alignment: .leading, spacing: 5) {
              Text("Your accounts stay on your Macs").font(.system(size: 13, weight: .semibold))
              Text(
                "Orbit receives status, never passwords or tokens. A saved session is different from verified model access. Payment renewal remains with each provider."
              )
              .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            }
          }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
            panel.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
        }.padding(30)
      }.background(canvas)
    }
    .background(canvas)
    .sheet(isPresented: $adding) { AddDeviceView(store: store) }
    .alert(
      "Orbit",
      isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })
    ) {
      Button("OK") { store.message = nil }
    } message: {
      Text(store.message ?? "")
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 11) {
        ZStack {
          Circle().stroke(mint.opacity(0.25), lineWidth: 1).frame(width: 32, height: 32)
          Circle().stroke(mint, lineWidth: 2).frame(width: 19, height: 19)
          Circle().fill(mint).frame(width: 5, height: 5).offset(x: 14, y: -6)
        }
        Text("orbit").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-1)
      }.padding(.bottom, 35)
      Text("YOUR FLEET").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(
        .secondary
      ).padding(.bottom, 12)
      ForEach(store.entries) { entry in
        Button {
          store.selection = entry.id
        } label: {
          HStack(spacing: 10) {
            Image(systemName: entry.device.isLocal ? "laptopcomputer" : "desktopcomputer").font(
              .system(size: 16))
            VStack(alignment: .leading, spacing: 3) {
              Text(entry.device.name).font(.system(size: 13, weight: .medium))
              Text(
                entry.checking
                  ? "Checking…"
                  : entry.online ? "Online" : entry.error == nil ? "Waiting" : "Unreachable"
              )
              .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(entry.online ? mint : entry.checking ? .orange : .gray).frame(
              width: 6, height: 6)
          }.foregroundStyle(store.selection == entry.id ? mint : .white.opacity(0.85))
            .padding(12).background(
              store.selection == entry.id ? mint.opacity(0.09) : .clear,
              in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).padding(.bottom, 5)
      }
      Button {
        adding = true
      } label: {
        Label("Add a Mac", systemImage: "plus").font(.system(size: 12)).frame(
          maxWidth: .infinity, alignment: .leading
        ).padding(12)
      }
      .buttonStyle(.plain).foregroundStyle(.secondary).padding(.top, 6)
      Spacer()
      Toggle(
        "Connection alerts",
        isOn: Binding(get: { store.notificationsEnabled }, set: { store.enableNotifications($0) })
      )
      .toggleStyle(.switch).font(.system(size: 11)).padding(.bottom, 18)
      HStack(spacing: 7) {
        Image(systemName: "shield.lefthalf.filled").foregroundStyle(mint)
        Text("Private by design").font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Text("Orbit 0.1 · Early access").font(.system(size: 10)).foregroundStyle(.tertiary).padding(
        .top, 7)
    }.padding(20).frame(width: 220).background(Color(red: 0.043, green: 0.052, blue: 0.06))
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 7) {
        Text("Your Macs. One clear view.").font(.system(size: 27, weight: .semibold)).tracking(-0.7)
        Text("Know what is connected, and what needs you.").font(.system(size: 13)).foregroundStyle(
          .secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 9) {
        Button {
          Task { await store.refresh() }
        } label: {
          Label(store.refreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(store.refreshing).keyboardShortcut("r", modifiers: .command)
        if let date = store.lastRefresh {
          Text(date, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
      }
    }
  }

  private func metric(_ title: String, value: String, symbol: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        Spacer()
        Image(systemName: symbol).foregroundStyle(color.opacity(0.8))
      }
      Text(value).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
      panel, in: RoundedRectangle(cornerRadius: 14))
  }

  private func deviceDetail(_ entry: FleetEntry) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 10) {
            Text(entry.device.name).font(.system(size: 22, weight: .semibold))
            if entry.device.isLocal { badge("THIS MAC", color: .gray) }
          }
          Text(
            entry.device.isLocal
              ? "Local connection"
              : entry.device.address.isEmpty ? entry.device.sshAlias : entry.device.address
          )
          .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Open Terminal") { store.openTerminal(entry.device) }
        Button("Open T3") { store.openT3(entry.device) }.disabled(entry.device.t3URL.isEmpty)
        Menu {
          if !entry.device.isLocal {
            Button("Install / update agent") { Task { await store.installAgent(entry.device) } }
          }
          Button("Remove from Orbit", role: .destructive) { store.remove(entry.id) }
        } label: {
          Image(systemName: "ellipsis")
        }.menuStyle(.borderlessButton).frame(width: 25)
      }
      HStack(spacing: 16) {
        connectionLabel("Mac reachable", ready: entry.online)
        connectionLabel(
          "Tailscale", ready: entry.snapshot?.tailscaleConnected == true && entry.online)
        connectionLabel("T3 service", ready: entry.snapshot?.t3Running == true && entry.online)
      }.padding(.vertical, 4)
      if let error = entry.error {
        HStack(alignment: .top) {
          Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
          VStack(alignment: .leading, spacing: 5) {
            Text(error).font(.system(size: 13, weight: .medium))
            Text(
              "SSH must be enabled and trusted. The Mac must be awake. Orbit cannot unlock FileVault or turn on a powered-off computer."
            ).font(.system(size: 11)).foregroundStyle(.secondary)
          }
        }.padding(16).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
      }
      Divider().opacity(0.4)
      HStack {
        Text("CODING ACCOUNTS").font(.system(size: 10, weight: .semibold)).tracking(1.8)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Verify all") { Task { await store.verifyAll(entry.id) } }.disabled(
          !entry.online || !entry.verifying.isEmpty)
      }
      VStack(spacing: 0) {
        ForEach(Provider.allCases) { provider in
          providerRow(provider, entry: entry)
          if provider != Provider.allCases.last { Divider().padding(.leading, 58).opacity(0.3) }
        }
      }.background(panel, in: RoundedRectangle(cornerRadius: 14))
      Text(
        "Verify access sends a tiny real model request and counts toward your normal usage. Results stay current for 15 minutes; routine monitoring sends no model requests."
      )
      .font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(3)
    }
  }

  private func providerRow(_ provider: Provider, entry: FleetEntry) -> some View {
    let status = entry.snapshot?.providers.first { $0.id == provider }
    let check = entry.verifications[provider]
    let fresh = check?.isFresh() == true
    let verified =
      entry.online && status?.auth == .authenticated && check?.state == .verified && fresh
    let needsLogin = entry.needsLogin(provider)
    let title =
      !entry.online
      ? "Not connected"
      : needsLogin
        ? "Sign in required"
        : verified
          ? "Access verified"
          : fresh && check?.state == .limited
            ? "Usage limited"
            : status?.auth == .authenticated
              ? "Signed in · unverified"
              : status?.auth == .notInstalled ? "Not installed" : "Check unavailable"
    let color: Color = verified ? mint : needsLogin ? .orange : .gray
    return HStack(spacing: 14) {
      Image(systemName: provider.symbol).font(.system(size: 20)).foregroundStyle(
        .white.opacity(0.8)
      )
      .frame(width: 34, height: 40)
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 9) {
          Text(provider.title).font(.system(size: 14, weight: .semibold))
          badge(title, color: color)
        }
        Text([status?.plan, status?.account].compactMap { $0 }.joined(separator: " · "))
          .font(.system(size: 11)).foregroundStyle(.secondary)
        Text(
          fresh && check?.state != .verified
            ? check?.note ?? ""
            : status?.renewal.label ?? "Check this Mac to see its session status."
        )
        .font(.system(size: 10)).foregroundStyle(.tertiary)
        if let expiry = status?.expiresAt, status?.renewal == .manual {
          Text("Credential expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
            .font(.system(size: 10)).foregroundStyle(
              expiry.timeIntervalSinceNow < 604800 ? .orange : .secondary)
        }
      }
      Spacer(minLength: 12)
      if entry.verifying.contains(provider) {
        ProgressView().controlSize(.small).frame(width: 30)
      } else {
        Button("Verify access") { Task { await store.verify(entry.id, provider: provider) } }
          .disabled(!entry.online || status?.auth == .notInstalled)
      }
      Button("Sign in") { store.openTerminal(entry.device, provider: provider) }.disabled(
        !entry.online || status?.auth == .notInstalled)
    }.padding(16)
  }

  private func badge(_ title: String, color: Color) -> some View {
    Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(color)
      .padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.1), in: Capsule())
  }

  private func connectionLabel(_ title: String, ready: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: ready ? "checkmark.circle.fill" : "circle").foregroundStyle(
        ready ? mint : .gray)
      Text(title).foregroundStyle(.secondary)
    }.font(.system(size: 11))
  }
}

struct AddDeviceView: View {
  @ObservedObject var store: FleetStore
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var alias = ""
  @State private var address = ""
  @State private var hostKeyAlias = ""
  @State private var t3URL = ""
  @State private var error: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Bring a Mac into Orbit").font(.system(size: 23, weight: .semibold))
      Text("Use a trusted SSH connection over your private Tailscale network.").foregroundStyle(
        .secondary
      ).font(.system(size: 12))
      Form {
        TextField("Name", text: $name)
        TextField("SSH alias", text: $alias).help(
          "An existing alias from your SSH configuration, such as studio.")
        TextField("Tailscale address (optional)", text: $address)
        TextField("Known host alias (optional)", text: $hostKeyAlias).help(
          "Use the address already trusted in known_hosts when overriding the connection address.")
        TextField("T3 HTTPS URL (optional)", text: $t3URL)
      }.textFieldStyle(.roundedBorder)
      Text(
        "After adding the Mac, open Terminal to trust its SSH key, then choose Install / update agent from the device menu."
      ).font(.system(size: 11)).foregroundStyle(.secondary)
      if let error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Add Mac") {
          do {
            try store.add(
              Device(
                name: name, sshAlias: alias, address: address, hostKeyAlias: hostKeyAlias,
                t3URL: t3URL))
            dismiss()
          } catch {
            self.error = (error as? OrbitError)?.errorDescription ?? "Could not save this Mac."
          }
        }.keyboardShortcut(.defaultAction).disabled(name.isEmpty || alias.isEmpty)
      }
    }.padding(30).frame(width: 530)
  }
}
