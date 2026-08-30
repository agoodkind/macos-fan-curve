//
//  SystemHelperLifecycleReconcilerTests.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

final class SystemHelperLifecycleReconcilerTests: XCTestCase {
  func testMatchingActiveHashRunsWithoutReplacingRegistration() async throws {
    let harness = try ReconcilerHarness(testCase: self, active: .bundled)

    let state = await harness.reconcile(.startup)

    expect(state) == .running(active: harness.bundledIdentity)
    expect(harness.service.registrationGeneration) == 1
    expect(harness.gate.isPaused) == false
  }

  func testReconnectRecognizesCurrentHelperWithoutReplacingRegistration() async throws {
    let harness = try ReconcilerHarness(testCase: self, active: .bundled)

    let state = await harness.reconcile(.reconnect)

    expect(state) == .running(active: harness.bundledIdentity)
    expect(harness.service.registrationGeneration) == 1
  }

  func testGenericIdentityFailureWithSuccessfulLegacyProbeReplacesHelper() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .legacy
    )

    let state = await harness.reconcile(.startup)

    expect(state) == .running(active: harness.bundledIdentity)
    expect(harness.service.registrationGeneration) == 2
    expect(harness.hardware.allFansAutomatic) == true
  }

  func testOutdatedIdentityReplacesAutomatically() async throws {
    let harness = try ReconcilerHarness(testCase: self, active: .outdated)

    let state = await harness.reconcile(.startup)

    expect(state) == .running(active: harness.bundledIdentity)
    expect(harness.service.registrationGeneration) == 2
    expect(harness.recorder.states).to(
      contain(
        .outdated(
          active: harness.outdatedIdentity,
          bundled: harness.bundledIdentity
        )
      )
    )
  }

  func testForcedRepairResetFailurePreservesEnabledUnreachableHelper() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      resetBehavior: .fail
    )

    let state = await harness.reconcile(.forcedRepair)

    expect(self.failureStage(of: state)) == .fanReset
    expect(harness.service.registrationGeneration) == 1
    expect(harness.service.unregisterCount) == 0
    expect(harness.service.hasRegistration) == true
  }

  func testMissingRegistrationRemainsRepairableWithoutAutomaticMutation() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notRegistered
    )

    let state = await harness.reconcile(.startup)

    expect(state)
      == .registrationNeedsRepair(reason: "System Helper is not registered")
    expect(harness.service.registrationGeneration) == 0
    expect(harness.gate.isPaused) == true
  }

  func testApprovalRemainsRequiredWithoutMutation() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .requiresApproval
    )

    let state = await harness.reconcile(.startup)

    expect(state) == .approvalRequired
    expect(harness.service.registrationGeneration) == 1
    expect(harness.gate.isPaused) == true
  }

  func testLoginItemsDenialAfterUnregisterRequiresApprovalAndKeepsJournal() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      registerBehavior: .operationNotPermitted
    )

    let state = await harness.reconcile(.startup)

    expect(state) == .approvalRequired
    expect(harness.service.hasRegistration) == false
    expect(harness.replacementJournal.hasPendingReplacement) == true
    expect(harness.gate.isPaused) == true
  }

  func testTransientOperationNotPermittedRetriesAndRuns() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      registerBehavior: .operationNotPermittedOnce
    )

    let state = await harness.reconcile(.startup)

    expect(state) == .running(active: harness.bundledIdentity)
    expect(harness.service.registrationGeneration) == 2
    expect(harness.replacementJournal.hasPendingReplacement) == false
    expect(harness.gate.isPaused) == false
  }

  func testInvalidBundledSignaturePreservesOldRegistration() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      artifactValidator: SystemHelperArtifactValidator(
        expectedBundleIdentifier: generatedHelperBundleID,
        expectedTeamIdentifier: generatedDevelopmentTeam,
        expectedVersion: generatedMarketingVersion,
        expectedBuild: generatedBuildNumber,
        commit: generatedGitCommit
      )
    )

    let state = await harness.reconcile(.startup)

    expect(self.failureStage(of: state)) == .preflight
    expect(harness.service.registrationGeneration) == 1
    expect(harness.service.hasRegistration) == true
  }

  func testFanResetFailurePreservesOldRegistration() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      resetBehavior: .fail
    )

    let state = await harness.reconcile(.startup)

    expect(self.failureStage(of: state)) == .fanReset
    expect(harness.service.hasRegistration) == true
    expect(harness.service.registrationGeneration) == 1
  }

  func testUnregisterFailureLeavesOldRegistrationAndFansAutomatic() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      unregisterBehavior: .fail
    )

    let state = await harness.reconcile(.startup)

    expect(self.failureStage(of: state)) == .unregister
    expect(harness.service.hasRegistration) == true
    expect(harness.hardware.allFansAutomatic) == true
  }

  func testRegisterFailureLeavesControlPausedAndFansAutomatic() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      registerBehavior: .fail
    )

    let state = await harness.reconcile(.startup)

    expect(self.failureStage(of: state)) == .register
    expect(harness.service.hasRegistration) == false
    expect(harness.hardware.allFansAutomatic) == true
    expect(harness.gate.isPaused) == true
    expect(state.activeIdentity) == nil
  }

  func testForcedRepairRegistersMissingHelperWithoutResetOrUnregister() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notRegistered
    )

    let state = await harness.reconcile(.forcedRepair)

    expect(state) == .running(active: harness.bundledIdentity)
    expect(harness.service.registrationGeneration) == 1
    expect(harness.service.unregisterCount) == 0
    expect(harness.hardware.resetCount) == 0
  }

  func testForcedRepairSurvivesConnectionInvalidatedSentinel() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .connectionInvalidated,
      serviceStatus: .notRegistered
    )

    let state = await harness.reconcile(.forcedRepair)

    expect(state) == .running(active: harness.bundledIdentity)
    expect(harness.service.registrationGeneration) == 1
    expect(harness.service.unregisterCount) == 0
    expect(harness.hardware.resetCount) == 0
  }

  func testForcedRepairResetsReachableUnregisteredHelperBeforeRegistering() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      serviceStatus: .notRegistered
    )

    let state = await harness.reconcile(.forcedRepair)

    expect(state) == .running(active: harness.bundledIdentity)
    expect(harness.hardware.resetCount) == 1
    expect(harness.service.unregisterCount) == 0
    expect(harness.service.registrationGeneration) == 1
  }

  func testRegistrationThrowAfterApprovalRequiredSkipsReconnect() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      registerBehavior: .requiresApproval,
      verificationTimeout: .seconds(1)
    )
    let clock = ContinuousClock()
    let start = clock.now

    let state = await harness.reconcile(.startup)

    expect(state) == .approvalRequired
    expect(harness.replacementJournal.hasPendingReplacement) == false
    expect(harness.hardware.identityRequestCount) == 1
    expect(start.duration(to: clock.now)) < .milliseconds(250)
  }

  func testReconnectTimeoutReportsReconnectStage() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      postRegisterIdentity: .unreachable,
      verificationTimeout: .milliseconds(80),
      verificationPollInterval: .milliseconds(10)
    )

    let state = await harness.reconcile(.startup)

    expect(self.failureStage(of: state)) == .reconnect
    expect(harness.gate.isPaused) == true
    expect(state.activeIdentity) == nil
  }

  func testHashMismatchAfterReconnectReportsIdentityVerificationStage() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      postRegisterIdentity: .outdated
    )

    let state = await harness.reconcile(.startup)

    expect(self.failureStage(of: state)) == .identityVerification
    expect(harness.gate.isPaused) == true
  }

  private func failureStage(
    of state: SystemHelperRuntimeState
  ) -> SystemHelperFailureStage? {
    guard case .repairFailed(_, _, let failure) = state else { return nil }
    return failure.stage
  }
}

