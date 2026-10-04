import Foundation

/// Ephemeral, user-started work. Reachability refreshes never advance this queue.
public struct ReconnectionQueue: Sendable {
  public private(set) var pending: [LoginTarget]
  public private(set) var waiting: LoginTarget?

  public init(targets: [LoginTarget] = []) {
    pending = targets
  }

  /// Only an explicit retry, skip, or verified sign-in asks for the next target.
  public mutating func next(available: Set<UUID>, reachable: Set<UUID>) -> LoginTarget? {
    waiting = nil
    while let target = pending.first {
      guard available.contains(target.deviceID) else {
        pending.removeFirst()
        continue
      }
      guard reachable.contains(target.deviceID) else {
        waiting = target
        return nil
      }
      return pending.removeFirst()
    }
    return nil
  }

  public mutating func skipWaiting() {
    guard let waiting, pending.first?.id == waiting.id else { return }
    pending.removeFirst()
    self.waiting = nil
  }

  public mutating func stop() {
    pending = []
    waiting = nil
  }
}
