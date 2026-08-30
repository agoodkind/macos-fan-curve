//
//  FanCurveTestControlMain.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Darwin
  import Foundation

  private let testControlMainLog = AppLog.make(category: "FanCurveTestControl")

  private enum CLIOut {
    static func print(_ value: String) {
      FileHandle.standardOutput.write(Data((value + "\n").utf8))
    }

    static func err(_ value: String) {
      FileHandle.standardError.write(Data((value + "\n").utf8))
    }
  }

  @main
  enum FanCurveTestControlMain {
    static func main() {
      do {
        let command = try FanCurveTestControlCommand.parse(
          Array(CommandLine.arguments.dropFirst())
        )
        testControlMainLog.info("test_control.cli.command.started")
        let result = try command.run()
        CLIOut.print(result)
        testControlMainLog.info("test_control.cli.command.completed")
      } catch {
        testControlMainLog.error(
          "test_control.cli.command.failed error=\(error.localizedDescription, privacy: .public) recovery=exit-nonzero"
        )
        CLIOut.err(error.localizedDescription)
        Darwin.exit(EXIT_FAILURE)
      }
    }
  }
#endif
