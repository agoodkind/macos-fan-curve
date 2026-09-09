//
//  GuidedSetupTests.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-07.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

// MARK: - GuidedSetupTests

@MainActor
final class GuidedSetupTests: XCTestCase {
  func testFreshSetupRegistersAgentBeforeUnknownHelperCanBlockIt() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()
    state.refreshOnce(agentClient: fixture.client)

    expect(state.setupActionTitle) == "Enable Background Control"
    expect(state.setupActionIsBusy) == false
    state.performSetupAction(agentClient: fixture.client)

    expect(fixture.service.status) == .enabled
    expect(fixture.service.registerCount) == 1
    expect(fixture.client.installCount) == 0
    expect(state.setupStatusText) == "Waiting for Background Agent"
  }

  func testApprovalAndRelaunchResumeWithoutRepeatingAgentRegistration() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.registrationStatus = .requiresApproval
    let first = fixture.makeState()
    first.beginSetup(agentClient: fixture.client)
    expect(first.setupActionTitle) == "Open System Settings"

    let resumed = fixture.makeState()
    resumed.refreshOnce(agentClient: fixture.client)
    resumed.performSetupAction(agentClient: fixture.client)
    expect(fixture.service.settingsOpenCount) == 1
    expect(fixture.service.registerCount) == 1
    expect(fixture.client.installCount) == 0

    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .registrationNeedsRepair(reason: "Not registered")
    let installed = expectation(description: "Helper installation returns")
    fixture.client.installationFinished = installed
    resumed.refreshOnce(agentClient: fixture.client)
    await fulfillment(of: [installed], timeout: 1)
    await resumed.setupTask?.value
    expect(fixture.client.installCount) == 1
    expect(fixture.service.registerCount) == 1
  }

  func testHelperApprovalSurvivesRelaunchAndCompletionRequiresRunningIdentity() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .unavailable(reason: "Definition not found")
    fixture.client.installedState = .approvalRequired
    let installed = expectation(description: "Helper installation returns")
    fixture.client.installationFinished = installed
    let first = fixture.makeState()
    first.beginSetup(agentClient: fixture.client)
    await fulfillment(of: [installed], timeout: 1)
    await first.setupTask?.value
    first.refreshOnce(agentClient: fixture.client)
    expect(first.setupProgress) == .verifyingHelper
    expect(first.setupActionTitle) == "Open System Settings"

    let resumed = fixture.makeState()
    resumed.refreshOnce(agentClient: fixture.client)
    resumed.refreshOnce(agentClient: fixture.client)
    expect(fixture.client.installCount) == 1
    expect(resumed.setupProgress) != .complete

    fixture.client.helperState = .running(active: fixture.identity)
    resumed.refreshOnce(agentClient: fixture.client)
    expect(resumed.setupProgress) == .complete
    expect(resumed.setupActionTitle) == nil
    expect(fixture.client.installCount) == 1
  }

  func testHelperFailurePersistsAcrossPollingAndRelaunchUntilExplicitRetry() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .registrationNeedsRepair(reason: "Not registered")
    fixture.client.installError = GuidedSetupTestError.registrationFailed
    let rejected = expectation(description: "Helper installation fails")
    fixture.client.installationFinished = rejected
    let first = fixture.makeState()
    first.beginSetup(agentClient: fixture.client)
    await fulfillment(of: [rejected], timeout: 1)
    await first.setupTask?.value
    let failure = try XCTUnwrap(first.lastError)
    first.refreshOnce(agentClient: fixture.client)

    let resumed = fixture.makeState()
    resumed.refreshOnce(agentClient: fixture.client)
    expect(resumed.setupProgress) == .failedHelper
    expect(resumed.lastError) == failure
    expect(resumed.setupActionTitle) == "Retry Setup"
    expect(fixture.client.installCount) == 1

    fixture.client.installError = nil
    fixture.client.installedState = .running(active: fixture.identity)
    let retried = expectation(description: "Explicit retry returns")
    fixture.client.installationFinished = retried
    resumed.performSetupAction(agentClient: fixture.client)
    await fulfillment(of: [retried], timeout: 1)
    await resumed.setupTask?.value
    resumed.refreshOnce(agentClient: fixture.client)
    expect(resumed.setupProgress) == .complete
    expect(fixture.client.installCount) == 2
  }

  func testUnknownHelperDoesNotClaimReadyOrClearRegistrationFailure() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    let state = fixture.makeState()
    state.beginSetup(agentClient: fixture.client)
    expect(state.step) == .checking
    expect(state.setupActionIsBusy) == false
    expect(fixture.client.installCount) == 0

    state.failSetup("Agent registration failed")
    fixture.client.helperState = .running(active: fixture.identity)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.lastError) == "Agent registration failed"
    expect(state.setupProgress) == .failed
  }

  func testExternalAgentDisableStopsPendingSetupWithoutReenablingIt() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()
    state.beginSetup(agentClient: fixture.client)
    fixture.service.status = .notRegistered

    let resumed = fixture.makeState()
    resumed.refreshOnce(agentClient: fixture.client)
    resumed.refreshOnce(agentClient: fixture.client)

    expect(resumed.setupProgress) == .failed
    expect(resumed.setupActionTitle) == "Retry Setup"
    expect(fixture.service.registerCount) == 1
    expect(fixture.client.installCount) == 0
  }

  func testUnregisterCancelsDurableIntent() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()
    state.beginSetup(agentClient: fixture.client)
    let unregistered = expectation(description: "Agent unregisters")
    fixture.service.unregistrationFinished = unregistered
    state.unregisterAgent()
    await fulfillment(of: [unregistered], timeout: 1)

    let resumed = fixture.makeState()
    resumed.refreshOnce(agentClient: fixture.client)
    expect(resumed.setupProgress) == .cancelled
    expect(resumed.setupActionTitle) == "Enable Background Control"
    expect(fixture.service.registerCount) == 1
    expect(fixture.client.installCount) == 0
  }

  func testAgentRegistrationErrorWithApprovalStatusFailsSetup() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.registrationStatus = .requiresApproval
    fixture.service.registerError = GuidedSetupTestError.registrationFailed
    let state = fixture.makeState()
    state.beginSetup(agentClient: fixture.client)

    expect(state.setupActionTitle) == "Retry Setup"
    expect(state.lastError) == "Registration was rejected"
    expect(state.setupProgress) == .failed
    expect(fixture.defaults.string(forKey: SharedConfigKeys.agentRegistrationFingerprint)) == nil
    expect(fixture.service.registerCount) == 1
  }

  func testRestartSerializesUnregisterBeforeRegister() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    let state = fixture.makeState()
    state.restartAgent()
    expect(fixture.service.operations) == ["unregister", "register"]
    expect(state.agentStatus) == .enabled
    expect(state.isRegisteringAgent) == false
  }

  func testAgentApprovalDenialWaitsForApprovalDuringSetupAndRestart() throws {
    for restarting in [false, true] {
      let fixture = try GuidedSetupFixture()
      defer { fixture.cleanUp() }
      fixture.service.registrationStatus = .requiresApproval
      fixture.service.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
      let state = fixture.makeState()

      if restarting {
        state.restartAgent()
      } else {
        state.beginSetup(agentClient: fixture.client)
      }

      expect(state.setupActionTitle) == "Open System Settings"
      expect(state.lastError) == nil
      expect(state.setupProgress.ownsLifecycle) == true
      expect(fixture.service.registerCount) == 1
    }
  }

  func testRestartRegistrationErrorWithApprovalStatusFailsSetup() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.registrationStatus = .requiresApproval
    fixture.service.registerError = GuidedSetupTestError.registrationFailed
    let state = fixture.makeState()

    state.restartAgent()

    expect(state.setupActionTitle) == "Retry Setup"
    expect(state.lastError) == "Registration was rejected"
    expect(state.setupProgress) == .failed
    expect(fixture.service.operations) == ["unregister", "register"]
  }

  func testImmediateEnableDisableEnableKeepsLastUserChoice() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()
    state.registerAgent()
    state.unregisterAgent()
    state.registerAgent()

    expect(fixture.service.operations) == ["register", "unregister", "register"]
    expect(state.agentStatus) == .enabled
    expect(state.setupProgress) == .connectingAgent
  }

  func testDirectRegistrationDistinguishesApprovalFromOtherFailures() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.registrationStatus = .requiresApproval
    fixture.service.registerError = GuidedSetupTestError.registrationFailed
    let state = fixture.makeState()

    state.registerAgent()

    expect(state.setupActionTitle) == "Retry Setup"
    expect(state.lastError) == "Registration was rejected"
    expect(fixture.defaults.string(forKey: SharedConfigKeys.agentRegistrationFingerprint)) == nil

    fixture.service.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
    state.registerAgent()

    expect(state.setupActionTitle) == "Open System Settings"
    expect(state.lastError) == nil
    expect(fixture.service.registerCount) == 2
  }

  func testRestartUnregisterDenialDoesNotBecomePendingApproval() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    let denial = NSError(domain: "SMAppServiceErrorDomain", code: 1)
    fixture.service.status = .requiresApproval
    fixture.service.unregisterError = denial
    let state = fixture.makeState()

    state.restartAgent()

    expect(state.setupProgress) == .failed
    expect(state.setupActionTitle) == "Retry Setup"
    expect(state.lastError) == denial.localizedDescription
    expect(fixture.service.operations) == ["unregister"]
    expect(fixture.service.registerCount) == 0
  }

}

