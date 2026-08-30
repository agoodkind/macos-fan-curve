//
//  SystemHelperLifecycleReconciler+Replacement.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - SystemHelperLifecycleReconciler

extension SystemHelperLifecycleReconciler {
  func replaceHelper(
    context: SystemHelperFailureContext,
    bundledIdentity: SystemHelperIdentity
  ) async -> SystemHelperReconcileResult {
    systemHelperLifecycleLog.notice(
      "system_helper.replace.started operation=\(context.operation.rawValue, privacy: .public)"
    )
    if Task.isCancelled {
      return cancelled(context: context, stage: .fanReset)
    }
    if let resetFailure = await resetFans(context: context) {
      return result(resetFailure)
    }
    if Task.isCancelled {
      return cancelled(context: context, stage: .unregister)
    }
    replacementJournal.recordPendingReplacement()
    systemHelperLifecycleLog.notice(
      "system_helper.replace.journal.recorded operation=\(context.operation.rawValue, privacy: .public)"
    )
    let inactiveContext = SystemHelperFailureContext(
      operation: context.operation,
      activeIdentity: nil,
      bundledIdentity: bundledIdentity
    )
    let recovery = Task { () -> SystemHelperReconcileResult? in
      if let unregisterFailure = await unregisterHelper(context: context) {
        return result(unregisterFailure)
      }
      return await registerService(
        context: inactiveContext,
        bundledIdentity: bundledIdentity,
        recoveringAfterUnregister: true
      )
    }
    if let recoveryFailure = await recovery.value {
      return recoveryFailure
    }
    return await finishRegistration(
      context: inactiveContext,
      bundledIdentity: bundledIdentity
    )
  }

  func registerMissingHelper(
    context: SystemHelperFailureContext,
    bundledIdentity: SystemHelperIdentity
  ) async -> SystemHelperReconcileResult {
    systemHelperLifecycleLog.notice(
      "system_helper.install.started operation=\(context.operation.rawValue, privacy: .public)"
    )
    if Task.isCancelled {
      return cancelled(context: context, stage: .register)
    }
    fanHardware.shutdown()
    return await registerHelper(
      context: context,
      bundledIdentity: bundledIdentity,
      recoveringAfterUnregister: false
    )
  }

  func resetFans(
    context: SystemHelperFailureContext
  ) async -> SystemHelperRuntimeState? {
    let resetOutcome = await SystemHelperFanResetSequencer.resetWithinDeadline(
      deadline: fanResetDeadline
    ) { [fanHardware] in
      try await fanHardware.resetAllDiscoveredFansToAuto()
    }
    switch resetOutcome {
    case .cancelled:
      return fail(
        context: context,
        stage: .fanReset,
        reason: "Fan reset was cancelled",
        recovery: "Retry System Helper repair"
      )
    case .completed:
      return nil
    case .failed(let reason):
      return fail(
        context: context,
        stage: .fanReset,
        reason: reason,
        recovery: "Retry after fan communication recovers"
      )
    case .timedOut:
      return fail(
        context: context,
        stage: .fanReset,
        reason: "Fan reset timed out",
        recovery: "Retry after fan communication recovers"
      )
    }
  }

  private func unregisterHelper(
    context: SystemHelperFailureContext
  ) async -> SystemHelperRuntimeState? {
    systemHelperLifecycleLog.notice(
      "system_helper.unregister.started operation=\(context.operation.rawValue, privacy: .public)"
    )
    fanHardware.shutdown()
    do {
      try await service.unregister()
      systemHelperLifecycleLog.notice(
        "system_helper.unregister.finished operation=\(context.operation.rawValue, privacy: .public)"
      )
      return nil
    } catch {
      return fail(
        context: context,
        stage: .unregister,
        reason: error.localizedDescription,
        recovery: "Retry System Helper repair"
      )
    }
  }

  private func registerHelper(
    context: SystemHelperFailureContext,
    bundledIdentity: SystemHelperIdentity,
    recoveringAfterUnregister: Bool
  ) async -> SystemHelperReconcileResult {
    if let registrationFailure = await registerService(
      context: context,
      bundledIdentity: bundledIdentity,
      recoveringAfterUnregister: recoveringAfterUnregister
    ) {
      return registrationFailure
    }
    return await finishRegistration(
      context: context,
      bundledIdentity: bundledIdentity
    )
  }

