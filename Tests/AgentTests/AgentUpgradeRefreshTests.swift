//
//  AgentUpgradeRefreshTests.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@MainActor
final class AgentUpgradeRefreshTests: XCTestCase {
  func testConnectedOutdatedAgentRefreshesRegistration() throws {
    let service = RecordingBackgroundAgentService()
    let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let bundledHash = { "bundled-agent" }
    let state = InstallationState(
      backgroundAgentService: service,
      setupDefaults: defaults,
      bundledAgentHash: bundledHash
    )
    let context = AgentRefreshContext(
      agentConnected: true,
      agentUnresponsive: false,
      runningHash: "outdated-agent",
      snapshotSchemaVersion: AgentSnapshot.currentSchemaVersion,
      storedFingerprint: "old-registration",
      expectedFingerprint: "new-registration",
      defaults: defaults
    )

    state.refreshAgentIfNeeded(context)
    state.refreshAgentIfNeeded(context)

    expect(service.unregisterCount) == 1
    expect(service.registerCount) == 1
    expect(service.status) == .enabled
  }

  func testUnresponsiveAgentWithMatchingHashRefreshesRegistration() throws {
    let service = RecordingBackgroundAgentService()
    let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let bundledHash = { "bundled-agent" }
    let state = InstallationState(
      backgroundAgentService: service,
      setupDefaults: defaults,
      bundledAgentHash: bundledHash
    )
    let context = AgentRefreshContext(
      agentConnected: false,
      agentUnresponsive: true,
      runningHash: "bundled-agent",
      snapshotSchemaVersion: nil,
      storedFingerprint: "new-registration",
      expectedFingerprint: "new-registration",
      defaults: defaults
    )

    state.refreshAgentIfNeeded(context)

    expect(service.unregisterCount) == 1
    expect(service.registerCount) == 1
    expect(service.status) == .enabled
  }

  func testConnectedAgentWithoutHeartbeatHashKeepsRegistration() throws {
    let service = RecordingBackgroundAgentService()
    let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let bundledHash = { "bundled-agent" }
    let state = InstallationState(
      backgroundAgentService: service,
      setupDefaults: defaults,
      bundledAgentHash: bundledHash
    )
    let context = AgentRefreshContext(
      agentConnected: true,
      agentUnresponsive: false,
      runningHash: "",
      snapshotSchemaVersion: nil,
      storedFingerprint: "new-registration",
      expectedFingerprint: "new-registration",
      defaults: defaults
    )

    state.refreshAgentIfNeeded(context)

    expect(service.unregisterCount) == 0
    expect(service.registerCount) == 0
  }

  func testDisconnectedAgentInsideGraceKeepsRegistration() throws {
    let service = RecordingBackgroundAgentService()
    let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let bundledHash = { "bundled-agent" }
    let state = InstallationState(
      backgroundAgentService: service,
      setupDefaults: defaults,
      bundledAgentHash: bundledHash
    )
    let context = AgentRefreshContext(
      agentConnected: false,
      agentUnresponsive: false,
      runningHash: "bundled-agent",
      snapshotSchemaVersion: nil,
      storedFingerprint: "new-registration",
      expectedFingerprint: "new-registration",
      defaults: defaults
    )

    state.refreshAgentIfNeeded(context)

    expect(service.unregisterCount) == 0
    expect(service.registerCount) == 0
  }

  func testPendingSetupRefreshesConfirmedOutdatedAgentAfterRelaunch() throws {
    let pendingStages: [GuidedSetupProgress] = [
      .connectingAgent, .verifyingHelper, .failedHelper,
    ]
    for progress in pendingStages {
      let service = RecordingBackgroundAgentService()
      let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
      defer { defaults.removePersistentDomain(forName: suiteName) }
      defaults.set(progress.rawValue, forKey: SharedConfigKeys.guidedSetupProgress)
      let bundledHash = { "bundled-agent" }
      let state = InstallationState(
        backgroundAgentService: service,
        setupDefaults: defaults,
        bundledAgentHash: bundledHash
      )
      let context = AgentRefreshContext(
        agentConnected: true,
        agentUnresponsive: false,
        runningHash: "outdated-agent",
        snapshotSchemaVersion: AgentSnapshot.currentSchemaVersion,
        storedFingerprint: "old-registration",
        expectedFingerprint: "new-registration",
        defaults: defaults
      )

      state.refreshAgentIfNeeded(context)
      state.refreshAgentIfNeeded(context)

      expect(service.unregisterCount) == 1
      expect(service.registerCount) == 1
      expect(service.status) == .enabled
      expect(state.setupProgress.ownsLifecycle) == true
    }
  }

  func testPendingSetupDoesNotRefreshAgentDuringHelperMutationOrAfterCancellation() throws {
    let stages: [GuidedSetupProgress] = [.installingHelper, .cancelled]
    for progress in stages {
      let service = RecordingBackgroundAgentService()
      let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
      defer { defaults.removePersistentDomain(forName: suiteName) }
      defaults.set(progress.rawValue, forKey: SharedConfigKeys.guidedSetupProgress)
      let bundledHash = { "bundled-agent" }
      let state = InstallationState(
        backgroundAgentService: service,
        setupDefaults: defaults,
        bundledAgentHash: bundledHash
      )
      state.isRegisteringHelper = progress == .installingHelper
      let context = AgentRefreshContext(
        agentConnected: true,
        agentUnresponsive: false,
        runningHash: "outdated-agent",
        snapshotSchemaVersion: AgentSnapshot.currentSchemaVersion,
        storedFingerprint: "old-registration",
        expectedFingerprint: "new-registration",
        defaults: defaults
      )

      state.refreshAgentIfNeeded(context)

      expect(service.unregisterCount) == 0
      expect(service.registerCount) == 0
    }
  }
}

// MARK: - Pending upgrade failures

extension AgentUpgradeRefreshTests {
  func testFailedPendingUpgradeDoesNotAutomaticallyRetry() throws {
    let service = RecordingBackgroundAgentService()
    service.unregisterError = NSError(domain: "GuidedUpgradeTests", code: 1)
    let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("verifyingHelper", forKey: SharedConfigKeys.guidedSetupProgress)
    let bundledHash = { "bundled-agent" }
    let state = InstallationState(
      backgroundAgentService: service,
      setupDefaults: defaults,
      bundledAgentHash: bundledHash
    )
    let context = AgentRefreshContext(
      agentConnected: true,
      agentUnresponsive: false,
      runningHash: "outdated-agent",
      snapshotSchemaVersion: AgentSnapshot.currentSchemaVersion,
      storedFingerprint: "old-registration",
      expectedFingerprint: "new-registration",
      defaults: defaults
    )

    state.refreshAgentIfNeeded(context)
    state.lastAutoRefreshAttemptDate = .distantPast
    state.refreshAgentIfNeeded(context)

    expect(state.setupProgress) == .failed
    expect(state.lastError) != nil
    expect(service.unregisterCount) == 1
    expect(service.registerCount) == 0
    expect(service.status) == .enabled
  }
}

// MARK: - RecordingBackgroundAgentService

private final class RecordingBackgroundAgentService: BackgroundAgentServiceManaging {
  private(set) var status: ManagedServiceStatus = .enabled
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0
  var unregisterError: NSError?

  func register() {
    registerCount += 1
    status = .enabled
  }

  func unregister() throws {
    unregisterCount += 1
    if let unregisterError { throw unregisterError }
    status = .notRegistered
  }

  func openSystemSettings() {
    XCTFail("Agent refresh must not open System Settings")
  }
}
