//
//  SystemHelperReplacementResumeTests.swift
//  FanCurveAgentTests
//
//  Created by Claude <noreply@anthropic.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

final class SystemHelperReplacementResumeTests: XCTestCase {
  func testPendingJournalResumesRegistrationOnStartup() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notRegistered
    )
    harness.replacementJournal.recordPendingReplacement()

    let state = await harness.reconcile(.startup)

    guard case .running(let active) = state else {
      XCTFail("Expected running state, got \(state)")
      return
    }
    expect(active) == harness.bundledIdentity
    expect(harness.service.status) == .enabled
    expect(harness.replacementJournal.hasPendingReplacement) == false
  }

  func testUnregisteredHelperWithoutJournalStaysNeedsRepair() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notRegistered
    )

    let state = await harness.reconcile(.startup)

    guard case .registrationNeedsRepair = state else {
      XCTFail("Expected registrationNeedsRepair state, got \(state)")
      return
    }
    expect(harness.service.status) == .notRegistered
  }

  func testFailedRegistrationKeepsJournalForNextReconcile() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .legacy,
      serviceStatus: .enabled,
      registerBehavior: .fail
    )

    let state = await harness.reconcile(.startup)

    guard case .repairFailed(_, _, let failure) = state else {
      XCTFail("Expected repairFailed state, got \(state)")
      return
    }
    expect(failure.stage) == .register
    expect(harness.replacementJournal.hasPendingReplacement) == true
  }
}