  private func registerService(
    context: SystemHelperFailureContext,
    bundledIdentity: SystemHelperIdentity,
    recoveringAfterUnregister: Bool
  ) async -> SystemHelperReconcileResult? {
    systemHelperLifecycleLog.notice(
      "system_helper.register.started operation=\(context.operation.rawValue, privacy: .public) recovery_after_unregister=\(recoveringAfterUnregister, privacy: .public)"
    )
    if let artifactFailure = revalidateRegistrationArtifact(
      context: context,
      bundledIdentity: bundledIdentity,
      registrationMutated: recoveringAfterUnregister
    ) {
      return artifactFailure
    }
    let attempts =
      recoveringAfterUnregister
      ? SystemHelperReconcileTiming.registerRetryAttempts
      : 1
    var lastFailureDescription = ""
    var lastFailureReason = ManagedServiceFailureReason.other
    for attempt in 1...attempts {
      do {
        try await service.register()
        systemHelperLifecycleLog.notice(
          "system_helper.register.finished operation=\(context.operation.rawValue, privacy: .public)"
        )
        return nil
      } catch {
        if let approvalResult = await registrationApprovalResult(
          error: error,
          context: context,
          bundledIdentity: bundledIdentity
        ) {
          return approvalResult
        }
        lastFailureReason = ManagedServiceFailureReason(error: error)
        lastFailureDescription = error.localizedDescription
        systemHelperLifecycleLog.notice(
          "system_helper.register.attempt_failed operation=\(context.operation.rawValue, privacy: .public) attempt=\(attempt, privacy: .public) of=\(attempts, privacy: .public) error=\(error.localizedDescription, privacy: .public) reason=\(lastFailureReason.rawValue, privacy: .public) recovery=retry-after-delay"
        )
      }
      if attempt < attempts, !Task.isCancelled {
        guard await waitForRegistrationRetry() else { break }
      }
    }
    if let approvalResult = exhaustedRegistrationApprovalResult(
      context: context,
      failureReason: lastFailureReason,
      recoveringAfterUnregister: recoveringAfterUnregister
    ) {
      return approvalResult
    }
    return result(
      fail(
        context: context,
        stage: .register,
        reason: lastFailureDescription,
        recovery: "Retry System Helper repair"
      ),
      registrationMutated: recoveringAfterUnregister
    )
  }

  private func waitForRegistrationRetry() async -> Bool {
    do {
      try await ContinuousClock().sleep(for: registerRetryDelay)
      return true
    } catch {
      systemHelperLifecycleLog.notice(
        "system_helper.register.retry_wait_cancelled recovery=stop-retrying"
      )
      return false
    }
  }

  private func registrationApprovalResult(
    error: Error,
    context: SystemHelperFailureContext,
    bundledIdentity: SystemHelperIdentity
  ) async -> SystemHelperReconcileResult? {
    guard service.status == .requiresApproval else { return nil }
    systemHelperLifecycleLog.notice(
      "system_helper.register.requires_approval operation=\(context.operation.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=await-user-approval"
    )
    return await finishRegistration(
      context: context,
      bundledIdentity: bundledIdentity
    )
  }

  private func exhaustedRegistrationApprovalResult(
    context: SystemHelperFailureContext,
    failureReason: ManagedServiceFailureReason,
    recoveringAfterUnregister: Bool
  ) -> SystemHelperReconcileResult? {
    guard !Task.isCancelled, failureReason == .operationNotPermitted else { return nil }
    systemHelperLifecycleLog.notice(
      "system_helper.register.denied_by_login_items operation=\(context.operation.rawValue, privacy: .public) reason=operation-not-permitted-after-retries recovery=open-system-settings"
    )
    publish(.approvalRequired)
    return result(
      .approvalRequired,
      registrationMutated: recoveringAfterUnregister
    )
  }

