//
//  SystemHelperLifecycleReconciler.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

let systemHelperLifecycleLog = AppLog.make(
  category: "SystemHelperLifecycleReconciler"
)

// MARK: - SystemHelperLifecycleReconciler

actor SystemHelperLifecycleReconciler {
  private let artifactValidator: any SystemHelperArtifactValidating
  private let bundledExecutableURL: URL
  let fanHardware: any FanHardware
  let fanResetDeadline: TimeInterval
  let lifecycleGate: any SystemHelperControllerLifecycleGating
  private let publishState: @Sendable (SystemHelperRuntimeState) -> Void
  let registerRetryDelay: Duration
  let replacementJournal: any SystemHelperReplacementJournaling
  let service: any HelperServiceManaging
  let verificationPollInterval: Duration
  let verificationTimeout: Duration
  private var activeReconciliation: ActiveSystemHelperReconciliation?

  init(
    fanHardware: any FanHardware,
    service: any HelperServiceManaging,
    lifecycleGate: any SystemHelperControllerLifecycleGating,
    bundledExecutableURL: URL,
    artifactValidator: any SystemHelperArtifactValidating =
      SystemHelperArtifactValidator(),
    fanResetDeadline: TimeInterval =
      SystemHelperFanResetSequencer.deadlineSeconds,
    verificationTimeout: Duration =
      SystemHelperReconcileTiming.verificationTimeout,
    verificationPollInterval: Duration =
      SystemHelperReconcileTiming.verificationPollInterval,
    registerRetryDelay: Duration =
      SystemHelperReconcileTiming.registerRetryDelay,
    replacementJournal: any SystemHelperReplacementJournaling =
      SystemHelperReplacementJournal(),
    publishState: @escaping @Sendable (SystemHelperRuntimeState) -> Void
  ) {
    self.fanHardware = fanHardware
    self.service = service
    self.lifecycleGate = lifecycleGate
    self.bundledExecutableURL = bundledExecutableURL
    self.artifactValidator = artifactValidator
    self.fanResetDeadline = fanResetDeadline
    self.verificationTimeout = verificationTimeout
    self.verificationPollInterval = verificationPollInterval
    self.registerRetryDelay = registerRetryDelay
    self.replacementJournal = replacementJournal
    self.publishState = publishState
  }
}

// MARK: - SystemHelperLifecycleReconciler

extension SystemHelperLifecycleReconciler {
  func reconcile(
    trigger: SystemHelperReconcileTrigger
  ) async -> SystemHelperRuntimeState {
    let waiterID = UUID()
    let reconciliation: ActiveSystemHelperReconciliation
    let joinedExisting: Bool
    if var activeReconciliation {
      systemHelperLifecycleLog.notice(
        "system_helper.reconcile.joined reason=in_flight recovery=await-current"
      )
      activeReconciliation.waiterIDs.insert(waiterID)
      self.activeReconciliation = activeReconciliation
      reconciliation = activeReconciliation
      joinedExisting = true
    } else {
      let task = Task {
        await performReconciliation(trigger: trigger)
      }
      reconciliation = ActiveSystemHelperReconciliation(
        id: UUID(),
        task: task,
        waiterIDs: [waiterID]
      )
      activeReconciliation = reconciliation
      joinedExisting = false
    }

    let result = await withTaskCancellationHandler {
      await reconciliation.task.value
    } onCancel: {
      Task {
        await self.cancelWaiter(
          waiterID,
          reconciliationID: reconciliation.id
        )
      }
    }
    if activeReconciliation?.id == reconciliation.id {
      activeReconciliation = nil
    }
    if joinedExisting,
      trigger == .forcedRepair,
      !result.registrationMutated,
      !Task.isCancelled
    {
      systemHelperLifecycleLog.notice(
        "system_helper.reconcile.queued operation=forced_repair reason=prior-check recovery=run"
      )
      return await reconcile(trigger: .forcedRepair)
    }
    return result.state
  }

