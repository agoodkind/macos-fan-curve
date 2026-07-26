//
//  FanCurveUISetupTests.swift
//  FanCurveUITests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import XCTest

@MainActor
final class FanCurveUISetupTests: XCTestCase {
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
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.error)
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
    try verifySetup(driver, title: "Install the System Helper")
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
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.error)
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
    try verifySetup(driver, title: "Allow the System Helper")
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.approvalGuide)
    try driver.tap(AppAccessibilityIdentifier.Setup.action)
    _ = try driver.waitForPayload(
      participant: .app,
      payload: .appToAgentCommand(command: .openSystemSettings),
      revision: driver.revision
    )
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
    try verifySetup(driver, title: "Install the System Helper")
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
    _ = try driver.waitForElement(AppAccessibilityIdentifier.Setup.error)
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
    try verifySetup(driver, title: "Install the System Helper")
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
}