// MARK: - Registration Safety

extension SystemHelperLifecycleReconcilerTests {
  func testInactiveServiceStateDoesNotDependOnBundledArtifactValidation() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notRegistered,
      artifactValidator: SystemHelperArtifactValidator(
        expectedBundleIdentifier: generatedHelperBundleID,
        expectedTeamIdentifier: generatedDevelopmentTeam,
        expectedVersion: generatedMarketingVersion,
        expectedBuild: generatedBuildNumber,
        commit: generatedGitCommit
      )
    )

    let state = await harness.reconcile(.startup)

    expect(state)
      == .registrationNeedsRepair(reason: "System Helper is not registered")
    expect(harness.hardware.identityRequestCount) == 0
  }

  func testArtifactChangeAfterUnregisterStopsRegistration() async throws {
    let harness = try ReconcilerHarness(testCase: self, active: .outdated)
    let executableURL = harness.bundledExecutableURL
    harness.service.setOnUnregistered {
      try Data("changed-system-helper".utf8).write(to: executableURL)
    }

    let state = await harness.reconcile(.startup)

    expect(self.failureStage(of: state)) == .register
    expect(harness.service.hasRegistration) == false
    expect(harness.service.registrationGeneration) == 1
  }
}

// MARK: - Concurrency

extension SystemHelperLifecycleReconcilerTests {

