import Darwin
import Foundation
import OrbitCore

/// Runs on the selected Mac. Only temporary authorization instructions leave this process.
final class LoginBridge: @unchecked Sendable {
  private let provider: Provider
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let lock = NSLock()
  private let emission = NSLock()
  private var reason: LoginEventKind?
  private var finished = false
  init(provider: Provider) { self.provider = provider }

  func run() -> Int32 {
    var lockFD: Int32 = -1
    var rollback: CredentialRollback?
    var launched = false
    do {
      lockFD = try acquireLock()
      guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
        emit(.busy)
        close(lockFD)
        return 1
      }
      defer {
        flock(lockFD, LOCK_UN)
        close(lockFD)
      }
      let (binary, arguments, initialInput) = try Login.command(provider)
      rollback = try CredentialRollback.prepare(provider)
      var environment = Paths.cleanEnvironment
      environment["BROWSER"] = "/usr/bin/false"
      environment["SSH_CONNECTION"] = "Orbit managed sign-in"
      environment["TERM"] = "dumb"
      environment["NO_COLOR"] = "1"
      process.executableURL = URL(fileURLWithPath: binary)
      process.arguments = arguments
      process.environment = environment
      process.standardInput = input
      process.standardOutput = output
      process.standardError = output
      _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
      try process.run()
      launched = true
      emit(.starting)
      if let initialInput {
        try input.fileHandleForWriting.write(contentsOf: initialInput)
        try input.fileHandleForWriting.close()
      }
      DispatchQueue.global().async { [self] in receiveCommands() }
      let timer = DispatchSource.makeTimerSource(queue: .global())
      timer.schedule(deadline: .now() + 570)
      timer.setEventHandler { [weak self] in self?.stop(.expired) }
      timer.resume()
      var parser = LoginOutputParser(provider: provider)
      while let chunk = try? PipeChunks.read(from: output.fileHandleForReading) {
        if let challenge = parser.consume(chunk) { emit(.challenge, challenge: challenge) }
      }
      process.waitUntilExit()
      timer.cancel()
      lock.lock()
      finished = true
      let reason = reason
      try? input.fileHandleForWriting.close()
      lock.unlock()
      if let reason {
        try rollback?.finish(succeeded: process.terminationStatus == 0)
        emit(reason)
        return 1
      }
      guard process.terminationStatus == 0 else {
        try rollback?.finish(succeeded: false)
        emit(.failed)
        return 1
      }
      try Login.didSucceed(provider)
      try rollback?.finish(succeeded: true)
      emit(.signedIn)
      return 0
    } catch {
      if process.isRunning {
        stop(.failed)
        process.waitUntilExit()
      }
      try? rollback?.finish(succeeded: launched && process.terminationStatus == 0)
      emit(.failed)
      return 1
    }
  }

  private func emit(_ kind: LoginEventKind, challenge: LoginChallenge? = nil) {
    emission.lock()
    defer { emission.unlock() }
    guard
      let data = try? Wire.encoder.encode(
        LoginEvent(provider: provider, kind: kind, challenge: challenge))
    else { return }
    try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
  }

  private func receiveCommands() {
    // Commands are bounded JSON lines, never a shell or a general terminal input channel.
    var pending = Data()
    while let data = try? PipeChunks.read(from: FileHandle.standardInput) {
      pending.append(data)
      if pending.count > 8192 {
        stop(.failed)
        return
      }
      while let end = pending.firstIndex(of: 10) {
        let line = pending.prefix(upTo: end)
        pending.removeSubrange(...end)
        guard let command = try? Wire.decoder.decode(LoginInput.self, from: line),
          (try? command.validate(for: provider)) != nil
        else {
          stop(.failed)
          return
        }
        if command.action == .cancel {
          stop(.cancelled)
          return
        }
        lock.lock()
        if !finished, reason == nil, process.isRunning, let code = command.code {
          do { try input.fileHandleForWriting.write(contentsOf: Data((code + "\n").utf8)) } catch {
            lock.unlock()
            stop(.failed)
            return
          }
        }
        lock.unlock()
      }
    }
    stop(.cancelled)
  }

  private func stop(_ kind: LoginEventKind) {
    lock.lock()
    defer { lock.unlock() }
    guard !finished, reason == nil else { return }
    reason = kind
    if process.isRunning { process.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
  }

  private func acquireLock() throws -> Int32 {
    let directory = Paths.home.appendingPathComponent(".local/share/orbit")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
    guard attrs[.type] as? FileAttributeType == .typeDirectory,
      attrs[.ownerAccountID] as? UInt32 == getuid(),
      (attrs[.posixPermissions] as? Int ?? 0) & 0o077 == 0
    else { throw OrbitError.unsafeFile }
    let fd = open(
      directory.appendingPathComponent("login.lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw OrbitError.unsafeFile }
    var stat = stat()
    guard fstat(fd, &stat) == 0, stat.st_uid == getuid(),
      stat.st_mode & S_IFMT == S_IFREG, stat.st_mode & 0o077 == 0
    else {
      close(fd)
      throw OrbitError.unsafeFile
    }
    return fd
  }
}
