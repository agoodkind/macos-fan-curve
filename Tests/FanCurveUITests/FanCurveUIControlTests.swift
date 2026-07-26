//
//  FanCurveUIControlTests.swift
//  FanCurveUITests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import XCTest

@MainActor
final class FanCurveUIControlTests: XCTestCase {
  private static let curveControlPointIndex = 2
  private static let curveControlPointDragOffset = CGVector(dx: 0, dy: -40)
  private static let expectedProbeRPM: Float = 15_000

  func testCurveControlSettingsOwnershipManualFanAndLifecycle() throws {
    try FanCurveUIScenario.run(in: self) { driver in
      try driver.prime(.make())
      try driver.launch()
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
      try verifyCurveAndControls(driver)
      try verifyGeneralSettingsAndOwnership(driver)
      try verifyManualFanAndReset(driver)
      try verifyAboutAndLifecycle(driver)
    }
  }

  private func verifyCurveAndControls(_ driver: FanCurveUITestDriver) throws {
    try driver.drag(
      AppAccessibilityIdentifier.Curve.controlPoint(Self.curveControlPointIndex),
      normalizedOffset: Self.curveControlPointDragOffset
    )
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .setCurve),
      revision: driver.revision
    )
    try driver.tap(AppAccessibilityIdentifier.Dashboard.fanControl)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .setFanControlEnabled),
      revision: driver.revision
    )
    try driver.tap(AppAccessibilityIdentifier.Dashboard.boost)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .setBoostEnabled),
      revision: driver.revision
    )
  }

  private func verifyGeneralSettingsAndOwnership(
    _ driver: FanCurveUITestDriver
  ) throws {
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.settingsCommand
    )
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Application.settingsWindow)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.root)
    try driver.tap(AppAccessibilityIdentifier.Settings.generalTab)
    try driver.tap(AppAccessibilityIdentifier.Settings.applyInBackground)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .setApplyInBackground),
      revision: driver.revision
    )
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.backgroundAgentRow)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.backgroundAgentStatus)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.helperRow)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.helperStatus)
    try driver.tap(AppAccessibilityIdentifier.Settings.ownershipDisclosure)
    _ = try driver.waitForPayload(
      participant: .agent,
      payload: .hardwareRead(operation: .ownership),
      revision: driver.revision
    )
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.ownershipStatus)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.ownershipRow(0))
  }

  private func verifyManualFanAndReset(_ driver: FanCurveUITestDriver) throws {
    try driver.tap(AppAccessibilityIdentifier.Settings.profilesTab)
    try driver.tap(AppAccessibilityIdentifier.Settings.learnAction)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Learn.root)
    try driver.tap(AppAccessibilityIdentifier.Learn.startSampling)
    try driver.tap(AppAccessibilityIdentifier.Learn.startProbe)
    try driver.tap(AppAccessibilityIdentifier.Learn.confirmProbe)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .requestFanRPM),
      revision: driver.revision
    )
    _ = try driver.waitForPayload(
      participant: .agent,
      payload: .fanWrite(
        fanIndex: 0,
        rpm: Self.expectedProbeRPM,
        priority: 0
      ),
      revision: driver.revision
    )
    try driver.tap(AppAccessibilityIdentifier.Learn.cancel)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .requestFanAuto),
      revision: driver.revision
    )
    _ = try driver.waitForPayload(
      participant: .agent,
      payload: .fanAutoReset(fanIndex: 0),
      revision: driver.revision
    )
  }

  private func verifyAboutAndLifecycle(_ driver: FanCurveUITestDriver) throws {
    try driver.tap(AppAccessibilityIdentifier.Settings.advancedTab)
    try driver.tap(AppAccessibilityIdentifier.Settings.aboutTab)
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.aboutCommand
    )
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Application.aboutWindow)
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.quitCommand
    )
    try driver.waitForTermination()
    try driver.launch()
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Application.mainWindow)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
  }
}
