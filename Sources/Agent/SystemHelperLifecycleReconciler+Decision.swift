//
//  SystemHelperLifecycleReconciler+Decision.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - SystemHelperLifecycleReconciler

extension SystemHelperLifecycleReconciler {
  func reconcileValidatedHelper(
    trigger: SystemHelperReconcileTrigger,
    serviceStatus: ManagedServiceStatus,
    bundledIdentity: SystemHelperIdentity
  ) async -> SystemHelperReconcileResult {
    guard serviceStatus == .enabled else {
      return await reconcileDisabledHelper(
        trigger: trigger,
        serviceStatus: serviceStatus,
        bundledIdentity: bundledIdentity
      )
    }
    return await reconcileEnabledHelper(
      trigger: trigger,
      bundledIdentity: bundledIdentity
    )
  }

  private func reconcileDisabledHelper(
    trigger: SystemHelperReconcileTrigger,
    serviceStatus: ManagedServiceStatus,
    bundledIdentity: SystemHelperIdentity
  ) async -> SystemHelperReconcileResult {
    let state = SystemHelperClassifier.classify(
      serviceStatus: serviceStatus,
      observation: .unreachable(reason: "Identity was not requested"),
      bundled: bundledIdentity
    )
    guard trigger == .forcedRepair,
      serviceStatus == .notRegistered
    else {
      publish(state)
      return result(state)
    }
    return await repairMissingHelper(
      trigger: trigger,
      bundledIdentity: bundledIdentity,
      fallbackState: state
    )
  }

  private func repairMissingHelper(
    trigger: SystemHelperReconcileTrigger,
    bundledIdentity: SystemHelperIdentity,
    fallbackState: SystemHelperRuntimeState
  ) async -> SystemHelperReconcileResult {
    let observation: SystemHelperIdentityObservation
    do {
      observation = try await observeActiveHelper()
    } catch is CancellationError {
      return cancelled(
        context: SystemHelperFailureContext(
          operation: trigger.operation,
          activeIdentity: nil,
          bundledIdentity: bundledIdentity
        ),
        stage: .disconnect
      )
    } catch {
      systemHelperLifecycleLog.error(
        "system_helper.observe.failed operation=\(trigger.operation.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=retain-registration"
      )
      return result(fallbackState)
    }
    let context = SystemHelperFailureContext(
      operation: trigger.operation,
      activeIdentity: observation.activeIdentity,
      bundledIdentity: bundledIdentity
    )
    publish(.updating(active: context.activeIdentity, bundled: bundledIdentity))
    if observation.isReachable,
      let resetFailure = await resetFans(context: context)
    {
      return result(resetFailure)
    }
    if Task.isCancelled {
      return cancelled(context: context, stage: .register)
    }
    return await registerMissingHelper(
      context: context,
      bundledIdentity: bundledIdentity
    )
  }

  private func reconcileEnabledHelper(
    trigger: SystemHelperReconcileTrigger,
    bundledIdentity: SystemHelperIdentity
  ) async -> SystemHelperReconcileResult {
    let observation: SystemHelperIdentityObservation
    do {
      observation = try await observeActiveHelper()
    } catch is CancellationError {
      return cancelled(
        context: SystemHelperFailureContext(
          operation: trigger.operation,
          activeIdentity: nil,
          bundledIdentity: bundledIdentity
        ),
        stage: .disconnect
      )
    } catch {
      systemHelperLifecycleLog.error(
        "system_helper.observe.failed operation=\(trigger.operation.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-unavailable"
      )
      return result(.unavailable(reason: error.localizedDescription))
    }
    let classifiedState = SystemHelperClassifier.classify(
      serviceStatus: .enabled,
      observation: observation,
      bundled: bundledIdentity
    )
    return await reconcileClassifiedHelper(
      classifiedState,
      trigger: trigger,
      bundledIdentity: bundledIdentity
    )
  }

  private func reconcileClassifiedHelper(
    _ classifiedState: SystemHelperRuntimeState,
    trigger: SystemHelperReconcileTrigger,
    bundledIdentity: SystemHelperIdentity
  ) async -> SystemHelperReconcileResult {
    if trigger != .forcedRepair {
      switch classifiedState {
      case .running:
        lifecycleGate.resume()
        publish(classifiedState)
        return result(classifiedState)
      case .outdated:
        publish(classifiedState)
      default:
        publish(classifiedState)
        return result(classifiedState)
      }
    }
    let context = SystemHelperFailureContext(
      operation: trigger.operation,
      activeIdentity: classifiedState.activeIdentity,
      bundledIdentity: bundledIdentity
    )
    publish(.updating(active: context.activeIdentity, bundled: bundledIdentity))
    return await replaceHelper(
      context: context,
      bundledIdentity: bundledIdentity
    )
  }

}
