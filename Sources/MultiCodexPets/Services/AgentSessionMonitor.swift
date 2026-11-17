import Foundation
import MultiCodexPetsCore

final class AgentSessionMonitor {
  private var timer: Timer?
  private let queue = DispatchQueue(label: "com.opensource.MultiCodexPets.sessions")
  private var isPolling = false
  private let metadata = AgentSessionMetadata()
  var onDiagnostics: (([String]) -> Void)?
  var onUpdate: (([DetectedAgentSession]?) -> Void)?

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
    queue.async { [weak self] in
      guard let self else { return }
      let sessions = Self.output("/bin/ps", ["-axo", "pid=,ppid=,comm="]).map {
        Self.detectSessions(String(decoding: $0, as: UTF8.self), metadata: self.metadata)
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isPolling = false
        guard self.timer != nil else { return }
        self.onUpdate?(sessions?.0)
        self.onDiagnostics?(sessions?.1 ?? ["Process inspection is unavailable."])
      }
    }
  }

  private static func detectSessions(_ listing: String, metadata: AgentSessionMetadata)
    -> ([DetectedAgentSession], [String])
  {
    let processes = AgentSession.sessions(in: listing)
    let codexPIDs = processes.filter { $0.agent == .codex }.compactMap(\.pid)
    var files: [Int: [String]] = [:]
    if !codexPIDs.isEmpty,
      let data = output(
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
    let candidates = [
      ProcessInfo.processInfo.environment["ORCA_CLI_COMMAND"],
      "/usr/local/bin/orca", "/opt/homebrew/bin/orca",
    ].compactMap { $0 }
    if let cli = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
      let data = output(cli, ["worktree", "ps", "--json"]),
      let orca = AgentSessionMetadata.orcaSessions(data)
    {
      // Orca's pane identities are more precise than a shared provider process.
      if !orca.isEmpty { sessions.removeAll { $0.hostedByOrca } }
      sessions.append(contentsOf: orca)
    } else if listing.lowercased().contains("/orca.app/contents/")
      || processes.contains(where: { $0.hostedByOrca })
    {
      diagnostics.append("Orca session API is unavailable. Check the running app and CLI access.")
    }
    return (sessions, Array(Set(diagnostics)).sorted())
  }

  private static func output(_ executable: String, _ arguments: [String]) -> Data? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
      DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: timeout)
      defer { timeout.cancel() }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return process.terminationStatus == 0 ? data : nil
    } catch { return nil }
  }

  deinit { timer?.invalidate() }
}
