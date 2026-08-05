//
//  SystemHelperPresentationTests.swift
//  FanCurveModelsTests
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class SystemHelperPresentationTests: XCTestCase {
  func testRuntimeStatesHaveDistinctPrimaryStatus() {
    let cases: [(SystemHelperRuntimeState, String)] = [
      (.checking, "Checking"),
      (.running(active: active), "Running"),
      (.updating(active: active, bundled: bundled), "Updating"),
      (.outdated(active: active, bundled: bundled), "Outdated"),
      (.registrationNeedsRepair(reason: "Registration is missing"), "Registration Needs Repair"),
      (.approvalRequired, "Approval Required"),
      (.repairFailed(active: active, bundled: bundled, failure: failure), "Repair Failed"),
      (.unavailable(reason: "Connection refused"), "Unavailable"),
    ]

    for (state, expectedStatus) in cases {
      expect(SystemHelperPresentation.resolve(state: state, repairInFlight: false).status)
        == expectedStatus
    }
  }

  func testOutdatedDetailNamesActiveAndBundledVersions() {
    let presentation = SystemHelperPresentation.resolve(
      state: .outdated(active: active, bundled: bundled),
      repairInFlight: false
    )

    expect(presentation.detail)
      == "Active version: 0.3.0 (build 3). Bundled version: 0.4.0 (build 4)."
  }

  func testRegistrationRepairDetailDoesNotRepeatReachability() {
    let presentation = SystemHelperPresentation.resolve(
      state: .registrationNeedsRepair(reason: "Registration is missing"),
      repairInFlight: false
    )

    expect(presentation.detail) == "Registration is missing"
    expect(presentation.detail).toNot(contain("reachable"))
  }

  func testRepairFailureDetailIncludesStageReasonAndRecovery() {
    let presentation = SystemHelperPresentation.resolve(
      state: .repairFailed(active: active, bundled: bundled, failure: failure),
      repairInFlight: false
    )

    expect(presentation.detail)
      == "Register failed: Registration refused. Retry System Helper repair."
  }

  func testOnlyApprovalOpensSystemSettings() {
    let states: [SystemHelperRuntimeState] = [
      .checking,
      .running(active: active),
      .updating(active: active, bundled: bundled),
      .outdated(active: active, bundled: bundled),
      .registrationNeedsRepair(reason: "Registration is missing"),
      .repairFailed(active: active, bundled: bundled, failure: failure),
      .unavailable(reason: "Connection refused"),
    ]

    let actions = states.map { state in
      SystemHelperPresentation.resolve(state: state, repairInFlight: false).action
    }

    expect(
      SystemHelperPresentation.resolve(state: .approvalRequired, repairInFlight: false).action
    ) == .openSystemSettings
    expect(actions) == [nil, .repair, .repair, .repair, .repair, .repair, .repair]
  }

  func testActiveIdentityUsesReinstallTitle() {
    let presentation = SystemHelperPresentation.resolve(
      state: .running(active: active),
      repairInFlight: false
    )

    expect(presentation.actionTitle) == "Reinstall System Helper"
    expect(presentation.action) == .repair
  }

  func testRepairStaysBusyThroughIdentityVerification() {
    let presentation = SystemHelperPresentation.resolve(
      state: .updating(active: active, bundled: bundled),
      repairInFlight: false
    )

    expect(presentation.actionTitle) == "Reinstalling System Helper"
    expect(presentation.isBusy) == true
  }

  func testAboutUsesActiveIdentityVersionAndHash() {
    let state = SystemHelperRuntimeState.running(active: active)

    expect(SystemHelperPresentation.activeVersion(for: state)) == "0.3.0 (build 3)"
    expect(SystemHelperPresentation.activeHash(for: state)) == "active-full-hash"
  }

  func testAboutReportsUnavailableWithoutActiveIdentity() {
    expect(SystemHelperPresentation.activeVersion(for: .checking)) == "Unavailable"
    expect(SystemHelperPresentation.activeHash(for: .checking)) == "Unavailable"
  }

  private let active = SystemHelperIdentity(
    version: "0.3.0",
    build: "3",
    commit: "active-commit",
    executableHash: "active-full-hash",
    protocolVersion: 1
  )

  private let bundled = SystemHelperIdentity(
    version: "0.4.0",
    build: "4",
    commit: "bundled-commit",
    executableHash: "bundled-full-hash",
    protocolVersion: 1
  )

  private let failure = SystemHelperFailure(
    operation: .forcedRepair,
    stage: .register,
    reason: "Registration refused",
    recovery: "Retry System Helper repair"
  )
}
