import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var fleetWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    showFleet()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showFleet()
    return false
  }

  func showFleet() {
    if fleetWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false)
      window.title = "Orbit"
      window.minSize = NSSize(width: 960, height: 680)
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(
        rootView: FleetView(store: FleetStore.shared).preferredColorScheme(.dark))
      window.center()
      fleetWindow = window
    }
    fleetWindow?.deminiaturize(nil)
    fleetWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@main
struct OrbitApplication: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var store = FleetStore.shared
  var body: some Scene {
    MenuBarExtra(
      "Orbit",
      systemImage: store.attentionCount == 0 ? "circle.hexagongrid" : "exclamationmark.circle"
    ) {
      OrbitMenu(store: store, openFleet: delegate.showFleet)
    }
    .commands {
      CommandGroup(after: .newItem) {
        Button("Open Orbit", action: delegate.showFleet).keyboardShortcut("o")
        Button("Refresh fleet") { Task { await store.refresh() } }.keyboardShortcut(
          "r", modifiers: .command)
      }
    }
  }
}

struct OrbitMenu: View {
  @ObservedObject var store: FleetStore
  let openFleet: () -> Void
  var body: some View {
    Text("\(store.onlineCount) of \(store.entries.count) Macs online")
    Text("\(store.verifiedCount) provider connections verified")
    Divider()
    Button("Open Orbit", action: openFleet)
    Button("Refresh") { Task { await store.refresh() } }
    Divider()
    Button("Quit Orbit") { NSApp.terminate(nil) }.keyboardShortcut("q")
  }
}
