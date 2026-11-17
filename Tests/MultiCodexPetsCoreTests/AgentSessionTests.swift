import XCTest

@testable import MultiCodexPetsCore

final class AgentSessionTests: XCTestCase {
  func testDetectsProvidersAndOrcaAncestryWithoutCountingHelpers() {
    let listing = """
      1 0 /sbin/launchd
      10 1 /Applications/Orca.app/Contents/MacOS/Orca
      11 10 /bin/zsh
      12 11 /opt/homebrew/bin/codex
      13 12 /opt/homebrew/bin/codex-code-mode-host
      20 1 /opt/homebrew/bin/claude
      21 1 /Applications/Codex.app/Contents/MacOS/Codex
      22 1 /Applications/Codex.app/Contents/Frameworks/Codex Helper
      23 1 /opt/homebrew/bin/claude
      """
    XCTAssertEqual(AgentSession.detected(in: listing), [.codex, .claude, .orca])
  }

  func testOrcaAppAloneIsNotASession() {
    XCTAssertEqual(AgentSession.detected(in: "10 1 /Applications/Orca.app/Contents/MacOS/Orca"), [])
  }

  func testDetachedOrcaTerminalHostAndNativeClaude() {
    XCTAssertEqual(
      AgentSession.detected(
        in: """
          10 1 /path with spaces/Orca Terminal Host.app/Contents/MacOS/orca-terminal-host
          11 10 /bin/zsh
          12 11 /Users/me/.local/share/claude/versions/2.1.0
          """), [.orca])
    XCTAssertEqual(
      AgentSession.detected(
        in:
          "12 1 /Users/me/.local/share/claude/versions/2.1.0"), [.claude])
  }

  func testMalformedRowsAndAncestryCyclesAreSafe() {
    XCTAssertEqual(
      AgentSession.detected(
        in: """
          invalid row
          10 11 codex
          11 10 /bin/zsh
          """), [.codex])
    XCTAssertEqual(AgentSession.detected(in: ""), [])
  }

  func testProvidersUseDifferentAnimations() {
    XCTAssertEqual(Set(AgentSession.allCases.map { $0.animationState.rawValue }).count, 4)
  }

  func testIndividualSessionsKeepProviderAndPID() {
    let sessions = AgentSession.sessions(
      in: """
        10 1 /Applications/Orca.app/Contents/MacOS/Orca
        12 10 /opt/homebrew/bin/claude
        20 1 /opt/homebrew/bin/claude
        21 1 /opt/homebrew/bin/claude
        """)
    XCTAssertEqual(sessions.map(\.pid), [20, 21, 12])
    XCTAssertEqual(sessions.last?.displayName, "Status Unknown · Untitled Claude session")
  }

  func testAutomaticDistributionIncludesEveryKindDespiteDuplicateSessions() {
    let routing = SessionRouting()
    let sessions = [
      DetectedAgentSession(id: 1, agent: .codex),
      DetectedAgentSession(id: 2, agent: .codex),
      DetectedAgentSession(id: 3, agent: .claude),
    ]
    XCTAssertEqual(
      routing.states(for: ["a", "b", "c"], sessions: sessions), [.idle, .idle, .idle])
    XCTAssertEqual(routing.states(for: ["a"], sessions: []), [.idle])
  }

  func testSingleSessionAppliesToAllPetsAndDoesNotSwitchWhenItEnds() {
    var routing = SessionRouting()
    routing.mode = .single
    routing.singleSessionID = "process:2"
    let sessions = [
      DetectedAgentSession(id: 1, agent: .codex), DetectedAgentSession(id: 2, agent: .claude),
    ]
    XCTAssertEqual(routing.states(for: ["a", "b"], sessions: sessions), [.idle, .idle])
    XCTAssertEqual(
      routing.states(for: ["a", "b"], sessions: Array(sessions.prefix(1))), [.idle, .idle])
  }

  func testPerPetSupportsExplicitSessionIdleAndAutomatic() {
    var routing = SessionRouting()
    routing.mode = .perPet
    routing.sessionIDsByPet = ["a": "process:2", "b": "idle", "c": "process:99"]
    let sessions = [
      DetectedAgentSession(id: 1, agent: .codex), DetectedAgentSession(id: 2, agent: .claude),
    ]
    XCTAssertEqual(
      routing.states(for: ["a", "b", "c", "d"], sessions: sessions),
      [.idle, .idle, .idle, .idle])
    routing.sessionIDsByPet.removeValue(forKey: "a")
    XCTAssertEqual(routing.states(for: ["a"], sessions: sessions), [.idle])
  }

}
