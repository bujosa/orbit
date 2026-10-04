import OrbitCore
import XCTest

@testable import OrbitAgent

final class CredentialRollbackTests: XCTestCase {
  func testCancellationRestoresRemovedCacheWithPrivatePermissions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("auth.json")
    let original = Data(#"{"auth_mode":"example","tokens":{"example":"fixture"}}"#.utf8)
    try original.write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let rollback = try CredentialRollback(
      file: file, directory: root.appendingPathComponent("backups"))
    try FileManager.default.removeItem(at: file)
    try rollback.finish(succeeded: false)
    XCTAssertEqual(try Data(contentsOf: file), original)
    XCTAssertEqual(
      try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        atPath: root.appendingPathComponent("backups").path
      ).count, 0)
  }

  func testRollbackPreservesNewOrExternallyChangedCache() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("auth.json")
    try Data(#"{"example":"old"}"#.utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let rollback = try CredentialRollback(
      file: file, directory: root.appendingPathComponent("backups"))
    let updated = Data(#"{"example":"new"}"#.utf8)
    try updated.write(to: file)
    try rollback.finish(succeeded: false)
    XCTAssertEqual(try Data(contentsOf: file), updated)
  }

  func testUnsafeCacheCannotBeBackedUpOrModified() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("auth.json")
    let actual = root.appendingPathComponent("other")
    try Data(#"{"example":"fixture"}"#.utf8).write(to: actual)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: actual)
    XCTAssertThrowsError(
      try CredentialRollback(file: file, directory: root.appendingPathComponent("backups")))
  }
}
