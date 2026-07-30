//
//  FanCurveAgentMain.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Darwin
import Foundation

private let log = AppLog.make(category: "AgentMain")

private enum FanCurveAgentMainConstants {
  /// Comfortably inside launchd's 5 second SIGTERM-to-SIGKILL grace period,
  /// leaving margin for `AgentController.stop()` and process exit after the
  /// reset-to-auto race resolves either way.
  static let shutdownResetDeadlineSeconds: TimeInterval = 3.0
}

// MARK: - FanCurveAgentMain

/// LaunchAgent entry point. Runs the curve application loop in the background.
/// Resets all fans to auto on SIGTERM/SIGINT/crash.
@main
enum FanCurveAgentMain {
  static func main() {
    AppLog.bootstrap(subsystem: "io.goodkind.fan")

    log.notice(
      "agent.starting pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")

    #if DEBUG
      let runtimeMode = TestControlProcessRuntimes.agent
      let fanHardware = AgentTestControlAdapters.fanHardware(mode: runtimeMode) {
        XPCClient(clientName: generatedAgentBundleID)
      }
      let helperService = AgentTestControlAdapters.helperService(mode: runtimeMode) {
        HelperServiceManagementAdapter()
      }
      let controller = AgentController(fanHardware: fanHardware)
      controller.runtimeHealthOverrideProvider =
        AgentTestControlAdapters.runtimeHealthOverrideProvider(mode: runtimeMode)
      let appXPCService = FanCurveAgentXPCService(
        controller: controller,
        helperService: helperService,
        faultController: TestControlAgentXPCFaultController(mode: runtimeMode)
      )
    #else
      let controller = AgentController()
      let appXPCService = FanCurveAgentXPCService(controller: controller)
    #endif

    installSignalHandler(SIGTERM, controller: controller)
    installSignalHandler(SIGINT, controller: controller)

    atexit {
      let exitLog = AppLog.make(category: "AgentMain")
      exitLog.info("agent.atexit fans may not have been reset")
    }

    appXPCService.start()
    controller.start()
    RunLoop.main.run()
  }

  private static func installSignalHandler(_ sig: Int32, controller: AgentController) {
    signal(sig, SIG_IGN)

    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
      log.notice("agent.signal received=\(sig, privacy: .public) action=reset-and-exit")
      Task {
        let outcome = await AgentShutdownSequencer.resetWithinDeadline(
          deadline: FanCurveAgentMainConstants.shutdownResetDeadlineSeconds,
          stopTicking: { controller.stopTickTimer() },
          resetFans: { await controller.resetAllFansToAuto() }
        )
        switch outcome {
        case .completed:
          log.notice("agent.signal.reset.completed")
        case .deadlineExceeded:
          log.notice(
            "agent.signal.reset.deadline_exceeded deadlineSeconds=\(FanCurveAgentMainConstants.shutdownResetDeadlineSeconds, privacy: .public) action=exit-anyway"
          )
        }
        controller.stop()
        CFRunLoopStop(CFRunLoopGetMain())
      }
    }
    source.resume()

    signalSources.append(source)
  }

  nonisolated(unsafe) private static var signalSources: [DispatchSourceSignal] = []
}
