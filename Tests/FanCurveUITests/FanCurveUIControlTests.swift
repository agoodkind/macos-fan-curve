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
  private static let curveControlPointCount = 8
  private static let curveControlPointIndex = 2
  private static let curveControlPointDragOffset = CGVector(dx: 0, dy: -40)
  private static let expectedProbeRPM: Float = 15_000

  private struct DashboardPersistentState {
    let fanControlEnabled: Bool
    let boostEnabled: Bool
    let controlPointFrames: [CGRect]
  }

  private struct SettingsPersistentState {
    let applyInBackground: Bool
  }

  private struct ExtendedRangePersistentState {
    let accessAllowed: Bool
    let overdriveEnabled: Bool
    let underdriveEnabled: Bool
  }

  func testAboutReportsUnavailableWithoutActiveHelperIdentity() throws {
    try FanCurveUIScenario.run(in: self) { driver in
      try driver.prime(
        .make(
          helperReachable: false,
          activeHelper: .unreachable(message: "Helper unavailable")
        )
      )
      try driver.launch()
      try driver.tapApplicationMenuCommand(
        AppAccessibilityIdentifier.Application.aboutCommand
      )
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Application.aboutWindow)
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Application.aboutSystemHelperVersion,
        equals: "Unavailable"
      )
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Application.aboutSystemHelperHash,
        equals: "Unavailable"
      )
    }
  }

  func testCurveControlSettingsOwnershipManualFanAndLifecycle() throws {
    try FanCurveUIScenario.run(in: self) { driver in
      try driver.prime(.make())
      try driver.launch()
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
      try verifyCurveAndControls(driver)
      try verifyExtendedRangeControls(driver)
      try verifyGeneralSettingsAndOwnership(driver)
      try verifyManualFanAndReset(driver)
      try verifyAboutAndLifecycle(driver)
    }
  }

  private func verifyExtendedRangeControls(_ driver: FanCurveUITestDriver) throws {
    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.fanControl, to: true)
    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.boost, to: false)
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.settingsCommand
    )
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.root)
    try driver.tap(AppAccessibilityIdentifier.Settings.advancedTab)
    let originalAccessAllowed = try driver.booleanControlValue(
      AppAccessibilityIdentifier.Settings.extendedRangeAccess
    )
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Settings.extendedRangeAccess,
      to: true
    )
    driver.closeWindow(named: "Settings")
    let persistentState = ExtendedRangePersistentState(
      accessAllowed: originalAccessAllowed,
      overdriveEnabled: try driver.booleanControlValue(
        AppAccessibilityIdentifier.Dashboard.overdrive
      ),
      underdriveEnabled: try driver.booleanControlValue(
        AppAccessibilityIdentifier.Dashboard.underdrive
      )
    )
    driver.registerCleanup {
      try self.restoreExtendedRangePersistentState(persistentState, driver: driver)
    }

    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.overdrive, to: false)
    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.underdrive, to: false)
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.settingsCommand
    )
    try driver.tap(AppAccessibilityIdentifier.Settings.advancedTab)
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Settings.extendedRangeAccess,
      to: false
    )
    driver.closeWindow(named: "Settings")
    XCTAssertFalse(driver.element(AppAccessibilityIdentifier.Dashboard.overdrive).exists)
    XCTAssertFalse(driver.element(AppAccessibilityIdentifier.Dashboard.underdrive).exists)

    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.settingsCommand
    )
    try driver.tap(AppAccessibilityIdentifier.Settings.advancedTab)
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Settings.extendedRangeAccess,
      to: true
    )
    driver.closeWindow(named: "Settings")
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.overdrive)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.underdrive)
    try driver.cancelBooleanControlEnablement(
      AppAccessibilityIdentifier.Dashboard.overdrive,
      alertTitle: "Enable Overdrive?"
    )
    try driver.enableBooleanControl(
      AppAccessibilityIdentifier.Dashboard.overdrive,
      alertTitle: "Enable Overdrive?"
    )
    try driver.enableBooleanControl(
      AppAccessibilityIdentifier.Dashboard.underdrive,
      alertTitle: "Enable Underdrive?"
    )
    try driver.relaunch()
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.overdrive)
    XCTAssertTrue(try driver.booleanControlValue(AppAccessibilityIdentifier.Dashboard.overdrive))
    XCTAssertTrue(try driver.booleanControlValue(AppAccessibilityIdentifier.Dashboard.underdrive))
  }

  private func verifyCurveAndControls(_ driver: FanCurveUITestDriver) throws {
    let persistentState = try captureDashboardPersistentState(driver)
    driver.registerCleanup {
      try self.restoreDashboardPersistentState(
        persistentState,
        driver: driver
      )
    }
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Dashboard.fanControl,
      to: true
    )

    try driver.drag(
      AppAccessibilityIdentifier.Curve.controlPoint(Self.curveControlPointIndex),
      normalizedOffset: Self.curveControlPointDragOffset
    )
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .setCurve),
      revision: driver.revision
    )
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Dashboard.boost,
      to: false
    )
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Dashboard.fanControl,
      to: false
    )
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .setFanControlEnabled),
      revision: driver.revision
    )
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Dashboard.fanControl,
      to: true
    )
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Dashboard.boost,
      to: true
    )
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .setBoostEnabled),
      revision: driver.revision
    )
  }

  private func captureDashboardPersistentState(
    _ driver: FanCurveUITestDriver
  ) throws -> DashboardPersistentState {
    let originalFanControl = try driver.booleanControlValue(
      AppAccessibilityIdentifier.Dashboard.fanControl
    )
    let originalControlPointFrames = try driver.controlPointFrames(
      count: Self.curveControlPointCount
    )
    let originalBoost: Bool
    if originalFanControl {
      originalBoost = try driver.booleanControlValue(
        AppAccessibilityIdentifier.Dashboard.boost
      )
    } else {
      originalBoost = false
    }
    return DashboardPersistentState(
      fanControlEnabled: originalFanControl,
      boostEnabled: originalBoost,
      controlPointFrames: originalControlPointFrames
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
    let persistentState = SettingsPersistentState(
      applyInBackground: try driver.booleanControlValue(
        AppAccessibilityIdentifier.Settings.applyInBackground
      )
    )
    driver.registerCleanup {
      try self.restoreSettingsPersistentState(
        persistentState,
        driver: driver
      )
    }
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Settings.applyInBackground,
      to: !persistentState.applyInBackground
    )
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
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Application.aboutSystemHelperVersion,
      equals: "0.4.2 (build 42)"
    )
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Application.aboutSystemHelperHash,
      equals: "bundled-helper-full-hash"
    )
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.quitCommand
    )
    try driver.waitForTermination()
    try driver.launch()
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Application.mainWindow)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
  }

  private func restoreDashboardPersistentState(
    _ state: DashboardPersistentState,
    driver: FanCurveUITestDriver
  ) throws {
    driver.app.activate()
    driver.closeWindow(named: "About Fan Curve")
    driver.closeWindow(named: "Settings")
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Dashboard.fanControl,
      to: true
    )
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Dashboard.boost,
      to: false
    )
    try driver.restoreControlPointFrames(state.controlPointFrames)
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Dashboard.boost,
      to: state.boostEnabled
    )
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Dashboard.fanControl,
      to: state.fanControlEnabled
    )
  }

  private func restoreSettingsPersistentState(
    _ state: SettingsPersistentState,
    driver: FanCurveUITestDriver
  ) throws {
    driver.app.activate()
    if !driver.element(AppAccessibilityIdentifier.Settings.applyInBackground).exists {
      try driver.tapApplicationMenuCommand(
        AppAccessibilityIdentifier.Application.settingsCommand
      )
    }
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.root)
    try driver.tap(AppAccessibilityIdentifier.Settings.generalTab)
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Settings.applyInBackground,
      to: state.applyInBackground
    )
    driver.closeWindow(named: "Settings")
  }

  private func restoreExtendedRangePersistentState(
    _ state: ExtendedRangePersistentState,
    driver: FanCurveUITestDriver
  ) throws {
    driver.app.activate()
    driver.closeWindow(named: "Settings")
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.fanControl, to: true)
    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.boost, to: false)
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.settingsCommand
    )
    try driver.tap(AppAccessibilityIdentifier.Settings.advancedTab)
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Settings.extendedRangeAccess,
      to: true
    )
    driver.closeWindow(named: "Settings")
    if state.overdriveEnabled {
      try driver.enableBooleanControl(
        AppAccessibilityIdentifier.Dashboard.overdrive,
        alertTitle: "Enable Overdrive?"
      )
    } else {
      try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.overdrive, to: false)
    }
    if state.underdriveEnabled {
      try driver.enableBooleanControl(
        AppAccessibilityIdentifier.Dashboard.underdrive,
        alertTitle: "Enable Underdrive?"
      )
    } else {
      try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.underdrive, to: false)
    }
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.settingsCommand
    )
    try driver.tap(AppAccessibilityIdentifier.Settings.advancedTab)
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Settings.extendedRangeAccess,
      to: state.accessAllowed
    )
    driver.closeWindow(named: "Settings")
  }
}
