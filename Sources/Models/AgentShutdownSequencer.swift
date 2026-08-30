//
//  AgentShutdownSequencer.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let agentShutdownSequencerLog = AppLog.make(category: "AgentShutdownSequencer")

// MARK: - AgentShutdownSequencer

/// Bounds agent shutdown inside launchd's SIGKILL grace period. Stops tick
/// scheduling first so the reset-to-auto call is not competing with the
/// tick loop for the same serialized XPC channel, then races the reset
/// against `deadline` so shutdown can exit even if the helper never answers.
enum AgentShutdownSequencer {
  static func resetWithinDeadline(
    deadline: TimeInterval,
    stopTicking: () -> Void,
    resetFans: @escaping @Sendable () async -> Void
  ) async -> DeadlineOutcome {
    agentShutdownSequencerLog.notice(
      "agent.shutdown.reset.starting deadlineSeconds=\(deadline, privacy: .public)")
    stopTicking()
    agentShutdownSequencerLog.notice("agent.shutdown.tick_stopped")

    let outcome = await DeadlineBoundedOperation.run(
      deadline: deadline,
      operation: resetFans
    )
    switch outcome {
    case .completed:
      agentShutdownSequencerLog.notice(
        "agent.shutdown.reset.finished outcome=completed"
      )
    case .deadlineExceeded:
      agentShutdownSequencerLog.notice(
        "agent.shutdown.reset.finished outcome=deadline_exceeded deadlineSeconds=\(deadline, privacy: .public) recovery=exit-anyway"
      )
    }
    return outcome
  }
}
