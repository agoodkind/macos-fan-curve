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
  func testEveryProtocolFaultRecoversAndLowerRevisionIsRejected() throws {
    let curveControlPointIndex = 3
    let curveControlPointDragOffset = CGVector(dx: 0, dy: -20)

    try FanCurveUIScenario.run(in: self) { driver in
      try driver.prime(.make())
      try driver.launch()
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)

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

      for fault in commandFaults {
        _ = try driver.apply(.make(xpcFault: fault))
        try driver.drag(
          AppAccessibilityIdentifier.Curve.controlPoint(curveControlPointIndex),
          normalizedOffset: curveControlPointDragOffset
        )
        _ = try driver.waitForPayload(
          participant: .agent,
          payload: .xpcFault(fault),
          revision: driver.revision
        )
        try recover(driver)
      }

      try driver.injectOutOfOrderRevision()
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
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
    if fault == .malformedEvent {
      _ = try driver.waitForPayload(
        participant: .app,
        payload: .xpcState(.runtimeEventRejected),
        revision: driver.revision
      )
    }
    if fault == .duplicateEvent {
      _ = try driver.waitForPayload(
        participant: .app,
        payload: .xpcState(.runtimeEventAccepted),
        revision: driver.revision
      )
    }
    if fault == .invalidation || fault == .interruption || fault == .reconnect {
      _ = try driver.waitForPayload(
        participant: .app,
        payload: .xpcState(.reconnectScheduled),
        revision: driver.revision
      )
    }
  }

  private func recover(_ driver: FanCurveUITestDriver) throws {
    _ = try driver.apply(.make())
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Dashboard.status,
      equals: "All systems go"
    )
  }
}
