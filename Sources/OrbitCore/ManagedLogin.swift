import Darwin
import Foundation

/// One owned agent process and its ephemeral protocol stream. No raw subprocess output is published.
public final class ManagedLogin: @unchecked Sendable {
  public let events: AsyncStream<LoginEvent>
  private let continuation: AsyncStream<LoginEvent>.Continuation
  private let provider: Provider
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let lock = NSLock()
  private var stopped = false
  private var stopKind = LoginEventKind.cancelled
  private var timer: DispatchSourceTimer?

  public convenience init(device: Device, provider: Provider, localAgent: String) throws {
    try device.validate()
    let executable = device.isLocal ? localAgent : "/usr/bin/ssh"
    let arguments =
      device.isLocal
      ? ["login-bridge", provider.rawValue]
      : try SSHTransport.arguments(for: device)
        + ["exec \"$HOME/.local/bin/orbit-agent\" login-bridge \(provider.rawValue)"]
    try self.init(executable: executable, arguments: arguments, provider: provider)
  }

  // Internal injection point for deterministic transport/cancellation tests, never CLI configuration.
  init(executable: String, arguments: [String], provider: Provider, timeout: TimeInterval = 600)
    throws
  {
    self.provider = provider
    var continuation: AsyncStream<LoginEvent>.Continuation!
    events = AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation = $0 }
    self.continuation = continuation
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = input
    _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard FileManager.default.isExecutableFile(atPath: executable) else {
      throw OrbitError.agentMissing
    }
    DispatchQueue.global().async { [self] in launchAndRead(timeout: timeout) }
  }

  private func launchAndRead(timeout: TimeInterval) {
    // Launch and wait on the same worker thread: Foundation task exit notifications use its run loop.
    lock.lock()
    if stopped {
      let kind = stopKind
      lock.unlock()
      continuation.yield(LoginEvent(provider: provider, kind: kind))
      continuation.finish()
      return
    }
    do { try process.run() } catch {
      lock.unlock()
      continuation.yield(LoginEvent(provider: provider, kind: .failed))
      continuation.finish()
      return
    }
    let timer = DispatchSource.makeTimerSource(queue: .global())
    timer.schedule(deadline: .now() + timeout)
    timer.setEventHandler { [weak self] in self?.stop(as: .expired) }
    self.timer = timer
    timer.resume()
    lock.unlock()
    readEvents()
  }

  public func submit(code: String) throws {
    let command = LoginInput(
      action: .code, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
    try command.validate(for: provider)
    lock.lock()
    defer { lock.unlock() }
    guard !stopped, process.isRunning else { throw OrbitError.offline }
    try input.fileHandleForWriting.write(contentsOf: Wire.encoder.encode(command) + Data([10]))
  }
  public func cancel() { stop(as: .cancelled) }
  private func stop(as kind: LoginEventKind) {
    lock.lock()
    defer { lock.unlock() }
    guard !stopped else { return }
    stopped = true
    stopKind = kind
    try? input.fileHandleForWriting.write(
      contentsOf: Wire.encoder.encode(LoginInput(action: .cancel)) + Data([10]))
    try? input.fileHandleForWriting.close()
    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in
      if process.isRunning { process.terminate() }
      DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      }
    }
  }

  private func readEvents() {
    var pending = Data()
    var terminal: LoginEvent?
    var invalid = false
    while let data = try? PipeChunks.read(from: output.fileHandleForReading) {
      pending.append(data)
      if pending.count > 32_768 {
        invalid = true
        cancel()
        break
      }
      while let end = pending.firstIndex(of: 10) {
        let line = pending.prefix(upTo: end)
        pending.removeSubrange(...end)
        guard let event = try? Wire.decoder.decode(LoginEvent.self, from: line),
          (try? event.validate(for: provider)) != nil, terminal == nil
        else {
          invalid = true
          cancel()
          break
        }
        if event.kind.terminal { terminal = event } else { continuation.yield(event) }
      }
      if invalid { break }
    }
    process.waitUntilExit()
    timer?.cancel()
    lock.lock()
    let stopped = stopped
    let stopKind = stopKind
    try? input.fileHandleForWriting.close()
    lock.unlock()
    if invalid || !pending.isEmpty {
      continuation.yield(LoginEvent(provider: provider, kind: .failed))
    } else if stopped {
      continuation.yield(LoginEvent(provider: provider, kind: stopKind))
    } else if let terminal, terminal.kind != .signedIn || process.terminationStatus == 0 {
      continuation.yield(terminal)
    } else {
      continuation.yield(LoginEvent(provider: provider, kind: .failed))
    }
    continuation.finish()
  }
}
