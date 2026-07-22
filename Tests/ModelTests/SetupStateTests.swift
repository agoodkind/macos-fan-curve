//
//  SetupStateTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-06-14.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class SetupStateTests: XCTestCase {
  func testEnabledHelperRegistrationReinstallsService() {
    let plan = HelperServiceRegistration.Plan.resolve(serviceEnabled: true)

    expect(plan) == .unregisterThenRegister
  }

  func testAgentInstalledWithMissingHelperRequiresHelperInstall() {
    let setupState = SetupState.resolve(
      backgroundAgent: .satisfied,
      helper: .required
    )

    expect(setupState) == .helperRequired(action: .installHelper)
  }

  func testHelperInstalledWithMissingAgentRequiresBackgroundAgent() {
    let setupState = SetupState.resolve(
      backgroundAgent: .required,
      helper: .satisfied
    )

    expect(setupState) == .backgroundAgentRequired(action: .enableBackgroundAgent)
  }

  func testMissingAgentAndHelperRequiresHelperInstallFirst() {
    let setupState = SetupState.resolve(
      backgroundAgent: .required,
      helper: .required
    )

    expect(setupState) == .helperRequired(action: .installHelper)
  }
}
