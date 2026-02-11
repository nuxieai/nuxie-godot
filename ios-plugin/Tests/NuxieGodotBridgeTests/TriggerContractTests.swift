import XCTest
@testable import NuxieGodotBridge
@preconcurrency import Nuxie

final class TriggerContractTests: XCTestCase {
  private struct TerminalFixtureCase: Decodable {
    let name: String
    let updateKind: String
    let decisionKind: String?
    let entitlementKind: String?
    let expectedTerminal: Bool
  }

  func testTerminalTriggerRulesMatchContractFixtures() throws {
    let fixtures = try loadFixtures()

    for fixture in fixtures {
      let update = try makeUpdate(from: fixture)
      XCTAssertEqual(
        isTerminalTriggerUpdate(update),
        fixture.expectedTerminal,
        "Fixture '\(fixture.name)' produced an unexpected terminal status"
      )
    }
  }

  func testSuppressedDecisionDictionaryFlattensReasonPayload() {
    let payload = triggerDecisionDictionary(.suppressed(.alreadyActive))

    XCTAssertEqual(payload["type"] as? String, "suppressed")
    XCTAssertEqual(payload["reason"] as? String, "already_active")
  }

  private func loadFixtures() throws -> [TerminalFixtureCase] {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "trigger_terminal_cases", withExtension: "json") else {
      throw NSError(domain: "io.nuxie.godot.tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture file"])
    }

    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([TerminalFixtureCase].self, from: data)
  }

  private func makeUpdate(from fixture: TerminalFixtureCase) throws -> TriggerUpdate {
    switch fixture.updateKind {
    case "error":
      return .error(TriggerError(code: "code", message: "message"))

    case "journey":
      return .journey(
        JourneyUpdate(
          journeyId: "journey-1",
          campaignId: "campaign-1",
          flowId: nil,
          exitReason: .completed,
          goalMet: true,
          goalMetAt: nil,
          durationSeconds: nil,
          flowExitReason: nil
        )
      )

    case "decision":
      guard let kind = fixture.decisionKind else {
        throw NSError(domain: "io.nuxie.godot.tests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing decision kind for fixture \(fixture.name)"])
      }
      return .decision(makeDecision(kind))

    case "entitlement":
      guard let kind = fixture.entitlementKind else {
        throw NSError(domain: "io.nuxie.godot.tests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing entitlement kind for fixture \(fixture.name)"])
      }
      return .entitlement(makeEntitlement(kind))

    default:
      throw NSError(domain: "io.nuxie.godot.tests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unknown update kind \(fixture.updateKind)"])
    }
  }

  private func makeDecision(_ kind: String) -> TriggerDecision {
    let ref = JourneyRef(journeyId: "journey-1", campaignId: "campaign-1", flowId: "flow-1")

    switch kind {
    case "noMatch", "no_match":
      return .noMatch
    case "allowedImmediate", "allowed_immediate":
      return .allowedImmediate
    case "deniedImmediate", "denied_immediate":
      return .deniedImmediate
    case "journeyStarted", "journey_started":
      return .journeyStarted(ref)
    case "journeyResumed", "journey_resumed":
      return .journeyResumed(ref)
    case "flowShown", "flow_shown":
      return .flowShown(ref)
    case "suppressed":
      return .suppressed(.alreadyActive)
    default:
      return .suppressed(.unknown(kind))
    }
  }

  private func makeEntitlement(_ kind: String) -> EntitlementUpdate {
    switch kind {
    case "pending":
      return .pending
    case "allowed":
      return .allowed(source: .cache)
    case "denied":
      return .denied
    default:
      return .pending
    }
  }
}
