//
//  AgentCommandRoutingTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class AgentCommandRoutingTests: XCTestCase {
  func testDevScenarioRoutesHelperInstallThroughControlXPC() {
    expect(AgentCommand.installOrRepairHelper.devScenarioRoute) == .controlXPC
  }

  func testDevScenarioRoutesHelperApprovalThroughControlXPC() {
    expect(AgentCommand.openSystemSettings.devScenarioRoute) == .controlXPC
  }

  func testDevScenarioKeepsFanControlCommandsSimulated() {
    expect(AgentCommand.setFanControlEnabled(true).devScenarioRoute) == .simulation
  }
}
