import Darwin
import Foundation

public struct CommandResult: Sendable {
  public let exit: Int32
  public let stdout: Data
  public let stderr: Data
  public let timedOut: Bool
  public var text: String { String(decoding: stdout, as: UTF8.self) }
  public var diagnostic: String { text + String(decoding: stderr, as: UTF8.self) }
}

private final class OutputBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Data()
  func append(_ data: Data) {
    lock.lock()
    defer { lock.unlock() }
    let remaining = max(0, 2_000_000 - value.count)
    value.append(data.prefix(remaining))
  }
  var data: Data {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

private final class TimeoutFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  func set() {
    lock.lock()
    value = true
    lock.unlock()
  }
  var timedOut: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

public enum ProcessRunner {
  public static func run(
    _ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 20,
    environment: [String: String]? = nil, cwd: URL? = nil, stdin: Data? = nil
  ) async throws -> CommandResult {
    try await Task.detached {
      try runSync(
        executable, arguments, timeout: timeout, environment: environment, cwd: cwd, stdin: stdin)
    }.value
  }

  public static func runSync(
    _ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 20,
    environment: [String: String]? = nil, cwd: URL? = nil, stdin: Data? = nil
  ) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = cwd
    let output = Pipe()
    let error = Pipe()
    let input = Pipe()
    process.standardOutput = output
    process.standardError = error
    process.standardInput = stdin == nil ? FileHandle.nullDevice : input
    let out = OutputBuffer()
    let err = OutputBuffer()
    let flag = TimeoutFlag()
    let readers = DispatchGroup()
    try process.run()
    for (pipe, buffer) in [(output, out), (error, err)] {
      readers.enter()
      DispatchQueue.global().async {
        defer { readers.leave() }
        while let chunk = try? pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
          buffer.append(chunk)
        }
      }
    }
    if let stdin {
      try input.fileHandleForWriting.write(contentsOf: stdin)
      try input.fileHandleForWriting.close()
    }
    let timer = DispatchSource.makeTimerSource(queue: .global())
    timer.schedule(deadline: .now() + timeout)
    timer.setEventHandler {
      guard process.isRunning else { return }
      flag.set()
      process.terminate()
      DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      }
    }
    timer.resume()
    process.waitUntilExit()
    timer.cancel()
    if readers.wait(timeout: .now() + 3) == .timedOut {
      try? output.fileHandleForReading.close()
      try? error.fileHandleForReading.close()
    }
    return CommandResult(
      exit: process.terminationStatus, stdout: out.data, stderr: err.data, timedOut: flag.timedOut)
  }
}
