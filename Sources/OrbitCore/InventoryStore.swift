import Foundation

public struct InventoryStore: Sendable {
  public let directory: URL
  public init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Orbit")
  }

  public func loadDevices() throws -> [Device] {
    let path = directory.appendingPathComponent("devices.json")
    guard FileManager.default.fileExists(atPath: path.path) else {
      return [Device(name: "This Mac", isLocal: true)]
    }
    let devices = try Wire.decoder.decode([Device].self, from: Data(contentsOf: path))
    try validate(devices)
    return devices
  }

  public func saveDevices(_ devices: [Device]) throws {
    try validate(devices)
    try write(Wire.encoder.encode(devices), name: "devices.json")
  }
  public func loadChecks() throws -> [StoredChecks] {
    let path = directory.appendingPathComponent("state.json")
    guard FileManager.default.fileExists(atPath: path.path) else { return [] }
    return try Wire.decoder.decode([StoredChecks].self, from: Data(contentsOf: path))
  }
  public func saveChecks(_ values: [StoredChecks]) throws {
    try write(Wire.encoder.encode(values), name: "state.json")
  }

  public func validate(_ devices: [Device]) throws {
    guard devices.count <= 100, Set(devices.map(\.id)).count == devices.count,
      devices.filter(\.isLocal).count <= 1
    else { throw OrbitError.invalidDevice }
    for device in devices { try device.validate() }
  }

  public func write(_ data: Data, name: String) throws {
    guard ["devices.json", "state.json"].contains(name) else { throw OrbitError.unsafeFile }
    let file = directory.appendingPathComponent(name)
    for url in [directory, file] {
      if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        attributes[.type] as? FileAttributeType == .typeSymbolicLink
      {
        throw OrbitError.unsafeFile
      }
    }
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try data.write(to: file, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
}
