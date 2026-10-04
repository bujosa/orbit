import Darwin
import Foundation
import OrbitCore

/// Codex removes its file cache as login starts. Keep recovery on that Mac, never on the controller.
final class CredentialRollback {
  private let file: URL
  private let backup: URL
  private let original: Data?

  init(file: URL, directory: URL) throws {
    self.file = file
    backup = directory.appendingPathComponent("codex-" + UUID().uuidString + ".backup")
    original = try Self.readPrivate(file)
    guard let original else { return }
    guard (try? JSONSerialization.jsonObject(with: original)) as? [String: Any] != nil else {
      throw OrbitError.unsafeFile
    }
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    guard attributes[.type] as? FileAttributeType == .typeDirectory,
      attributes[.ownerAccountID] as? UInt32 == getuid(),
      (attributes[.posixPermissions] as? Int ?? 0) & 0o077 == 0
    else { throw OrbitError.unsafeFile }
    guard
      FileManager.default.createFile(
        atPath: backup.path, contents: original,
        attributes: [.posixPermissions: 0o600])
    else { throw OrbitError.unsafeFile }
  }

  static func prepare(_ provider: Provider) throws -> CredentialRollback? {
    guard provider == .codex else { return nil }
    return try CredentialRollback(
      file: Paths.home.appendingPathComponent(".codex/auth.json"),
      directory: Paths.home.appendingPathComponent(".local/share/orbit/login-backups"))
  }

  func finish(succeeded: Bool) throws {
    if !succeeded, let original, try Self.readPrivate(file) == nil {
      // Restore only a removed cache. A new/changed cache may belong to a completed or external login.
      let parent = try FileManager.default.attributesOfItem(
        atPath: file.deletingLastPathComponent().path)
      guard parent[.type] as? FileAttributeType == .typeDirectory,
        parent[.ownerAccountID] as? UInt32 == getuid(),
        (parent[.posixPermissions] as? Int ?? 0) & 0o022 == 0
      else { throw OrbitError.unsafeFile }
      let fd = open(file.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, S_IRUSR | S_IWUSR)
      guard fd >= 0 else { throw OrbitError.unsafeFile }
      let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
      try handle.write(contentsOf: original)
      try handle.close()
    }
    if FileManager.default.fileExists(atPath: backup.path) {
      _ = try Self.readPrivate(backup)
      try FileManager.default.removeItem(at: backup)
    }
  }

  private static func readPrivate(_ file: URL) throws -> Data? {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular,
        attributes[.ownerAccountID] as? UInt32 == getuid(),
        (attributes[.posixPermissions] as? Int ?? 0) & 0o077 == 0,
        (attributes[.size] as? Int ?? 0) <= 1_000_000
      else { throw OrbitError.unsafeFile }
      return try Data(contentsOf: file)
    } catch let error as CocoaError
      where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code)
    { return nil }
  }
}
