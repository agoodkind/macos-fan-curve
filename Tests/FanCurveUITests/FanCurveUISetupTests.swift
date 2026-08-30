//
//  FanCurveUISetupTests.swift
//  FanCurveUITests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import XCTest

@MainActor
final class FanCurveUISetupTests: XCTestCase {
  func testSystemHelperLifecyclePresentationAndRecovery() throws {
    try FanCurveUIScenario.run(in: self) { driver in
      let registerFailure = TestOperationDirective.fail(
        code: "helper-registration-refused",
        message: "Helper registration refused"
      )
      try driver.prime(
        .make(
          helper: .notRegistered,
          serviceOperation: registerFailure,
          helperReachable: false,
          activeHelper: .unreachable(message: "Helper unavailable")
        )
      )
      try driver.launch()
      try verifySetup(driver, title: "Registration Needs Repair")
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Setup.message,
        equals: "System Helper is not registered"
      )
      try driver.tap(AppAccessibilityIdentifier.Setup.action)
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Setup.title,
        equals: "Repair Failed"
      )
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Setup.message,
        equals: "Register failed: Helper registration refused. Retry System Helper repair."
      )

      _ = try driver.apply(
        .make(
          helper: .enabled,
          helperReachable: true,
          activeHelper: .identity(FanCurveUITestState.bundledHelperIdentity)
        )
      )
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Setup.title,
        equals: "Repair Failed"
      )
      try driver.tap(AppAccessibilityIdentifier.Setup.action)
      _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)

      try driver.tapApplicationMenuCommand(
        AppAccessibilityIdentifier.Application.settingsCommand
      )
      try driver.tap(AppAccessibilityIdentifier.Settings.generalTab)
      try driver.waitForLabel(
        AppAccessibilityIdentifier.Settings.helperStatus,
        equals: "Running"
      )
    }
  }

  func testSystemHelperBusyTitlePersistsThroughVerification() throws {
    try FanCurveUIScenario.run(in: self) { driver in
      try launchSettingsDuringAutomaticHelperUpdate(driver)
      try finishBlockedHelperVerification(driver)
      try startBlockedManualHelperReinstall(driver)
      try finishBlockedHelperVerification(driver)
    }
  }

  func testSetupStatesFailuresAndEnabledHelperRepair() throws {
    try FanCurveUIScenario.run(in: self) { driver in
      try verifyBackgroundRegistrationFailure(driver)
      try verifyBackgroundApprovalFailure(driver)
      try verifyHelperRegistrationFailure(driver)
      try verifyHelperApprovalFailure(driver)
      try verifyHelperRepairFailure(driver)
      try verifyOriginalStuckStateRepair(driver)
    }
  }

  private func verifyBackgroundRegistrationFailure(
    _ driver: FanCurveUITestDriver
  ) throws {
    let registrationFailure = TestOperationDirective.fail(
      code: "background-registration-refused",
      message: "Background registration refused"
    )
    try driver.prime(
      .make(
        backgroundAgent: .notRegistered,
        serviceOperation: registrationFailure
      )
    )
    try driver.launch()
    try verifySetup(driver, title: "Enable Background Control")
    try driver.tap(AppAccessibilityIdentifier.Setup.action)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .serviceMutation(
        service: .backgroundAgent,
        operation: .register,
        result: registrationFailure
      ),
      revision: driver.revision
    )
    try verifyVisibleError(driver, message: "Background registration refused")
  }

  private func verifyBackgroundApprovalFailure(
    _ driver: FanCurveUITestDriver
  ) throws {
    let settingsFailure = TestOperationDirective.fail(
      code: "settings-unavailable",
      message: "System Settings unavailable"
    )
    _ = try driver.apply(
      .make(
        backgroundAgent: .approvalRequired,
        serviceOperation: settingsFailure
      )
    )
    try verifySetup(driver, title: "Allow Fan Curve in Background")
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.approvalGuide)
    try driver.tap(AppAccessibilityIdentifier.Setup.action)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .serviceMutation(
        service: .backgroundAgent,
        operation: .openSystemSettings,
        result: settingsFailure
      ),
      revision: driver.revision
    )
    try verifyVisibleError(driver, message: "System Settings unavailable")
  }

  private func verifyHelperRegistrationFailure(
    _ driver: FanCurveUITestDriver
  ) throws {
    let registrationFailure = TestOperationDirective.fail(
      code: "helper-registration-refused",
      message: "Helper registration refused"
    )
    _ = try driver.apply(
      .make(
        helper: .notRegistered,
        serviceOperation: registrationFailure,
        helperReachable: false
      )
    )
    try verifySetup(driver, title: "Registration Needs Repair")
    try driver.tap(AppAccessibilityIdentifier.Setup.action)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .installOrRepairHelper),
      revision: driver.revision
    )
    _ = try driver.waitForPayload(
      participant: .agent,
      payload: .serviceMutation(
        service: .helper,
        operation: .register,
        result: registrationFailure
      ),
      revision: driver.revision
    )
    try verifyVisibleError(driver, message: "Helper registration refused")
  }

  private func verifyHelperApprovalFailure(
    _ driver: FanCurveUITestDriver
  ) throws {
    let settingsFailure = TestOperationDirective.fail(
      code: "settings-unavailable",
      message: "System Settings unavailable"
    )
    _ = try driver.apply(
      .make(
        helper: .approvalRequired,
        serviceOperation: settingsFailure,
        helperReachable: false
      )
    )
    try verifySetup(driver, title: "Approval Required")
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.approvalGuide)
    try driver.tap(AppAccessibilityIdentifier.Setup.action)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .openSystemSettings),
      revision: driver.revision
    )
    try verifyVisibleError(driver, message: "System Settings unavailable")
    _ = try driver.waitForPayload(
      participant: .agent,
      payload: .serviceMutation(
        service: .helper,
        operation: .openSystemSettings,
        result: settingsFailure
      ),
      revision: driver.revision
    )
  }

  private func verifyHelperRepairFailure(
    _ driver: FanCurveUITestDriver
  ) throws {
    let repairFailure = TestOperationDirective.fail(
      code: "helper-repair-refused",
      message: "Helper repair refused"
    )
    _ = try driver.apply(
      .make(
        helper: .enabled,
        serviceOperation: repairFailure,
        helperReachable: false
      )
    )
    try verifySetup(driver, title: "Unavailable")
    try driver.tap(AppAccessibilityIdentifier.Setup.action)
    _ = try driver.waitForPayload(
      participant: .agent,
      payload: .serviceMutation(
        service: .helper,
        operation: .unregister,
        result: repairFailure
      ),
      revision: driver.revision
    )
    try verifyVisibleError(driver, message: "Helper repair refused")
  }

  private func verifyOriginalStuckStateRepair(
    _ driver: FanCurveUITestDriver
  ) throws {
    _ = try driver.apply(
      .make(
        helper: .enabled,
        serviceOperation: .succeed,
        helperReachable: false
      )
    )
    try verifySetup(driver, title: "Unavailable")
    try driver.tap(AppAccessibilityIdentifier.Setup.action)
    _ = try driver.waitForPayload(
      participant: .agent,
      payload: .serviceMutation(
        service: .helper,
        operation: .unregister,
        result: .succeed
      ),
      revision: driver.revision
    )
    _ = try driver.waitForPayload(
      participant: .agent,
      payload: .serviceMutation(
        service: .helper,
        operation: .register,
        result: .succeed
      ),
      revision: driver.revision
    )
    _ = try driver.apply(.make())
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.root)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Dashboard.fanRow(0))
  }

  private func verifySetup(
    _ driver: FanCurveUITestDriver,
    title: String
  ) throws {
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.root)
    try driver.waitForLabel(AppAccessibilityIdentifier.Setup.title, equals: title)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.message)
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.action)
  }

  private func verifyVisibleError(
    _ driver: FanCurveUITestDriver,
    message: String
  ) throws {
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Setup.error,
      equals: message
    )
  }
}

