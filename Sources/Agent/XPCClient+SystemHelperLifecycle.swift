//
//  XPCClient+SystemHelperLifecycle.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let xpcClientLifecycleLog = AppLog.make(category: "XPCClient")

// MARK: - XPCClient

extension XPCClient {
  func resetAllDiscoveredFansToAuto() async throws {
    let xpcClient = try requireClient()
    let completion = XPCVoidOperationCompletion()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        completion.install(continuation)
        let operationTask = Task {
          do {
            await lifecycleRequestDispatchGate()
            try Task.checkCancellation()
            let requestScope = xpcClient.makeRequestScope()
            let fanCount = try await xpcClient.getFanCount(scope: requestScope)
            xpcClientLifecycleLog.notice(
              "xpc.strict_auto_reset.started fanCount=\(fanCount, privacy: .public)"
            )
            for fanIndex in 0..<fanCount {
              await lifecycleRequestDispatchGate()
              try Task.checkCancellation()
              do {
                try await xpcClient.setFanAuto(fanIndex, scope: requestScope)
              } catch {
                xpcClientLifecycleLog.error(
                  "xpc.strict_auto_reset.failed fan=\(fanIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=abort-helper-replacement"
                )
                throw error
              }
            }
            xpcClientLifecycleLog.notice(
              "xpc.strict_auto_reset.completed fanCount=\(fanCount, privacy: .public)"
            )
            completion.finish(with: .success(()))
          } catch {
            xpcClientLifecycleLog.notice(
              "xpc.strict_auto_reset.worker_failed error=\(error.localizedDescription, privacy: .public) recovery=complete-caller"
            )
            completion.finish(with: .failure(error))
          }
        }
        completion.install(operationTask: operationTask)
      }
    } onCancel: {
      if completion.finish(with: .failure(CancellationError())) {
        xpcClientLifecycleLog.notice(
          "xpc.strict_auto_reset.cancelled recovery=cancel-operation-task"
        )
      }
    }
  }
}
