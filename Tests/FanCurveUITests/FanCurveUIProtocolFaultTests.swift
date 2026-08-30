//
//  FanCurveUIProtocolFaultTests.swift
//  FanCurveUITests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import XCTest

@MainActor
final class FanCurveUIProtocolFaultTests: XCTestCase {
  private static let curveControlPointCount = 8

  func testEveryProtocolFaultRecoversAndLowerRevisionIsRejected() throws {
    let curveControlPointIndex = 3
    let curveControlPointDragOffset = CGVector(dx: 0, dy: -20)

    try FanCurveUIScenario.run(in: self) { driver in
      try driver.prime(.make())
      try driver.launch()
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
      try registerCurveCleanup(driver)
      try verifyStartupAndEventFaults(driver)
      try verifyCommandFaults(
        driver,
        controlPointIndex: curveControlPointIndex,
        dragOffset: curveControlPointDragOffset
      )

      try driver.injectOutOfOrderRevision()
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
    }
  }

  private func registerCurveCleanup(_ driver: FanCurveUITestDriver) throws {
    let originalControlPointFrames = try driver.controlPointFrames(
      count: Self.curveControlPointCount
    )
    driver.registerCleanup {
      driver.app.activate()
      try driver.restoreControlPointFrames(originalControlPointFrames)
    }
  }

  private func verifyStartupAndEventFaults(
    _ driver: FanCurveUITestDriver
  ) throws {
    for fault in startupAndEventFaults {
      _ = try driver.apply(.make(xpcFault: fault))
      if startupFaults.contains(fault) {
        try driver.relaunch()
      }
      let participant =
        fault == .reconnect
        ? TestControlParticipant.app
        : TestControlParticipant.agent
      _ = try driver.waitForPayload(
        participant: participant,
        payload: .xpcFault(fault),
        revision: driver.revision
      )
      try verifyFaultSpecificEvidence(driver, fault: fault)
      try recover(driver)
    }
  }

  private func verifyCommandFaults(
    _ driver: FanCurveUITestDriver,
    controlPointIndex: Int,
    dragOffset: CGVector
  ) throws {
    for fault in commandFaults {
      _ = try driver.apply(.make(xpcFault: fault))
      try driver.drag(
        AppAccessibilityIdentifier.Curve.controlPoint(controlPointIndex),
        normalizedOffset: dragOffset
      )
      _ = try driver.waitForPayload(
        participant: .agent,
        payload: .xpcFault(fault),
        revision: driver.revision
      )
      _ = try driver.waitForPayload(
        participant: .app,
        payload: .appToAgentCommand(command: .setCurve),
        revision: driver.revision
      )
      let appState: TestXPCStateEvent
      if fault == .rejectedCommand {
        appState = .commandRejected
      } else {
        appState = .commandReplyMalformed
      }
      _ = try driver.waitForPayload(
        participant: .app,
        payload: .xpcState(appState),
        revision: driver.revision
      )
      try verifyDashboardPreserved(driver)
      try recover(driver)
    }
  }

  private var startupAndEventFaults: [TestXPCFault] {
    [
      .malformedInitialState,
      .duplicateEvent,
      .malformedEvent,
      .invalidation,
      .interruption,
      .reconnect,
    ]
  }

  private var startupFaults: Set<TestXPCFault> {
    [.malformedInitialState, .interruption, .reconnect]
  }

  private var commandFaults: [TestXPCFault] {
    [.rejectedCommand, .malformedReply]
  }

  private func verifyFaultSpecificEvidence(
    _ driver: FanCurveUITestDriver,
    fault: TestXPCFault
  ) throws {
    switch fault {
    case .malformedInitialState:
      _ = try driver.waitForPayload(
        participant: .app,
        payload: .xpcState(.initialStateRejected),
        revision: driver.revision
      )
      try verifyReconnectEvidence(driver)
    case .malformedEvent:
      _ = try driver.waitForPayload(
        participant: .app,
        payload: .xpcState(.runtimeEventRejected),
        revision: driver.revision
      )
    case .duplicateEvent:
      try driver.waitForPayloadCount(
        participant: .app,
        payload: .xpcState(.runtimeEventAccepted),
        revision: driver.revision,
        count: 2
      )
    case .invalidation:
      _ = try driver.waitForPayload(
        participant: .app,
        payload: .xpcState(.disconnected),
        revision: driver.revision
      )
      try verifyReconnectEvidence(driver)
    case .interruption:
      _ = try driver.waitForPayload(
        participant: .agent,
        payload: .processLifecycle(process: .agent, phase: .terminated),
        revision: driver.revision
      )
      _ = try driver.waitForPayload(
        participant: .app,
        payload: .xpcState(.disconnected),
        revision: driver.revision
      )
      try verifyReconnectEvidence(driver)
    case .reconnect:
      try verifyReconnectEvidence(driver)
    case .malformedReply, .noFault, .rejectedCommand:
      break
    }
    try verifyDashboardPreserved(driver)
  }

  private func verifyReconnectEvidence(_ driver: FanCurveUITestDriver) throws {
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .xpcState(.reconnectScheduled),
      revision: driver.revision
    )
  }

  private func verifyDashboardPreserved(_ driver: FanCurveUITestDriver) throws {
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.fanControl)
  }

  private func recover(_ driver: FanCurveUITestDriver) throws {
    _ = try driver.apply(.make())
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.fanControl)
  }
}