// MARK: - FanCurveUISetupTests

extension FanCurveUISetupTests {
  private func launchSettingsDuringAutomaticHelperUpdate(
    _ driver: FanCurveUITestDriver
  ) throws {
    try driver.prime(
      .make(
        activeHelper: .identity(FanCurveUITestState.outdatedHelperIdentity),
        helperVerificationBlocked: true
      )
    )
    try driver.launch()
    try driver.tapApplicationMenuCommand(
      AppAccessibilityIdentifier.Application.settingsCommand
    )
    try driver.tap(AppAccessibilityIdentifier.Settings.generalTab)
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Settings.helperStatus,
      equals: "Updating"
    )
  }

  private func startBlockedManualHelperReinstall(
    _ driver: FanCurveUITestDriver
  ) throws {
    _ = try driver.apply(
      .make(
        activeHelper: .identity(FanCurveUITestState.outdatedHelperIdentity),
        helperVerificationBlocked: true
      )
    )
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Settings.helperAction,
      equals: "Reinstall System Helper"
    )
    try driver.tap(AppAccessibilityIdentifier.Settings.helperAction)
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Settings.helperAction,
      equals: "Reinstalling System Helper"
    )
    _ = try driver.waitForElement(
      AppAccessibilityIdentifier.Settings.helperProgress
    )
  }

  private func finishBlockedHelperVerification(
    _ driver: FanCurveUITestDriver
  ) throws {
    _ = try driver.apply(
      .make(
        activeHelper: .identity(FanCurveUITestState.bundledHelperIdentity),
        helperVerificationBlocked: false
      )
    )
    try driver.waitForLabel(
      AppAccessibilityIdentifier.Settings.helperStatus,
      equals: "Running"
    )
    try driver.waitForElementToDisappear(
      AppAccessibilityIdentifier.Settings.helperProgress
    )
  }
}
