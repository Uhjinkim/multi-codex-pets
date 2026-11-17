import Foundation
import XCTest
@testable import MultiCodexPets

final class AgentSessionMonitorTests: XCTestCase {
  func testReadsOutputLargerThanPipeCapacityAndRejectsFailures() {
    let data = AgentSessionMonitor.output("/bin/sh", ["-c", "head -c 200000 /dev/zero"], timeout: 3)
    XCTAssertEqual(data?.count, 200_000)
    XCTAssertNil(AgentSessionMonitor.output("/bin/sh", ["-c", "exit 1"]))
    XCTAssertNil(AgentSessionMonitor.output("/missing-command", []))
  }

  func testTimeoutKillsProcessIgnoringTerminationAndNextCommandStillWorks() {
    let start = ProcessInfo.processInfo.systemUptime
    XCTAssertNil(AgentSessionMonitor.output("/bin/sh", ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.15))
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    XCTAssertEqual(AgentSessionMonitor.output("/bin/echo", ["ok"]), Data("ok\n".utf8))
  }

  func testTimeoutAlsoBoundsPipeHeldOpenByDescendant() {
    let start = ProcessInfo.processInfo.systemUptime
    XCTAssertNil(AgentSessionMonitor.output("/bin/sh", ["-c", "sleep 1 & exit 0"], timeout: 0.15))
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.9)
  }
}