  func testConcurrentTriggersShareOneSerializedReplacement() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      mutationDelay: .milliseconds(30)
    )

    async let startup = harness.reconcile(.startup)
    async let forcedRepair = harness.reconcile(.forcedRepair)
    let states = await [startup, forcedRepair]

    expect(states) == [
      .running(active: harness.bundledIdentity),
      .running(active: harness.bundledIdentity),
    ]
    expect(harness.service.registrationGeneration) == 2
  }

  func testForcedRepairRunsAfterConcurrentHealthyStartupCheck() async throws {
    let startupCheckStarted = expectation(description: "startup check started")
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .bundled,
      identityDelay: .milliseconds(30),
      identityRequestStarted: startupCheckStarted
    )

    let startup = Task { await harness.reconcile(.startup) }
    await fulfillment(of: [startupCheckStarted], timeout: 1)
    let forcedRepair = Task { await harness.reconcile(.forcedRepair) }
    let states = await [startup.value, forcedRepair.value]

    expect(states) == [
      .running(active: harness.bundledIdentity),
      .running(active: harness.bundledIdentity),
    ]
    expect(harness.service.registrationGeneration) == 2
    expect(harness.service.unregisterCount) == 1
  }

  func testCancellingJoinedCallerPreservesSharedReplacement() async throws {
    let identityRequestStarted = expectation(description: "identity request started")
    let joinerStarted = expectation(description: "joiner started")
    let unregisterStarted = expectation(description: "unregister started")
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      identityDelay: .milliseconds(20),
      identityRequestStarted: identityRequestStarted,
      unregisterStarted: unregisterStarted,
      mutationDelay: .milliseconds(80)
    )
    let owner = Task { await harness.reconcile(.startup) }
    await fulfillment(of: [identityRequestStarted], timeout: 1)
    let joiner = Task {
      joinerStarted.fulfill()
      return await harness.reconcile(.startup)
    }
    await fulfillment(of: [joinerStarted, unregisterStarted], timeout: 1)

    joiner.cancel()
    let ownerState = await owner.value
    _ = await joiner.value

    expect(ownerState) == .running(active: harness.bundledIdentity)
    expect(harness.service.registrationGeneration) == 2
  }

  func testCancellingOwnerPreservesSharedReplacementForJoiner() async throws {
    let identityRequestStarted = expectation(description: "identity request started")
    let joinerStarted = expectation(description: "joiner started")
    let unregisterStarted = expectation(description: "unregister started")
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      identityDelay: .milliseconds(20),
      identityRequestStarted: identityRequestStarted,
      unregisterStarted: unregisterStarted,
      mutationDelay: .milliseconds(80)
    )
    let owner = Task { await harness.reconcile(.startup) }
    await fulfillment(of: [identityRequestStarted], timeout: 1)
    let joiner = Task {
      joinerStarted.fulfill()
      return await harness.reconcile(.startup)
    }
    await fulfillment(of: [joinerStarted, unregisterStarted], timeout: 1)

    owner.cancel()
    let joinerState = await joiner.value
    _ = await owner.value

    expect(joinerState) == .running(active: harness.bundledIdentity)
    expect(harness.service.registrationGeneration) == 2
  }

  func testForcedRepairCancellationBeforeMutationPreservesRegistration() async throws {
    let identityRequestStarted = expectation(description: "identity request started")
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      identityDelay: .seconds(5),
      identityRequestStarted: identityRequestStarted
    )
    let repair = Task { await harness.reconcile(.forcedRepair) }
    await fulfillment(of: [identityRequestStarted], timeout: 1)

    repair.cancel()
    _ = await repair.value

    expect(harness.hardware.resetCount) == 0
    expect(harness.service.unregisterCount) == 0
    expect(harness.service.registrationGeneration) == 1
  }

  func testForcedRepairCancellationAfterUnregisterCompletesRegistration() async throws {
    let unregisterCompleted = expectation(description: "unregister completed")
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      unregisterCompleted: unregisterCompleted,
      mutationDelay: .milliseconds(80)
    )
    let repair = Task { await harness.reconcile(.forcedRepair) }
    await fulfillment(of: [unregisterCompleted], timeout: 1)

    repair.cancel()
    _ = await repair.value

    expect(harness.service.hasRegistration) == true
    expect(harness.service.registrationGeneration) == 2
  }

  func testCancellationStopsLegacyProbe() async throws {
    let legacyProbeStarted = expectation(description: "legacy probe started")
    let legacyProbeCancelled = expectation(description: "legacy probe cancelled")
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .legacy,
      legacyProbeStarted: legacyProbeStarted,
      legacyProbeCancelled: legacyProbeCancelled
    )
    let reconciliation = Task {
      await harness.reconcile(.startup)
    }
    await fulfillment(of: [legacyProbeStarted], timeout: 1)

    reconciliation.cancel()

    await fulfillment(of: [legacyProbeCancelled], timeout: 1)
    _ = await reconciliation.value
    expect(harness.service.registrationGeneration) == 1
  }

  func testCancellationStopsReconnectVerificationPolling() async throws {
    let verificationStarted = expectation(description: "verification started")
    let additionalVerificationStarted = expectation(
      description: "additional verification started"
    )
    additionalVerificationStarted.isInverted = true
    let reconciliationCompleted = expectation(description: "reconciliation completed")
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .outdated,
      postRegisterIdentity: .unreachable,
      additionalVerificationStarted: additionalVerificationStarted,
      verificationStarted: verificationStarted,
      verificationTimeout: .seconds(5),
      verificationPollInterval: .seconds(1)
    )
    let reconciliation = Task {
      let state = await harness.reconcile(.startup)
      reconciliationCompleted.fulfill()
      return state
    }
    await fulfillment(of: [verificationStarted], timeout: 1)

    reconciliation.cancel()
    await fulfillment(of: [reconciliationCompleted], timeout: 0.25)
    _ = await reconciliation.value
    let identityRequestCount = harness.hardware.identityRequestCount
    await fulfillment(of: [additionalVerificationStarted], timeout: 0.05)

    expect(harness.hardware.identityRequestCount) == identityRequestCount
  }

}
