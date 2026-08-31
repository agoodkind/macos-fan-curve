//
//  FanCurveUIScenario.swift
//  FanCurveUITests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import XCTest

@MainActor
enum FanCurveUIScenario {
  static func run(
    in testCase: XCTestCase,
    _ scenario: (FanCurveUITestDriver) throws -> Void
  ) throws {
    testCase.continueAfterFailure = false
    let driver: FanCurveUITestDriver
    do {
      driver = try FanCurveUITestDriver(testCase: testCase)
    } catch {
      FanCurveUITestDriver.attachInitializationFailureArtifacts(
        to: testCase,
        name: testCase.name,
        error: error
      )
      testCase.continueAfterFailure = true
      throw error
    }
    defer {
      do {
        try driver.runCleanupActions()
      } catch {
        fanCurveUITestLog.notice(
          "ui_test.cleanup.actions_failed error=\(error.localizedDescription, privacy: .public) recovery=continue-termination"
        )
      }
      do {
        try driver.terminate()
      } catch {
        fanCurveUITestLog.notice(
          "ui_test.cleanup.termination_failed error=\(error.localizedDescription, privacy: .public) recovery=continue-teardown"
        )
      }
      testCase.continueAfterFailure = true
    }
    do {
      try scenario(driver)
    } catch {
      driver.attachFailureArtifacts(name: testCase.name)
      throw error
    }
  }
}
