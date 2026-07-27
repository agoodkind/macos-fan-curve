//
//  FanCurveServiceSmokeTests.swift
//  FanCurveServiceSmokeTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

// MARK: - FanCurveServiceSmokeTests

@MainActor
final class FanCurveServiceSmokeTests: XCTestCase {
  func testCanonicalReleaseServicesRepairReconnectAndRelaunch() throws {
    continueAfterFailure = false
    let driver = FanCurveServiceSmokeDriver()
    defer { driver.terminate() }
    try driver.prepareFanSafety()
    try driver.launchCanonicalApp()
    try driver.completeRealServiceSetup()
    driver.assertHelperReadReachedDashboard()

    let originalAgentPID = try driver.waitForAgentPID()
    let originalAgentTick = try driver.waitForAgentLastTick()
    try driver.killAgent()
    let restartedAgentPID = try driver.waitForAgentPID(differentFrom: originalAgentPID)
    expect(restartedAgentPID) != originalAgentPID
    _ = try driver.waitForAgentLastTick(after: originalAgentTick)
    driver.assertHelperReadReachedDashboard()

    try driver.relaunchCanonicalApp()
    driver.assertHelperReadReachedDashboard()
    try driver.assertNoFanRPMWrites()
  }
}
