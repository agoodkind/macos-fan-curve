//
//  FanCurveUITestDriver.swift
//  FanCurveUITests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppKit
import AppLog
import Foundation
import XCTest

let fanCurveUITestLog = AppLog.make(category: "FanCurveUITests")

// MARK: - FanCurveUITestDriverError

enum FanCurveUITestDriverError: Error, LocalizedError {
  case conditionTimedOut(String)
  case invalidEnvironment(String)
  case unexpectedExecutablePath(String)

  var errorDescription: String? {
    switch self {
    case .conditionTimedOut(let condition):
      return "Timed out waiting for \(condition)"
    case .invalidEnvironment(let message):
      return message
    case .unexpectedExecutablePath(let path):
      return "Fan Curve launched outside the canonical app: \(path)"
    }
  }
}

// MARK: - FanCurveUITestDriver

@MainActor
final class FanCurveUITestDriver {
  static let conditionTimeout: TimeInterval = 20

  let app: XCUIApplication
  let sessionURL: URL
  let store: TestControlSessionStore

  unowned let testCase: XCTestCase
  var currentState: TestControlState
  var failureSequence = 0

  init(testCase: XCTestCase) throws {
    self.testCase = testCase
    guard
      let sessionPath = ProcessInfo.processInfo.environment[
        TestControlActivation.environmentKey
      ],
      !sessionPath.isEmpty
    else {
      throw FanCurveUITestDriverError.invalidEnvironment(
        "\(TestControlActivation.environmentKey) must name the pre-created UI test session"
      )
    }

    sessionURL = URL(fileURLWithPath: sessionPath, isDirectory: true).standardizedFileURL
    store = try TestControlSessionStore.open(at: sessionURL)
    currentState = try store.loadState()
    app = XCUIApplication(bundleIdentifier: generatedAppBundleID)
    app.launchEnvironment[TestControlActivation.environmentKey] = sessionURL.path
    app.launchArguments += [
      "-ApplePersistenceIgnoreState",
      "YES",
      "-NSQuitAlwaysKeepsWindows",
      "NO",
    ]
  }

  var revision: UInt64 {
    currentState.revision.value
  }

  func prime(_ fixture: FanCurveUITestState) throws {
    _ = try apply(fixture, waitsForParticipants: false)
  }

  @discardableResult
  func apply(
    _ fixture: FanCurveUITestState,
    waitsForParticipants: Bool = true
  ) throws -> UInt64 {
    let nextRevision = currentState.revision.value + 1
    let nextState = TestControlState(
      sessionID: currentState.sessionID,
      revision: nextRevision,
      services: fixture.services,
      hardware: fixture.hardware,
      xpcFault: fixture.xpcFault
    )
    let stateURL = sessionURL.appendingPathComponent(
      "ui-state-\(nextRevision).json"
    )
    try TestControlCodec.encode(nextState).write(to: stateURL, options: .atomic)
    let command = FanCurveTestControlCommand.apply(
      sessionPath: sessionURL.path,
      statePath: stateURL.path
    )
    _ = try command.run()
    currentState = nextState

    if waitsForParticipants {
      try waitForAcknowledgment(participant: .app, revision: nextRevision)
      try waitForAcknowledgment(participant: .agent, revision: nextRevision)
    }
    return nextRevision
  }

  func launch() throws {
    app.launch()
    guard app.wait(for: .runningForeground, timeout: Self.conditionTimeout) else {
      throw FanCurveUITestDriverError.conditionTimedOut(
        "the canonical Fan Curve process to enter the foreground"
      )
    }
    try assertCanonicalExecutablePath()
  }

  func relaunch() throws {
    try terminate()
    try launch()
  }

  func terminate() throws {
    guard app.state != .notRunning else {
      return
    }
    app.terminate()
    guard app.wait(for: .notRunning, timeout: Self.conditionTimeout) else {
      throw FanCurveUITestDriverError.conditionTimedOut(
        "Fan Curve process termination"
      )
    }
  }

  func waitForTermination() throws {
    guard app.wait(for: .notRunning, timeout: Self.conditionTimeout) else {
      throw FanCurveUITestDriverError.conditionTimedOut(
        "Fan Curve process termination"
      )
    }
  }

  func waitForAcknowledgment(
    participant: TestControlParticipant,
    revision: UInt64
  ) throws {
    let command = FanCurveTestControlCommand.waitAcknowledgment(
      sessionPath: sessionURL.path,
      wait: TestControlAcknowledgmentWait(
        participant: participant,
        revision: revision,
        timeout: Self.conditionTimeout
      )
    )
    _ = try command.run()
  }
}
