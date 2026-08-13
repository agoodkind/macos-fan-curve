//
//  ReconcilerHarness.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import XCTest

// MARK: - ReconcilerHarness

final class ReconcilerHarness: @unchecked Sendable {
  private static let defaultVerificationPollMilliseconds: Int64 = 10
  private static let defaultVerificationTimeoutMilliseconds: Int64 = 200
  private static let fanResetDeadlineSeconds: TimeInterval = 0.05

  enum ActiveFixture {
    case bundled
    case connectionInvalidated
    case legacy
    case outdated
    case unreachable
  }

  enum OperationBehavior: Equatable {
    case fail
    case requiresApproval
    case succeed
  }

  let bundledIdentity: SystemHelperIdentity
  let bundledExecutableURL: URL
  let gate = RecordingLifecycleGate()
  let hardware: StatefulFanHardware
  let outdatedIdentity: SystemHelperIdentity
  let recorder = SystemHelperStateRecorder()
  let replacementJournal = InMemorySystemHelperReplacementJournal()
  let service: StatefulHelperService

  private let reconciler: SystemHelperLifecycleReconciler

  init(
    testCase: XCTestCase,
    active: ActiveFixture,
    serviceStatus: ManagedServiceStatus = .enabled,
    artifactValidator: any SystemHelperArtifactValidating =
      HashingArtifactValidator(),
    resetBehavior: OperationBehavior = .succeed,
    unregisterBehavior: OperationBehavior = .succeed,
    registerBehavior: OperationBehavior = .succeed,
    postRegisterIdentity: ActiveFixture = .bundled,
    identityDelay: Duration = .zero,
    identityRequestStarted: XCTestExpectation? = nil,
    additionalVerificationStarted: XCTestExpectation? = nil,
    legacyProbeStarted: XCTestExpectation? = nil,
    legacyProbeCancelled: XCTestExpectation? = nil,
    verificationStarted: XCTestExpectation? = nil,
    verificationGate: IdentityVerificationGate? = nil,
    unregisterStarted: XCTestExpectation? = nil,
    unregisterCompleted: XCTestExpectation? = nil,
    mutationDelay: Duration = .zero,
    verificationTimeout: Duration = .milliseconds(
      ReconcilerHarness.defaultVerificationTimeoutMilliseconds
    ),
    verificationPollInterval: Duration = .milliseconds(
      ReconcilerHarness.defaultVerificationPollMilliseconds
    )
  ) throws {
    let artifactFixture = try SystemHelperArtifactFixture.make(testCase: testCase)
    let executableURL = artifactFixture.executableURL
    bundledExecutableURL = executableURL
    bundledIdentity = artifactFixture.identity
    outdatedIdentity = SystemHelperIdentity(
      version: "1.0.0",
      build: "10",
      commit: "active-commit",
      executableHash: "outdated-hash",
      protocolVersion: 1
    )
    hardware = StatefulFanHardware(
      identity: Self.identityObservation(
        active,
        bundled: bundledIdentity,
        outdated: outdatedIdentity
      ),
      identityDelay: identityDelay,
      identityRequestStarted: identityRequestStarted,
      additionalVerificationStarted: additionalVerificationStarted,
      legacyProbeStarted: legacyProbeStarted,
      legacyProbeCancelled: legacyProbeCancelled,
      verificationStarted: verificationStarted,
      verificationGate: verificationGate,
      resetBehavior: resetBehavior
    )
    service = StatefulHelperService(
      status: serviceStatus,
      registrationGeneration: serviceStatus == .notRegistered ? 0 : 1,
      unregisterFails: unregisterBehavior == .fail,
      registerBehavior: registerBehavior,
      unregisterStarted: unregisterStarted,
      unregisterCompleted: unregisterCompleted,
      mutationDelay: mutationDelay
    )
    let installedObservation = Self.identityObservation(
      postRegisterIdentity,
      bundled: bundledIdentity,
      outdated: outdatedIdentity
    )
    service.setOnRegistered { [hardware] in
      hardware.setIdentity(installedObservation)
    }
    reconciler = SystemHelperLifecycleReconciler(
      fanHardware: hardware,
      service: service,
      lifecycleGate: gate,
      bundledExecutableURL: executableURL,
      artifactValidator: artifactValidator,
      fanResetDeadline: Self.fanResetDeadlineSeconds,
      verificationTimeout: verificationTimeout,
      verificationPollInterval: verificationPollInterval,
      registerRetryDelay: .milliseconds(1),
      replacementJournal: replacementJournal
    ) { [recorder] state in
      recorder.record(state)
    }
  }

  func reconcile(
    _ trigger: SystemHelperReconcileTrigger
  ) async -> SystemHelperRuntimeState {
    await reconciler.reconcile(trigger: trigger)
  }

  private static func identityObservation(
    _ fixture: ActiveFixture,
    bundled: SystemHelperIdentity,
    outdated: SystemHelperIdentity
  ) -> StatefulFanHardware.IdentityBehavior {
    switch fixture {
    case .bundled:
      return .identity(bundled)
    case .connectionInvalidated:
      return .connectionInvalidated
    case .legacy:
      return .legacy
    case .outdated:
      return .identity(outdated)
    case .unreachable:
      return .unreachable
    }
  }
}

// MARK: - InMemorySystemHelperReplacementJournal

final class InMemorySystemHelperReplacementJournal:
  SystemHelperReplacementJournaling,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var pending = false

  var hasPendingReplacement: Bool { lock.withLock { pending } }

  func recordPendingReplacement() { lock.withLock { pending = true } }
  func clearPendingReplacement() { lock.withLock { pending = false } }
}

// MARK: - RecordingLifecycleGate

final class RecordingLifecycleGate:
  SystemHelperControllerLifecycleGating,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var paused = true

  var isPaused: Bool { lock.withLock { paused } }

  func pause() { lock.withLock { paused = true } }
  func resume() { lock.withLock { paused = false } }
}

// MARK: - SystemHelperStateRecorder

final class SystemHelperStateRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storedStates: [SystemHelperRuntimeState] = []

  var states: [SystemHelperRuntimeState] { lock.withLock { storedStates } }

  func record(_ state: SystemHelperRuntimeState) {
    lock.withLock { storedStates.append(state) }
  }
}
