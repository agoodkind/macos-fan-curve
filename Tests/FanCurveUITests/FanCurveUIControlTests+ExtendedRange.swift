//
//  FanCurveUIControlTests+ExtendedRange.swift
//  FanCurveUITests
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-08-30.
//  Copyright © 2026, all rights reserved.
//

import XCTest

private struct ExtendedRangePersistentState {
  let accessAllowed: Bool
  let overdriveEnabled: Bool
  let underdriveEnabled: Bool
}

// MARK: - FanCurveUIControlTests

@MainActor
extension FanCurveUIControlTests {
  func verifyExtendedRangeControls(_ driver: FanCurveUITestDriver) throws {
    try prepareExtendedRangeControls(driver)
    let persistentState = try captureExtendedRangePersistentState(driver)
    driver.registerCleanup {
      try self.restoreExtendedRangePersistentState(persistentState, driver: driver)
    }

    try verifyExtendedRangeAccessGate(driver)
    try verifyExtendedRangeConfirmations(driver)
  }

  private func prepareExtendedRangeControls(_ driver: FanCurveUITestDriver) throws {
    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.fanControl, to: true)
    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.boost, to: false)
  }

  private func captureExtendedRangePersistentState(
    _ driver: FanCurveUITestDriver
  ) throws -> ExtendedRangePersistentState {
    try openAdvancedSettings(driver)
    let accessAllowed = try driver.booleanControlValue(
      AppAccessibilityIdentifier.Settings.extendedRangeAccess
    )
    driver.closeWindow(named: "Settings")
    try setExtendedRangeAccess(true, driver: driver)
    return ExtendedRangePersistentState(
      accessAllowed: accessAllowed,
      overdriveEnabled: try driver.booleanControlValue(
        AppAccessibilityIdentifier.Dashboard.overdrive
      ),
      underdriveEnabled: try driver.booleanControlValue(
        AppAccessibilityIdentifier.Dashboard.underdrive
      )
    )
  }

  private func verifyExtendedRangeAccessGate(_ driver: FanCurveUITestDriver) throws {
    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.overdrive, to: false)
    try driver.setBooleanControl(AppAccessibilityIdentifier.Dashboard.underdrive, to: false)
    try setExtendedRangeAccess(false, driver: driver)
    guard !driver.element(AppAccessibilityIdentifier.Dashboard.overdrive).exists else {
      throw FanCurveUITestDriverError.invalidEnvironment("Overdrive remained visible")
    }
    guard !driver.element(AppAccessibilityIdentifier.Dashboard.underdrive).exists else {
      throw FanCurveUITestDriverError.invalidEnvironment("Underdrive remained visible")
    }
    try setExtendedRangeAccess(true, driver: driver)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.overdrive)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.underdrive)
  }

  private func verifyExtendedRangeConfirmations(_ driver: FanCurveUITestDriver) throws {
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
    guard try driver.booleanControlValue(AppAccessibilityIdentifier.Dashboard.overdrive) else {
      throw FanCurveUITestDriverError.invalidEnvironment("Overdrive did not persist")
    }
    guard try driver.booleanControlValue(AppAccessibilityIdentifier.Dashboard.underdrive) else {
      throw FanCurveUITestDriverError.invalidEnvironment("Underdrive did not persist")
    }
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
    try setExtendedRangeAccess(true, driver: driver)
    try restoreExtendedRangeModes(state, driver: driver)
    try setExtendedRangeAccess(state.accessAllowed, driver: driver)
  }

  private func restoreExtendedRangeModes(
    _ state: ExtendedRangePersistentState,
    driver: FanCurveUITestDriver
  ) throws {
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
  }

  private func setExtendedRangeAccess(
    _ allowed: Bool,
    driver: FanCurveUITestDriver
  ) throws {
    try openAdvancedSettings(driver)
    try driver.setBooleanControl(
      AppAccessibilityIdentifier.Settings.extendedRangeAccess,
      to: allowed
    )
    driver.closeWindow(named: "Settings")
  }

  private func openAdvancedSettings(_ driver: FanCurveUITestDriver) throws {
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.settingsCommand
    )
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Settings.root)
    try driver.tap(AppAccessibilityIdentifier.Settings.advancedTab)
  }
}
