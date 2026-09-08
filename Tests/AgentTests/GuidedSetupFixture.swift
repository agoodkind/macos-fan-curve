//
//  GuidedSetupFixture.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-07.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import XCTest

// MARK: - GuidedSetupFixture

@MainActor
final class GuidedSetupFixture {
  let suiteName = "GuidedSetupTests.\(UUID().uuidString)"
  let defaults: UserDefaults
  let service = GuidedBackgroundAgentService()
  let client = GuidedAgentClient()
  let identity = SystemHelperIdentity(
    version: "1",
    build: "1",
    commit: "test",
    executableHash: "bundled-helper",
    protocolVersion: 1
  )

  init() throws {
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  func makeState() -> InstallationState {
    let bundledHash = { "bundled-agent" }
    let legacyRepair = {
      LegacyLaunchAgentRepairResult(
        repaired: false,
        sourcePath: "",
        backupPath: nil,
        reason: "isolated-test"
      )
    }
    return InstallationState(
      backgroundAgentService: service,
      setupDefaults: defaults,
      legacyLaunchAgentRepair: legacyRepair,
      bundledAgentHash: bundledHash
    )
  }

  func cleanUp() {
    defaults.removePersistentDomain(forName: suiteName)
  }
}

// MARK: - GuidedSetupTestError

enum GuidedSetupTestError: LocalizedError {
  case registrationFailed

  var errorDescription: String? { "Registration was rejected" }
}

// MARK: - GuidedBackgroundAgentService

final class GuidedBackgroundAgentService: BackgroundAgentServiceManaging {
  var status: ManagedServiceStatus = .notFound
  var registrationStatus: ManagedServiceStatus = .enabled
  var registerError: GuidedSetupTestError?
  var registerCount = 0
  var settingsOpenCount = 0
  var operations: [String] = []
  var unregistrationFinished: XCTestExpectation?

  func register() throws {
    operations.append("register")
    registerCount += 1
    status = registrationStatus
    if let registerError { throw registerError }
  }

  func unregister() {
    operations.append("unregister")
    status = .notRegistered
    unregistrationFinished?.fulfill()
  }

  func openSystemSettings() {
    settingsOpenCount += 1
  }
}

// MARK: - GuidedAgentClient

@MainActor
final class GuidedAgentClient: InstallationAgentClient {
  var connectionState: FanCurveAgentConnectionState = .disconnected
  var connectionGeneration: UInt64 = 0
  var helperState: SystemHelperRuntimeState = .checking
  var installedState: SystemHelperRuntimeState = .approvalRequired
  var installError: GuidedSetupTestError?
  var installCount = 0
  var installationFinished: XCTestExpectation?
  var refreshedState: SystemHelperRuntimeState?
  var refreshError: GuidedSetupTestError?
  var stateReadCount = 0
  var pauseInstallation = false
  var installationStarted: XCTestExpectation?
  var settingsOpened: XCTestExpectation?
  var settingsOpenCount = 0
  private var installationContinuation: CheckedContinuation<Void, Never>?

  var runtimeState: RuntimeState {
    .fromSharedDefaultsSnapshot(nil, systemHelper: helperState)
  }

  var helperReachable: Bool { helperState.permitsFanControl }

  func installOrRepairHelper() async throws {
    defer { installationFinished?.fulfill() }
    installCount += 1
    if pauseInstallation {
      await withCheckedContinuation { continuation in
        installationContinuation = continuation
        installationStarted?.fulfill()
      }
    }
    if let installError { throw installError }
    helperState = installedState
  }

  func refreshCurrentState() throws {
    stateReadCount += 1
    if let refreshError { throw refreshError }
    if let refreshedState { helperState = refreshedState }
  }

  func finishInstallation() {
    installationContinuation?.resume()
    installationContinuation = nil
  }

  func openSystemSettings() {
    settingsOpenCount += 1
    settingsOpened?.fulfill()
  }
}
