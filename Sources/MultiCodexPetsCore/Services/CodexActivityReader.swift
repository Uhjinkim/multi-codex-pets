import Foundation

/// Call from the monitor's serial queue. Retains lifecycle state and a bounded partial JSONL record.
final class CodexActivityReader {
  private struct Cursor {
    var fileID: UInt64
    var offset: UInt64 = 0
    var pending = Data()
    var droppingLongLine = false
    var activity: AgentActivity = .unknown
  }
  private var cursors: [URL: Cursor] = [:]

  func activity(at url: URL) -> AgentActivity {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
      let handle = try? FileHandle(forReadingFrom: url)
    else {
      cursors.removeValue(forKey: url)
      return .unknown
    }
    defer { try? handle.close() }
    do {
      let end = try handle.seekToEnd()
      var cursor = cursors[url] ?? Cursor(fileID: fileID)
      if cursor.fileID != fileID || cursor.offset > end { cursor = Cursor(fileID: fileID) }
      try handle.seek(toOffset: cursor.offset)
      let separator = Data([10])
      while cursor.offset < end {
        guard let chunk = try handle.read(upToCount: Int(min(65_536, end - cursor.offset))),
          !chunk.isEmpty
        else { break }
        cursor.offset += UInt64(chunk.count)
        cursor.pending.append(chunk)
        while let newline = cursor.pending.range(of: separator)?.lowerBound {
          let line = cursor.pending[..<newline]
          if !cursor.droppingLongLine, let state = autoreleasepool(invoking: { Self.lifecycle(Data(line)) }) {
            cursor.activity = state
          }
          cursor.droppingLongLine = false
          cursor.pending.removeSubrange(...newline)
        }
        // Lifecycle events are short; skip oversized message/tool-output lines.
        if cursor.pending.count > 65_536 {
          cursor.pending.removeAll(keepingCapacity: false)
          cursor.droppingLongLine = true
        }
      }
      cursors[url] = cursor
      return cursor.activity
    } catch {
      cursors.removeValue(forKey: url)
      return .unknown
    }
  }

  func retain(paths: Set<String>) {
    cursors = cursors.filter { paths.contains($0.key.path) }
  }

  private static func lifecycle(_ line: Data) -> AgentActivity? {
    guard line.count <= 65_536,
      let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
      json["type"] as? String == "event_msg",
      let payload = json["payload"] as? [String: Any], let type = payload["type"] as? String
    else { return nil }
    switch type {
    case "task_started", "turn_started": return .running
    case "task_complete", "task_completed", "turn_completed": return .completed
    case "turn_aborted": return .waiting
    case "approval_request", "request_approval", "exec_approval_request",
      "apply_patch_approval_request":
      return .approval
    default: return nil
    }
  }
}
