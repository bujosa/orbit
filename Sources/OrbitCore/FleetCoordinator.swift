import Foundation

public struct StoredChecks: Codable, Sendable {
  public var deviceID: UUID
  public var checks: [Provider: AccessCheck]
  public init(deviceID: UUID, checks: [Provider: AccessCheck]) {
    self.deviceID = deviceID
    self.checks = checks
  }

  /// Refresh may import checks from orbitctl without replacing newer app results.
  public func merging(_ incoming: StoredChecks, now: Date = Date()) -> StoredChecks {
    guard incoming.deviceID == deviceID else { return self }
    var result = checks
    for (provider, check) in incoming.checks {
      guard check.provider == provider, check.checkedAt <= now.addingTimeInterval(30),
        result[provider].map({ $0.checkedAt < check.checkedAt }) ?? true
      else { continue }
      result[provider] = check
    }
    return StoredChecks(deviceID: deviceID, checks: result)
  }
}

public struct FleetCoordinator: Sendable {
  public let client: AgentClient
  public init(client: AgentClient) { self.client = client }

  /// Both the app and controller use this policy; sign-in is always a separate explicit action.
  public func connect(
    device: Device, snapshot: DeviceSnapshot, checks: [Provider: AccessCheck],
    onCheck: @Sendable (Provider, AccessCheck?) async -> Void
  ) async -> [Provider: AccessCheck] {
    var result = checks
    for provider in Provider.allCases {
      guard !Task.isCancelled else { break }
      let health = ConnectionHealth(snapshot: snapshot, checks: result)
      if health.verifiedProviders.contains(provider) { continue }
      guard snapshot.providers.first(where: { $0.id == provider })?.auth == .authenticated else {
        continue
      }
      await onCheck(provider, nil)
      let check: AccessCheck
      do { check = try await client.verify(device, provider: provider) } catch {
        check = AccessCheck(
          provider: provider, state: .failed,
          note: (error as? OrbitError)?.errorDescription
            ?? "The access check could not be completed.")
      }
      result[provider] = check
      await onCheck(provider, check)
    }
    return result
  }
}