// MARK: - Command outcomes

extension GuidedSetupTests {
  func testApprovalReadWaitsForReplacementConnectionWithoutHeartbeat() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.defaults.set("verifyingHelper", forKey: SharedConfigKeys.guidedSetupProgress)
    fixture.defaults.set("outdated-agent", forKey: SharedConfigKeys.agentExecutableHash)
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .approvalRequired
    fixture.client.refreshError = .registrationFailed
    let state = fixture.makeState()

    await state.refreshObservedSetup(agentClient: fixture.client)
    await state.refreshObservedSetup(agentClient: fixture.client)

    expect(fixture.service.operations) == ["unregister", "register"]
    expect(fixture.client.stateReadCount) == 0
    expect(state.setupProgress) == .verifyingHelper
    expect(state.lastError) == nil

    fixture.client.connectionGeneration += 1
    fixture.client.refreshError = nil
    fixture.client.refreshedState = .running(active: fixture.identity)
    await state.refreshObservedSetup(agentClient: fixture.client)

    expect(fixture.client.stateReadCount) == 1
    expect(state.setupProgress) == .complete
  }

  func testApprovalPollingReadsAgentAndFinishesWithoutRepair() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .approvalRequired
    fixture.client.refreshedState = .running(active: fixture.identity)
    let state = fixture.makeState()
    state.beginSetup(agentClient: fixture.client)

    await state.refreshObservedSetup(agentClient: fixture.client)

    expect(state.setupProgress) == .complete
    expect(fixture.client.stateReadCount) == 1
    expect(fixture.client.installCount) == 0
    expect(fixture.service.registerCount) == 0
  }

  func testApprovalPollingFailureStopsFurtherReadsUntilRetry() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .approvalRequired
    fixture.client.refreshError = .registrationFailed
    let state = fixture.makeState()
    state.beginSetup(agentClient: fixture.client)

    await state.refreshObservedSetup(agentClient: fixture.client)
    await state.refreshObservedSetup(agentClient: fixture.client)

    expect(state.setupProgress) == .failed
    expect(state.lastError) == "Registration was rejected"
    expect(fixture.client.stateReadCount) == 1
    expect(fixture.client.installCount) == 0
  }

  func testInstallAcknowledgementUsesFreshStateInsteadOfDelayedEvent() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .unavailable(reason: "Not registered")
    fixture.client.installedState = fixture.client.helperState
    fixture.client.refreshedState = .running(active: fixture.identity)
    let installed = expectation(description: "Installation reply arrives")
    fixture.client.installationFinished = installed
    let state = fixture.makeState()

    state.beginSetup(agentClient: fixture.client)
    await fulfillment(of: [installed], timeout: 1)
    await state.setupTask?.value

    expect(fixture.client.stateReadCount) == 1
    expect(state.setupProgress) == .complete
    expect(state.lastError) == nil
  }

  func testRejectedCommandWithFreshApprovalStateContinuesAfterApproval() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .registrationNeedsRepair(reason: "Not registered")
    fixture.client.installError = .registrationFailed
    fixture.client.refreshedState = .approvalRequired
    let installed = expectation(description: "Installation reply arrives")
    fixture.client.installationFinished = installed
    let state = fixture.makeState()

    state.beginSetup(agentClient: fixture.client)
    await fulfillment(of: [installed], timeout: 1)
    await state.setupTask?.value
    expect(state.setupActionTitle) == "Open System Settings"
    expect(state.lastError) == nil

    fixture.client.helperState = .running(active: fixture.identity)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.setupProgress) == .complete
    expect(fixture.client.installCount) == 1
  }

  func testFailedCurrentStateReadCannotAcceptCachedRunningHelper() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .running(active: fixture.identity)
    fixture.client.installedState = fixture.client.helperState
    fixture.client.refreshError = .registrationFailed
    let installed = expectation(description: "Repair reply arrives")
    fixture.client.installationFinished = installed
    let state = fixture.makeState()

    state.installOrRepairHelper(agentClient: fixture.client)
    await fulfillment(of: [installed], timeout: 1)
    await state.setupTask?.value
    state.refreshOnce(agentClient: fixture.client)

    expect(state.setupProgress) == .failed
    expect(state.lastError) == "Registration was rejected"
  }

  func testSettingsRepairSettlesPersistedGuidedFailure() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.defaults.set("failed", forKey: SharedConfigKeys.guidedSetupProgress)
    fixture.defaults.set("Previous failure", forKey: SharedConfigKeys.guidedSetupFailure)
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .registrationNeedsRepair(reason: "Not registered")
    fixture.client.installedState = .running(active: fixture.identity)
    let installed = expectation(description: "Repair reply arrives")
    fixture.client.installationFinished = installed
    let state = fixture.makeState()

    state.installOrRepairHelper(agentClient: fixture.client)
    await fulfillment(of: [installed], timeout: 1)
    await state.setupTask?.value

    expect(state.setupProgress) == .complete
    expect(state.lastError) == nil
    expect(state.setupProgress.ownsLifecycle) == false
  }

  func testDisableDuringPendingHelperCommandCannotResumeSetup() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .registrationNeedsRepair(reason: "Not registered")
    fixture.client.pauseInstallation = true
    fixture.client.installedState = .running(active: fixture.identity)
    let started = expectation(description: "Helper command starts")
    let finished = expectation(description: "Helper command finishes after cancellation")
    let unregistered = expectation(description: "Agent unregisters")
    fixture.client.installationStarted = started
    fixture.client.installationFinished = finished
    fixture.service.unregistrationFinished = unregistered
    let state = fixture.makeState()

    state.beginSetup(agentClient: fixture.client)
    state.beginSetup(agentClient: fixture.client)
    await fulfillment(of: [started], timeout: 1)
    expect(fixture.client.installCount) == 1
    state.unregisterAgent()
    await fulfillment(of: [unregistered], timeout: 1)
    fixture.client.finishInstallation()
    await fulfillment(of: [finished], timeout: 1)
    await state.setupTask?.value

    expect(state.setupProgress) == .cancelled
    expect(fixture.client.stateReadCount) == 0
    expect(fixture.service.status) == .notRegistered
  }

  func testRepeatedApprovalClicksOpenSettingsOnce() async throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.helperState = .approvalRequired
    let opened = expectation(description: "Helper approval settings open")
    fixture.client.settingsOpened = opened
    let state = fixture.makeState()
    state.beginSetup(agentClient: fixture.client)
    state.failSetup("Previous failure")

    state.openHelperApproval(agentClient: fixture.client)
    state.openHelperApproval(agentClient: fixture.client)
    await fulfillment(of: [opened], timeout: 1)
    await state.setupTask?.value

    expect(fixture.client.settingsOpenCount) == 1
    expect(fixture.client.installCount) == 0
    expect(state.lastError) == nil
    expect(state.setupProgress) == .verifyingHelper
  }

  func testInvalidSavedProgressFailsWithoutStartingRegistration() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.defaults.set("invalid", forKey: SharedConfigKeys.guidedSetupProgress)
    let state = fixture.makeState()
    state.refreshOnce(agentClient: fixture.client)

    expect(state.setupProgress) == .failed
    expect(state.setupActionTitle) == "Retry Setup"
    expect(state.lastError) != nil
    expect(fixture.service.registerCount) == 0
    expect(fixture.client.installCount) == 0
  }
}
