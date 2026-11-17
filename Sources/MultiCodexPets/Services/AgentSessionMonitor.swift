import Foundation
import Darwin
import MultiCodexPetsCore

final class AgentSessionMonitor {
  private var timer: Timer?
  private let queue = DispatchQueue(label: "com.opensource.MultiCodexPets.sessions")
  private var isPolling = false
  private let metadata = AgentSessionMetadata()
  private var messageTracker = OrcaMessageTracker()
  private var messageGeneration = 0
  var observesOrcaMessages = false {
    didSet { if oldValue != observesOrcaMessages { resetOrcaMessageBaseline() } }
  }
  var onDiagnostics: (([String]) -> Void)?
  var onUpdate: (([DetectedAgentSession]?) -> Void)?
  var onOrcaMessages: (([OrcaMessageEvent]) -> Void)?

  func resetOrcaMessageBaseline() {
    messageGeneration += 1
    queue.async { [weak self] in self?.messageTracker.reset() }
  }

  func start() {
    guard timer == nil else { return }
    poll()
    let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func refresh() { poll() }

  private func poll() {
    guard !isPolling else { return }
    isPolling = true
    let observesMessages = observesOrcaMessages
    let generation = messageGeneration
    queue.async { [weak self] in
      guard let self else { return }
      let sessions = Self.output("/bin/ps", ["-axo", "pid=,ppid=,comm="]).map {
        self.detectSessions(String(decoding: $0, as: UTF8.self), observesMessages: observesMessages)
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isPolling = false
        guard self.timer != nil else { return }
        self.onUpdate?(sessions?.0)
        self.onDiagnostics?(sessions?.1 ?? ["Process inspection is unavailable."])
        if generation == self.messageGeneration { self.onOrcaMessages?(sessions?.2 ?? []) }
      }
    }
  }

  private func detectSessions(_ listing: String, observesMessages: Bool)
    -> ([DetectedAgentSession], [String], [OrcaMessageEvent])
  {
    let processes = AgentSession.sessions(in: listing)
    let codexPIDs = processes.filter { $0.agent == .codex }.compactMap(\.pid)
    var files: [Int: [String]] = [:]
    if !codexPIDs.isEmpty,
      let data = Self.output(
        "/usr/sbin/lsof",
        ["-n", "-P", "-a", "-p", codexPIDs.map(String.init).joined(separator: ","), "-Fn"])
    {
      var pid: Int?
      for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        if line.first == "p" { pid = Int(line.dropFirst()) }
        if line.first == "n", let pid { files[pid, default: []].append(String(line.dropFirst())) }
      }
    }
    var sessions = metadata.enrich(processes, openFiles: files)
    var diagnostics = metadata.diagnostics
    var messages: [OrcaMessageEvent] = []
    let candidates = [
      ProcessInfo.processInfo.environment["ORCA_CLI_COMMAND"],
      "/usr/local/bin/orca", "/opt/homebrew/bin/orca",
    ].compactMap { $0 }
    if let cli = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
      let data = Self.output(cli, ["worktree", "ps", "--json"]),
      let orca = AgentSessionMetadata.orcaSessions(data)
    {
      // Orca's pane identities are more precise than a shared provider process.
      if !orca.isEmpty { sessions.removeAll { $0.hostedByOrca } }
      sessions.append(contentsOf: orca)
      if observesMessages, !orca.isEmpty {
        // shortcut: inspect the latest 200 records; use a cursor API if bursts exceed a scan window.
        let inbox = Self.output(cli, ["orchestration", "inbox", "--limit", "200", "--full", "--json"])
        if let events = messageTracker.observe(inbox, sessions: orca) {
          messages = events
        } else {
          diagnostics.append("Orca message history is unavailable. Message alerts will resume from a fresh baseline.")
        }
      } else { messageTracker.reset() }
    } else if listing.lowercased().contains("/orca.app/contents/")
      || processes.contains(where: { $0.hostedByOrca })
    {
      diagnostics.append("Orca session API is unavailable. Check the running app and CLI access.")
      messageTracker.reset()
    } else { messageTracker.reset() }
    return (sessions, Array(Set(diagnostics)).sorted(), messages)
  }

  static func output(_ executable: String, _ arguments: [String], timeout: TimeInterval = 2) -> Data? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    do {
      try process.run()
      defer {
        try? pipe.fileHandleForReading.close()
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
      }
      try pipe.fileHandleForWriting.close()
      let deadline = ProcessInfo.processInfo.systemUptime + timeout
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 65_536)
      var descriptor = pollfd(fd: pipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
      while true {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return nil }
        let ready = Darwin.poll(&descriptor, 1, Int32(max(1, min(remaining * 1000, Double(Int32.max)))))
        if ready < 0, errno == EINTR { continue }
        guard ready > 0 else { return nil }
        let count = buffer.withUnsafeMutableBytes {
          Darwin.read(descriptor.fd, $0.baseAddress, $0.count)
        }
        if count < 0, errno == EINTR { continue }
        guard count >= 0 else { return nil }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
      }
      guard exited.wait(timeout: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime)) == .success
      else { return nil }
      process.waitUntilExit()
      return process.terminationStatus == 0 ? data : nil
    } catch { return nil }
  }

  deinit { timer?.invalidate() }
}
