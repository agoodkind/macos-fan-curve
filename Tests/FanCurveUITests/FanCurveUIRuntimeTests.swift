//
//  FanCurveUIRuntimeTests.swift
//  FanCurveUITests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
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
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Dashboard.status,
        equals: "Telemetry Unavailable"
      )
      try recover(driver)

      _ = try driver.apply(
        .make(
          hardwareOperation: .fail(
            code: "smc-unavailable",
            message: "SMC unavailable"
          )
        )
      )
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.root)
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Setup.title,
        equals: "Install the System Helper"
      )
      try recover(driver)

      _ = try driver.apply(.make(telemetryStale: true))
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Dashboard.status,
        equals: "Telemetry Stale"
      )
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.degraded)
      try recover(driver)

      _ = try driver.apply(.make(ownershipPreempted: true))
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Dashboard.status,
        equals: "Fan Control Preempted"
      )
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.fanRow(0))
      try recover(driver)
    }
  }

  private func recover(_ driver: FanCurveUITestDriver) throws {
    _ = try driver.apply(.make())
    try verifyHealthyTelemetry(driver)
  }

  private func verifyHealthyTelemetry(_ driver: FanCurveUITestDriver) throws {
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.temperature)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.cpuLoad)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.gpuLoad)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.fanRow(0))
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Dashboard.status,
      equals: "All systems go"
    )
  }
}
