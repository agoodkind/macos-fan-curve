//
//  FanCurveAgentMain.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import Darwin
import Foundation
import SMCFanLogging

/// LaunchAgent entry point. Runs the curve application loop in the background.
/// Resets all fans to auto on SIGTERM/SIGINT/crash.
@main
struct FanCurveAgentMain {
  static func main() {
    LogBootstrap.configure(subsystem: generatedAgentBundleID)

    Log.info("FanCurve agent starting (pid \(ProcessInfo.processInfo.processIdentifier))")

    let controller = AgentController()

    // Signal handlers: reset fans to auto before exit.
    installSignalHandler(SIGTERM, controller: controller)
    installSignalHandler(SIGINT, controller: controller)

    // atexit fallback (called for normal exit, not for signals on darwin unfortunately).
    atexit {
      // NOTE: atexit handlers are limited. Best effort only.
      Log.info("atexit handler: fans may not have been reset")
    }

    controller.start()
    RunLoop.main.run()
  }

  private static func installSignalHandler(_ sig: Int32, controller: AgentController) {
    // Ignore default handling; DispatchSource handles it on a queue.
    signal(sig, SIG_IGN)

    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
      Log.info("Agent received signal \(sig), resetting fans and exiting")
      Task {
        await controller.resetAllFansToAuto()
        controller.stop()
        exit(0)
      }
    }
    source.resume()

    // Retain the source so it doesn't get deallocated.
    signalSources.append(source)
  }

  nonisolated(unsafe) private static var signalSources: [DispatchSourceSignal] = []
}
