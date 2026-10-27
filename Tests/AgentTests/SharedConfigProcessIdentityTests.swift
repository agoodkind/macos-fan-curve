//
//  SharedConfigProcessIdentityTests.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

final class SharedConfigProcessIdentityTests: XCTestCase {
  func testHeartbeatKeepsHashCapturedForRunningProcess() throws {
    let scratch = try ScratchDefaults(label: "SharedConfigProcessIdentityTests")
    defer { scratch.remove() }
    let defaults = scratch.defaults
    let config = SharedConfig(defaults: defaults, runningExecutableHash: "original-agent")

    config.writeAgentStatus(pid: 1, lastTick: Date())
    defaults.set("replacement-agent", forKey: SharedConfigKeys.agentExecutableHash)
    config.writeAgentStatus(pid: 1, lastTick: Date())

    expect(defaults.string(forKey: SharedConfigKeys.agentExecutableHash)) == "original-agent"
  }
}
