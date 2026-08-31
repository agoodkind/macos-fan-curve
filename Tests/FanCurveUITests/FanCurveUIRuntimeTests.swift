//
//  FanCurveUIRuntimeTests.swift
//  FanCurveUITests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import XCTest

@MainActor
final class FanCurveUIRuntimeTests: XCTestCase {
  func testTelemetryHealthTransitionsAndRecovery() throws {
    try FanCurveUIScenario.run(in: self) { driver in
      try driver.prime(.make())
      try driver.launch()
      try verifyHealthyTelemetry(driver)

      _ = try driver.apply(
        .make(
          fanReadings: []
        )
      )
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.degraded)
      try recover(driver)

      try verifyHelperUnreachable(driver)
      try recover(driver)

      try verifyHardwareOperationFailure(driver)
      try recover(driver)

      _ = try driver.apply(.make(telemetryStale: true))
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.degraded)
      try recover(driver)

      _ = try driver.apply(.make(ownershipPreempted: true))
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.fanRow(0))
      try recover(driver)
    }
  }

  private func recover(_ driver: FanCurveUITestDriver) throws {
    _ = try driver.apply(.make())
    try verifyHealthyTelemetry(driver)
  }

  private func verifyHelperUnreachable(_ driver: FanCurveUITestDriver) throws {
    _ = try driver.apply(.make(helperReachable: false))
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.root)
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Setup.title,
      equals: "Install the System Helper"
    )
  }

  private func verifyHardwareOperationFailure(
    _ driver: FanCurveUITestDriver
  ) throws {
    _ = try driver.apply(
      .make(
        helperReachable: true,
        hardwareOperation: .fail(
          code: "smc-unavailable",
          message: "SMC unavailable"
        )
      )
    )
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.degraded)
  }

  private func verifyHealthyTelemetry(_ driver: FanCurveUITestDriver) throws {
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.temperature)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.cpuLoad)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.gpuLoad)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.fanRow(0))
  }
}