  private func cancelWaiter(
    _ waiterID: UUID,
    reconciliationID: UUID
  ) {
    guard var activeReconciliation,
      activeReconciliation.id == reconciliationID
    else { return }
    activeReconciliation.waiterIDs.remove(waiterID)
    guard activeReconciliation.waiterIDs.isEmpty else {
      self.activeReconciliation = activeReconciliation
      return
    }
    self.activeReconciliation = nil
    activeReconciliation.task.cancel()
    systemHelperLifecycleLog.notice(
      "system_helper.reconcile.cancelled reason=no_waiters recovery=stop-work"
    )
  }

  private func performReconciliation(
    trigger: SystemHelperReconcileTrigger
  ) async -> SystemHelperReconcileResult {
    lifecycleGate.pause()
    publish(.checking)
    systemHelperLifecycleLog.notice(
      "system_helper.reconcile.started operation=\(trigger.operation.rawValue, privacy: .public)"
    )

    let serviceStatus = service.status
    if let inactiveState = SystemHelperClassifier.classifyInactive(
      serviceStatus: serviceStatus
    ),
      !shouldResumeRegistration(trigger: trigger, serviceStatus: serviceStatus)
    {
      publish(inactiveState)
      return result(inactiveState)
    }

    let bundledIdentity: SystemHelperIdentity
    do {
      bundledIdentity = try validateBundledArtifact()
    } catch {
      return result(
        fail(
          context: SystemHelperFailureContext(
            operation: trigger.operation,
            activeIdentity: nil,
            bundledIdentity: nil
          ),
          stage: .preflight,
          reason: error.localizedDescription,
          recovery: "Reinstall Fan Curve and retry"
        )
      )
    }

    if Task.isCancelled {
      return cancelled(
        context: SystemHelperFailureContext(
          operation: trigger.operation,
          activeIdentity: nil,
          bundledIdentity: bundledIdentity
        ),
        stage: .preflight
      )
    }

    return await reconcileValidatedHelper(
      trigger: trigger,
      serviceStatus: serviceStatus,
      bundledIdentity: bundledIdentity
    )
  }

  /// An unregistered helper normally requires an explicit user repair, but a
  /// pending replacement journal entry means this reconciler removed the old
  /// helper itself and still owes the machine a registered replacement.
  func shouldResumeRegistration(
    trigger: SystemHelperReconcileTrigger,
    serviceStatus: ManagedServiceStatus
  ) -> Bool {
    guard serviceStatus == .notRegistered else { return false }
    return trigger == .forcedRepair || replacementJournal.hasPendingReplacement
  }

  func publish(_ state: SystemHelperRuntimeState) {
    publishState(state)
  }

  func validateBundledArtifact() throws -> SystemHelperIdentity {
    try artifactValidator.validate(at: bundledExecutableURL)
  }

  func waitForVerificationPoll() async -> Bool {
    let clock = ContinuousClock()
    do {
      try await clock.sleep(for: verificationPollInterval)
      return true
    } catch {
      systemHelperLifecycleLog.notice(
        "system_helper.reconnect.wait_cancelled recovery=stop-polling"
      )
      return false
    }
  }

  func result(
    _ state: SystemHelperRuntimeState,
    registrationMutated: Bool = false
  ) -> SystemHelperReconcileResult {
    SystemHelperReconcileResult(
      state: state,
      registrationMutated: registrationMutated
    )
  }

  func cancelled(
    context: SystemHelperFailureContext,
    stage: SystemHelperFailureStage
  ) -> SystemHelperReconcileResult {
    result(
      fail(
        context: context,
        stage: stage,
        reason: "System Helper reconciliation was cancelled",
        recovery: "Retry System Helper repair"
      )
    )
  }

  func fail(
    context: SystemHelperFailureContext,
    stage: SystemHelperFailureStage,
    reason: String,
    recovery: String
  ) -> SystemHelperRuntimeState {
    lifecycleGate.pause()
    systemHelperLifecycleLog.error(
      "system_helper.reconcile.failed operation=\(context.operation.rawValue, privacy: .public) stage=\(stage.rawValue, privacy: .public) reason=\(reason, privacy: .public) recovery=\(recovery, privacy: .public)"
    )
    let state = SystemHelperRuntimeState.repairFailed(
      active: context.activeIdentity,
      bundled: context.bundledIdentity,
      failure: SystemHelperFailure(
        operation: context.operation,
        stage: stage,
        reason: reason,
        recovery: recovery
      )
    )
    publish(state)
    return state
  }
}