  private func revalidateRegistrationArtifact(
    context: SystemHelperFailureContext,
    bundledIdentity: SystemHelperIdentity,
    registrationMutated: Bool
  ) -> SystemHelperReconcileResult? {
    let currentIdentity: SystemHelperIdentity
    do {
      currentIdentity = try validateBundledArtifact()
    } catch {
      return result(
        fail(
          context: context,
          stage: .register,
          reason:
            "Bundled System Helper failed validation immediately before registration: \(error.localizedDescription)",
          recovery: "Reinstall Fan Curve and retry"
        ),
        registrationMutated: registrationMutated
      )
    }
    guard currentIdentity == bundledIdentity else {
      return result(
        fail(
          context: context,
          stage: .register,
          reason: "Bundled System Helper changed after preflight",
          recovery: "Reinstall Fan Curve and retry"
        ),
        registrationMutated: registrationMutated
      )
    }
    return nil
  }

  private func finishRegistration(
    context: SystemHelperFailureContext,
    bundledIdentity: SystemHelperIdentity
  ) async -> SystemHelperReconcileResult {
    replacementJournal.clearPendingReplacement()
    systemHelperLifecycleLog.notice(
      "system_helper.replace.journal.cleared operation=\(context.operation.rawValue, privacy: .public)"
    )
    if service.status == .requiresApproval {
      publish(.approvalRequired)
      return result(.approvalRequired, registrationMutated: true)
    }
    guard service.status == .enabled else {
      return result(
        fail(
          context: context,
          stage: .register,
          reason: "System Helper registration did not become enabled",
          recovery: "Approve the System Helper or retry repair"
        ),
        registrationMutated: true
      )
    }
    let state = await verifyReplacement(
      context: context,
      bundledIdentity: bundledIdentity
    )
    return result(state, registrationMutated: true)
  }

  private func verifyReplacement(
    context: SystemHelperFailureContext,
    bundledIdentity: SystemHelperIdentity
  ) async -> SystemHelperRuntimeState {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: verificationTimeout)
    while clock.now < deadline {
      if Task.isCancelled {
        return verificationCancelled(context: context)
      }
      do {
        let activeIdentity = try await fanHardware.getHelperIdentity()
        return verifyIdentity(
          activeIdentity,
          context: context,
          bundledIdentity: bundledIdentity
        )
      } catch {
        if Task.isCancelled {
          return verificationCancelled(context: context)
        }
        systemHelperLifecycleLog.notice(
          "system_helper.reconnect.waiting error=\(error.localizedDescription, privacy: .public) recovery=retry"
        )
      }
      guard await waitForVerificationPoll() else {
        return verificationCancelled(context: context)
      }
    }
    return fail(
      context: context,
      stage: .reconnect,
      reason: "System Helper did not reconnect before the deadline",
      recovery: "Retry System Helper repair"
    )
  }

  private func verifyIdentity(
    _ activeIdentity: SystemHelperIdentity,
    context: SystemHelperFailureContext,
    bundledIdentity: SystemHelperIdentity
  ) -> SystemHelperRuntimeState {
    guard activeIdentity.executableHash == bundledIdentity.executableHash else {
      return fail(
        context: SystemHelperFailureContext(
          operation: context.operation,
          activeIdentity: activeIdentity,
          bundledIdentity: bundledIdentity
        ),
        stage: .identityVerification,
        reason: "Registered System Helper does not match the bundled executable",
        recovery: "Retry System Helper repair"
      )
    }
    let state = SystemHelperRuntimeState.running(active: activeIdentity)
    lifecycleGate.resume()
    publish(state)
    systemHelperLifecycleLog.notice(
      "system_helper.reconcile.finished operation=\(context.operation.rawValue, privacy: .public) state=running hash=\(BuildFingerprint.presented(activeIdentity.executableHash), privacy: .public)"
    )
    return state
  }

  private func verificationCancelled(
    context: SystemHelperFailureContext
  ) -> SystemHelperRuntimeState {
    fail(
      context: context,
      stage: .reconnect,
      reason: "System Helper verification was cancelled",
      recovery: "Retry System Helper repair"
    )
  }
}
