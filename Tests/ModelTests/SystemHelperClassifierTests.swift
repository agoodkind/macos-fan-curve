//
//  SystemHelperClassifierTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class SystemHelperClassifierTests: XCTestCase {
  func testMatchingExecutableHashRunsDespiteDifferentVersionText() {
    let active = identity(version: "0.3.0", build: "8", hash: bundled.executableHash)

    let runtime = resolve(
      serviceStatus: .enabled,
      observation: .identity(active)
    )

    expect(runtime.systemHelper) == .running(active: active)
    expect(runtime.setup) == .ready
    expect(runtime.systemHelper.permitsFanControl) == true
  }

  func testMismatchedExecutableHashIsOutdated() {
    let active = identity(version: "0.4.0", build: "1", hash: "active-hash")

    let runtime = resolve(
      serviceStatus: .enabled,
      observation: .identity(active)
    )

    expect(runtime.systemHelper) == .outdated(active: active, bundled: bundled)
    expect(runtime.setup) == .ready
    expect(runtime.systemHelper.permitsFanControl) == false
  }

  func testLegacyReachableHelperIsOutdatedWithoutActiveIdentity() {
    let runtime = resolve(
      serviceStatus: .enabled,
      observation: .legacyReachable
    )

    expect(runtime.systemHelper) == .outdated(active: nil, bundled: bundled)
    expect(runtime.setup) == .ready
  }

  func testFailedIdentityAndLegacyProbeIsUnavailable() {
    let runtime = resolve(
      serviceStatus: .enabled,
      observation: .unreachable(reason: "identity and legacy probes failed")
    )

    expect(runtime.systemHelper)
      == .unavailable(reason: "identity and legacy probes failed")
    expect(runtime.setup) == .helperRequired(action: .installHelper)
  }

  func testNotRegisteredHelperNeedsRegistrationRepair() {
    let runtime = resolve(
      serviceStatus: .notRegistered,
      observation: .unreachable(reason: "not attempted")
    )

    expect(runtime.systemHelper)
      == .registrationNeedsRepair(reason: "System Helper is not registered")
    expect(runtime.setup) == .helperRequired(action: .installHelper)
  }

  func testHelperRequiringApprovalNeedsApproval() {
    let runtime = resolve(
      serviceStatus: .requiresApproval,
      observation: .unreachable(reason: "not attempted")
    )

    expect(runtime.systemHelper) == .approvalRequired
    expect(runtime.setup) == .helperApproval(action: .approveHelper)
  }

  func testMissingRegistrationDefinitionIsUnavailable() {
    let runtime = resolve(
      serviceStatus: .notFound,
      observation: .unreachable(reason: "not attempted")
    )

    expect(runtime.systemHelper)
      == .unavailable(
        reason: "System Helper registration definition was not found"
      )
    expect(runtime.setup) == .helperRequired(action: .installHelper)
  }

  func testUnknownServiceStatusIsUnavailable() {
    let runtime = resolve(
      serviceStatus: .unknown(rawValue: 42),
      observation: .unreachable(reason: "not attempted")
    )

    expect(runtime.systemHelper)
      == .unavailable(reason: "System Helper service status is unknown (42)")
    expect(runtime.setup) == .helperRequired(action: .installHelper)
  }

  private let bundled = SystemHelperIdentity(
    version: "0.4.0",
    build: "1",
    commit: "bundled-commit",
    executableHash: "bundled-hash",
    protocolVersion: 1
  )

  private func identity(version: String, build: String, hash: String) -> SystemHelperIdentity {
    SystemHelperIdentity(
      version: version,
      build: build,
      commit: "active-commit",
      executableHash: hash,
      protocolVersion: 1
    )
  }

  private func resolve(
    serviceStatus: ManagedServiceStatus,
    observation: SystemHelperIdentityObservation
  ) -> RuntimeState {
    let systemHelper = SystemHelperClassifier.classify(
      serviceStatus: serviceStatus,
      observation: observation,
      bundled: bundled
    )
    return RuntimeState.resolve(
      RuntimeStateInputs(
        setup: RuntimeSetupInputs(backgroundAgent: .satisfied),
        systemHelper: systemHelper,
        snapshot: nil
      )
    )
  }
}
