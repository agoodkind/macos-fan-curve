//
//  FanCurveUITestDriver+Assertions.swift
//  FanCurveUITests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import XCTest

private enum FanCurveUITestGestureConstants {
  static let centerNormalizedOffset: CGFloat = 0.5
  static let pressDuration: TimeInterval = 0.1
}

// MARK: - FanCurveUITestDriver

extension FanCurveUITestDriver {
  func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @discardableResult
  func waitForElement(
    _ identifier: String,
    timeout: TimeInterval = FanCurveUITestDriver.conditionTimeout
  ) throws -> XCUIElement {
    let candidate = element(identifier)
    guard candidate.waitForExistence(timeout: timeout) else {
      throw FanCurveUITestDriverError.conditionTimedOut(
        "accessibility element \(identifier)"
      )
    }
    return candidate
  }

  func waitForLabel(
    _ identifier: String,
    equals expectedLabel: String,
    timeout: TimeInterval = FanCurveUITestDriver.conditionTimeout
  ) throws {
    let candidate = try waitForElement(identifier, timeout: timeout)
    try waitForPredicate(
      NSPredicate(format: "label == %@", expectedLabel),
      object: candidate,
      description: "\(identifier) label to equal \(expectedLabel)",
      timeout: timeout
    )
  }

  func tap(
    _ identifier: String,
    timeout: TimeInterval = FanCurveUITestDriver.conditionTimeout
  ) throws {
    let candidate = try waitForElement(identifier, timeout: timeout)
    try waitForPredicate(
      NSPredicate(format: "isHittable == true"),
      object: candidate,
      description: "\(identifier) to become hittable",
      timeout: timeout
    )
    candidate.tap()
  }

  func tapApplicationMenuCommand(_ identifier: String) throws {
    let appMenu = app.menuBars.menuBarItems["Fan Curve"]
    guard appMenu.waitForExistence(timeout: Self.conditionTimeout) else {
      throw FanCurveUITestDriverError.conditionTimedOut("the Fan Curve application menu")
    }
    appMenu.click()
    try tap(identifier)
  }

  func drag(
    _ identifier: String,
    normalizedOffset: CGVector
  ) throws {
    let candidate = try waitForElement(identifier)
    let center = FanCurveUITestGestureConstants.centerNormalizedOffset
    let start = candidate.coordinate(withNormalizedOffset: CGVector(dx: center, dy: center))
    let destination = start.withOffset(normalizedOffset)
    start.press(
      forDuration: FanCurveUITestGestureConstants.pressDuration,
      thenDragTo: destination
    )
  }

  @discardableResult
  func waitForPayload(
    participant: TestControlParticipant,
    payload: TestControlEventPayload,
    revision: UInt64,
    timeout: TimeInterval = FanCurveUITestDriver.conditionTimeout
  ) throws -> TestControlEvent {
    let command = FanCurveTestControlCommand.waitEvent(
      sessionPath: sessionURL.path,
      wait: TestControlEventWait(
        participant: participant,
        kind: payload.kind,
        revision: revision,
        timeout: timeout
      )
    )
    _ = try command.run()

    var matchedEvent: TestControlEvent?
    var observationError: Error?
    let predicate = NSPredicate { [store] _, _ in
      do {
        matchedEvent = try store.loadEvents(for: participant).first { event in
          event.revision.value >= revision && event.payload == payload
        }
        return matchedEvent != nil
      } catch {
        fanCurveUITestLog.error(
          "ui_test.evidence_observation.failed participant=\(participant.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )
        observationError = error
        return false
      }
    }
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
    let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
    if let observationError {
      throw observationError
    }
    guard result == .completed, let matchedEvent else {
      throw FanCurveUITestDriverError.conditionTimedOut(
        "\(participant.rawValue) evidence \(payload)"
      )
    }
    return matchedEvent
  }

  func injectOutOfOrderRevision() throws {
    let appliedRevision = currentState.revision.value
    let proposedRevision = appliedRevision - 1
    let regressedState = TestControlState(
      sessionID: currentState.sessionID,
      revision: proposedRevision,
      services: currentState.services,
      hardware: currentState.hardware,
      xpcFault: currentState.xpcFault
    )
    try TestControlCodec.encode(regressedState).write(
      to: store.controlURL,
      options: .atomic
    )
    var rejectionError: Error?
    do {
      _ = try waitForPayload(
        participant: .app,
        payload: .revisionRejected(
          applied: appliedRevision,
          proposed: proposedRevision
        ),
        revision: appliedRevision
      )
      _ = try waitForPayload(
        participant: .agent,
        payload: .revisionRejected(
          applied: appliedRevision,
          proposed: proposedRevision
        ),
        revision: appliedRevision
      )
    } catch {
      fanCurveUITestLog.error(
        "ui_test.revision_fault.observation_failed applied=\(appliedRevision, privacy: .public) proposed=\(proposedRevision, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=restore-accepted-state"
      )
      rejectionError = error
    }

    try TestControlCodec.encode(currentState).write(
      to: store.controlURL,
      options: .atomic
    )
    fanCurveUITestLog.notice(
      "ui_test.revision_fault.restored revision=\(appliedRevision, privacy: .public)"
    )
    if let rejectionError {
      throw rejectionError
    }
  }

  private func waitForPredicate(
    _ predicate: NSPredicate,
    object: XCUIElement,
    description: String,
    timeout: TimeInterval
  ) throws {
    let expectation = XCTNSPredicateExpectation(
      predicate: predicate,
      object: object
    )
    guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
      throw FanCurveUITestDriverError.conditionTimedOut(description)
    }
  }
}
