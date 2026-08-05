//
//  main.swift
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

private func bundledSystemHelperExecutableURL() -> URL {
  guard let agentExecutableURL = Bundle.main.executableURL else {
    log.error(
      "agent.system_helper.bundle_path.failed reason=agent-executable-unavailable recovery=terminate"
    )
    exit(1)
  }
  return agentExecutableURL.deletingLastPathComponent()
    .appendingPathComponent(generatedHelperBundleID)
}

nonisolated(unsafe) private var signalSources: [DispatchSourceSignal] = []

private func installSignalHandler(_ sig: Int32, controller: AgentController) {
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
      // RunLoop.main.run() is Foundation's "permanent loop" convenience: it
      // re-enters run(mode:before:) itself, so CFRunLoopStop only ends the
      // current inner iteration and the loop keeps going. The XPC listener
      // in FanCurveAgentXPCService also runs on its own GCD-backed mach
      // port independent of the run loop, so the process stays alive and
      // keeps answering XPC calls even after controller.stop(). Exit the
      // process directly so a launchd-delivered SIGTERM (as make run's
      // deploy step sends) actually terminates the agent and lets
      // launchd's KeepAlive respawn it from the freshly deployed binary.
      log.notice("agent.exiting signal=\(sig, privacy: .public)")
      exit(0)
    }
  }
  source.resume()

  signalSources.append(source)
}

// MARK: - Entry point

// LaunchAgent entry point. Runs the curve application loop in the background.
// Resets all fans to auto on SIGTERM/SIGINT/crash. This is a literal
// `main.swift` (rather than an `@main`-attributed type) so the process can
// call `exit(_:)` directly from a recognized CLI entrypoint file.
AppLog.bootstrap(subsystem: "io.goodkind.fan")

log.notice(
  "agent.starting pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")

#if DEBUG
  // Debug builds resolve the agent's composition root through the test control
  // adapters, which fall back to the production XPC client unless an explicit
  // controlled session is active. Release builds have no such seam.
  let runtimeMode = TestControlProcessRuntimes.agent
  let fanHardware = AgentTestControlAdapters.fanHardware(mode: runtimeMode) {
    XPCClient(clientName: generatedAgentBundleID)
  }
  let helperService = AgentTestControlAdapters.helperService(mode: runtimeMode) {
    HelperServiceManagementAdapter()
  }
  let artifactValidator = AgentTestControlAdapters.artifactValidator(
    mode: runtimeMode
  ) {
    SystemHelperArtifactValidator()
  }
  let faultController: any FanCurveAgentXPCFaultControlling =
    TestControlAgentXPCFaultController(mode: runtimeMode)
#else
  let fanHardware: any FanHardware = XPCClient(clientName: generatedAgentBundleID)
  let helperService: any HelperServiceManaging = HelperServiceManagementAdapter()
  let artifactValidator: any SystemHelperArtifactValidating =
    SystemHelperArtifactValidator()
  let faultController: any FanCurveAgentXPCFaultControlling =
    ProductionAgentXPCFaultControl()
#endif

let controller = AgentController(fanHardware: fanHardware)
let reconciler = SystemHelperLifecycleReconciler(
  fanHardware: fanHardware,
  service: helperService,
  lifecycleGate: controller,
  bundledExecutableURL: bundledSystemHelperExecutableURL(),
  artifactValidator: artifactValidator
) { state in
  controller.updateSystemHelperRuntimeState(state)
}
let appXPCService = FanCurveAgentXPCService(
  controller: controller,
  helperService: helperService,
  reconciler: reconciler,
  faultController: faultController
)

installSignalHandler(SIGTERM, controller: controller)
installSignalHandler(SIGINT, controller: controller)

atexit {
  let exitLog = AppLog.make(category: "AgentMain")
  exitLog.info("agent.atexit fans may not have been reset")
}

appXPCService.start()
Task {
  await appXPCService.reconcileSystemHelper(trigger: .startup)
}
RunLoop.main.run()
