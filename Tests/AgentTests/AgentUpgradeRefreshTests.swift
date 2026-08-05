//
//  AgentUpgradeRefreshTests.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@MainActor
final class AgentUpgradeRefreshTests: XCTestCase {
  func testConnectedOutdatedAgentRefreshesRegistration() throws {
    let service = RecordingBackgroundAgentService()
    let state = InstallationState(backgroundAgentService: service) {
      "bundled-agent"
    }
    let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
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
    let state = InstallationState(backgroundAgentService: service) {
      "bundled-agent"
    }
    let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
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
    let state = InstallationState(backgroundAgentService: service) {
      "bundled-agent"
    }
    let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
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
    let state = InstallationState(backgroundAgentService: service) {
      "bundled-agent"
    }
    let suiteName = "AgentUpgradeRefreshTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
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
}

// MARK: - RecordingBackgroundAgentService

private final class RecordingBackgroundAgentService: BackgroundAgentServiceManaging {
  private(set) var status: ManagedServiceStatus = .enabled
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  func register() {
    registerCount += 1
    status = .enabled
  }

  func unregister() {
    unregisterCount += 1
    status = .notRegistered
  }

  func openSystemSettings() {
    XCTFail("Agent refresh must not open System Settings")
  }
}
