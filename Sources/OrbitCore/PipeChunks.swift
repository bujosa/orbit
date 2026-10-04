import Darwin
import Foundation

public enum PipeChunks {
  /// POSIX reads return available bytes immediately; Foundation's counted reads can await a full block.
  public static func read(from handle: FileHandle) throws -> Data? {
    var bytes = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
      if count > 0 { return Data(bytes.prefix(count)) }
      if count == 0 { return nil }
      if errno != EINTR { throw OrbitError.offline }
    }
  }
}
