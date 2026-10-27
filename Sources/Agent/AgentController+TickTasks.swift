//
//  AgentController+TickTasks.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-10-27.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let agentControllerTickTaskLog = AppLog.make(category: "AgentControllerTick")

// MARK: - AgentController

extension AgentController {
  func requestTick() {
    let taskID = UUID()
    tickTaskLock.withLock {
      tickTasks[taskID] = Task { [weak self] in
        guard let self else { return }
        defer { finishTickTask(taskID) }
        guard await tickCoordinator.requestTick() else { return }
        await runTickLoop()
      }
    }
  }

  /// Call pause() first; an active lifecycle can keep adding ticks to the wait.
  /// This method awaits tick tasks until tickTasks is empty. Running ticks finish
  /// their SharedConfig writes before this method returns.
  func waitUntilTickIdle() async {
    while true {
      let pendingTasks = tickTaskLock.withLock { Array(tickTasks.values) }
      guard !pendingTasks.isEmpty else {
        agentControllerTickTaskLog.debug("agent.tick.idle")
        return
      }
      agentControllerTickTaskLog.debug(
        "agent.tick.wait_for_idle pending=\(pendingTasks.count, privacy: .public)"
      )
      for task in pendingTasks {
        await task.value
      }
    }
  }

  private func finishTickTask(_ taskID: UUID) {
    _ = tickTaskLock.withLock {
      tickTasks.removeValue(forKey: taskID)
    }
  }
}
