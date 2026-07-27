//
//  FanCurveServiceSmokeDriver.swift
//  FanCurveServiceSmokeTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import AppKit
import Foundation
import Nimble
import XCTest

private enum FanCurveServiceSmokeConstants {
  static let appLaunchTimeout: TimeInterval = 30
  static let appTerminationTimeout: TimeInterval = 20
  static let agentLabel = "io.goodkind.fancurveagent"
  static let agentConnectionReadyLog = "agent_client.connection.ready"
  static let agentDisconnectionLog = "agent_client.connection.disconnected"
  static let canonicalExecutablePath =
    "/Applications/Fan Curve.app/Contents/MacOS/FanCurve"
  static let firstFanIndex = 0
  static let runLoopPumpInterval: TimeInterval = 0.25
  static let requiredAgentReadyConnectionCount = 2
  static let settingsLaunchTimeout: TimeInterval = 5
  static let settingsBundleIdentifier = "com.apple.systempreferences"
  static let setupTimeout: TimeInterval = 180
  static let stateTimeout: TimeInterval = 60
}

// MARK: - ServiceSmokeProcessResult

// MARK: - FanCurveServiceSmokeDriver

@MainActor
final class FanCurveServiceSmokeDriver {
  private let app = XCUIApplication(bundleIdentifier: generatedAppBundleID)
  private let processRunner = ServiceSmokeProcessRunner()
  private let startDate = Date()

  func prepareFanSafety() throws {
    try writeSharedDefault(key: "curveActive", boolean: false)
    try writeSharedDefault(key: "boostEnabled", boolean: false)
  }

  func launchCanonicalApp() throws {
    app.launchArguments += [
      "-ApplePersistenceIgnoreState",
      "YES",
      "-NSQuitAlwaysKeepsWindows",
      "NO",
    ]
    app.launch()
    expect(
      self.app.wait(
        for: .runningForeground,
        timeout: FanCurveServiceSmokeConstants.appLaunchTimeout
      )
    )
    .to(
      beTrue(),
      description: "The canonical Release app did not reach the foreground"
    )
    try assertCanonicalExecutable()
  }

  func completeRealServiceSetup() throws {
    let deadline = Date().addingTimeInterval(
      FanCurveServiceSmokeConstants.setupTimeout
    )
    while Date() < deadline {
      if dashboardAndFanReadingAreVisible() {
        return
      }
      try throwVisibleSetupError()
      let action = app.buttons[AppAccessibilityIdentifier.Setup.action]
      if action.exists, action.isEnabled {
        action.click()
        approveBackgroundServiceIfRequired()
      } else {
        pumpRunLoop()
      }
    }
    throw FanCurveServiceSmokeFailure.timedOut("real service setup")
  }

  func assertHelperReadReachedDashboard() {
    let dashboard = app.otherElements[AppAccessibilityIdentifier.Dashboard.root]
    expect(
      dashboard.waitForExistence(
        timeout: FanCurveServiceSmokeConstants.appLaunchTimeout
      )
    )
    .to(beTrue(), description: "The live Agent XPC dashboard did not appear")
    let fan = app.descendants(matching: .any)[
      AppAccessibilityIdentifier.Dashboard.fanRow(
        FanCurveServiceSmokeConstants.firstFanIndex
      )
    ]
    expect(
      fan.waitForExistence(
        timeout: FanCurveServiceSmokeConstants.appLaunchTimeout
      )
    )
    .to(
      beTrue(),
      description: "The real helper did not return the first fan reading"
    )
  }

  func waitForAgentPID(differentFrom priorPID: Int32? = nil) throws -> Int32 {
    let deadline = Date().addingTimeInterval(
      FanCurveServiceSmokeConstants.stateTimeout
    )
    while Date() < deadline {
      let result = try processRunner.run(
        "/usr/bin/defaults",
        arguments: ["read", generatedSharedSuiteID, "agentPID"]
      )
      if result.status == 0,
        let value = Int32(result.output.trimmingCharacters(in: .whitespacesAndNewlines)),
        value > 0,
        value != priorPID
      {
        return value
      }
      pumpRunLoop()
    }
    throw FanCurveServiceSmokeFailure.timedOut("a live Agent PID")
  }

  func waitForAgentLastTick(after priorTick: TimeInterval = 0) throws
    -> TimeInterval
  {
    let deadline = Date().addingTimeInterval(
      FanCurveServiceSmokeConstants.stateTimeout
    )
    while Date() < deadline {
      let result = try processRunner.run(
        "/usr/bin/defaults",
        arguments: ["read", generatedSharedSuiteID, "agentLastTick"]
      )
      if result.status == 0,
        let value = TimeInterval(
          result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        value > priorTick
      {
        return value
      }
      pumpRunLoop()
    }
    throw FanCurveServiceSmokeFailure.timedOut("a new Agent telemetry tick")
  }

  func killAgent() throws {
    let userID = getuid()
    let serviceTarget =
      "gui/\(userID)/\(FanCurveServiceSmokeConstants.agentLabel)"
    let result = try processRunner.run(
      "/bin/launchctl",
      arguments: ["kill", "SIGKILL", serviceTarget]
    )
    guard result.status == 0 else {
      throw FanCurveServiceSmokeFailure.commandFailed(
        operation: "launchctl Agent SIGKILL",
        error: result.error
      )
    }
  }

  func relaunchCanonicalApp() throws {
    app.terminate()
    expect(
      self.app.wait(
        for: .notRunning,
        timeout: FanCurveServiceSmokeConstants.appTerminationTimeout
      )
    ) == true
    try launchCanonicalApp()
  }

  func assertNoFanRPMWrites() throws {
    let logResult = try processRunner.run(
      "/usr/bin/log",
      arguments: [
        "show",
        "--start",
        logStartArgument(),
        "--style",
        "compact",
        "--predicate",
        "process == \"FanCurve\" OR process == \"FanCurveAgent\" "
          + "OR process == \"io.goodkind.smcfanhelper\"",
      ]
    )
    guard logResult.status == 0 else {
      throw FanCurveServiceSmokeFailure.commandFailed(
        operation: "read unified log",
        error: logResult.error
      )
    }
    attach(logResult.output, name: "Release smoke unified log")
    expect(logResult.output).to(
      contain(FanCurveServiceSmokeConstants.agentDisconnectionLog),
      description: "The app did not observe the killed Agent connection"
    )
    let readyConnectionCount =
      logResult.output.components(
        separatedBy: FanCurveServiceSmokeConstants.agentConnectionReadyLog
      ).count - 1
    expect(readyConnectionCount).to(
      beGreaterThanOrEqualTo(
        FanCurveServiceSmokeConstants.requiredAgentReadyConnectionCount
      ),
      description: "The app did not establish a replacement Agent XPC connection"
    )
    for forbiddenWrite in [
      "agent.hardware.rpm.requested",
      "agent.hardware.rpm.succeeded",
      "xpc.set_fan",
      "smcSetFanRPM",
    ] {
      expect(logResult.output).toNot(
        contain(forbiddenWrite),
        description: "Fan control was disabled but an RPM write was observed"
      )
    }
  }

  func terminate() {
    if app.state != .notRunning {
      app.terminate()
    }
  }
}

// MARK: - Private Helpers

extension FanCurveServiceSmokeDriver {
  private func approveBackgroundServiceIfRequired() {
    let settings = XCUIApplication(
      bundleIdentifier: FanCurveServiceSmokeConstants.settingsBundleIdentifier
    )
    guard
      settings.wait(
        for: .runningForeground,
        timeout: FanCurveServiceSmokeConstants.settingsLaunchTimeout
      )
    else {
      pumpRunLoop()
      return
    }
    let fanCurveControls = settings.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS[c] %@", "Fan Curve")
    )
    for index in 0..<fanCurveControls.count {
      let control = fanCurveControls.element(boundBy: index)
      guard control.isHittable else { continue }
      if control.elementType == .switch || control.elementType == .checkBox {
        let enabledValue = control.value as? String
        if enabledValue != "1" {
          control.click()
        }
      }
    }
    let allowButton = settings.buttons["Allow"]
    if allowButton.exists, allowButton.isHittable {
      allowButton.click()
    }
    app.activate()
    expect(
      self.app.wait(
        for: .runningForeground,
        timeout: FanCurveServiceSmokeConstants.appTerminationTimeout
      )
    ) == true
  }

  private func dashboardAndFanReadingAreVisible() -> Bool {
    let dashboard = app.otherElements[AppAccessibilityIdentifier.Dashboard.root]
    let fan = app.descendants(matching: .any)[
      AppAccessibilityIdentifier.Dashboard.fanRow(
        FanCurveServiceSmokeConstants.firstFanIndex
      )
    ]
    return dashboard.exists && fan.exists
  }

  private func throwVisibleSetupError() throws {
    let error = app.staticTexts[AppAccessibilityIdentifier.Setup.error]
    if error.exists {
      throw FanCurveServiceSmokeFailure.setup(error.label)
    }
  }

  private func assertCanonicalExecutable() throws {
    let mainWindow = app.windows[
      AppAccessibilityIdentifier.Application.mainWindow
    ]
    expect(
      mainWindow.waitForExistence(
        timeout: FanCurveServiceSmokeConstants.appTerminationTimeout
      )
    ) == true
    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: generatedAppBundleID
    )
    guard
      runningApplications.count == 1,
      let runningApplication = runningApplications.first,
      let executableURL = runningApplication.executableURL?.standardizedFileURL
    else {
      throw FanCurveServiceSmokeFailure.processResolution
    }
    let expectedExecutableURL = URL(
      fileURLWithPath: FanCurveServiceSmokeConstants.canonicalExecutablePath
    ).standardizedFileURL
    expect(runningApplication.bundleIdentifier) == generatedAppBundleID
    expect(executableURL) == expectedExecutableURL
  }

  private func writeSharedDefault(key: String, boolean: Bool) throws {
    let result = try processRunner.run(
      "/usr/bin/defaults",
      arguments: [
        "write",
        generatedSharedSuiteID,
        key,
        "-bool",
        boolean ? "true" : "false",
      ]
    )
    guard result.status == 0 else {
      throw FanCurveServiceSmokeFailure.commandFailed(
        operation: "write \(key)",
        error: result.error
      )
    }
  }

  private func logStartArgument() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: startDate)
  }

  private func attach(_ contents: String, name: String) {
    let attachment = XCTAttachment(string: contents)
    attachment.name = name
    attachment.lifetime = .keepAlways
    XCTContext.runActivity(named: name) { activity in
      activity.add(attachment)
    }
  }

  private func pumpRunLoop() {
    RunLoop.current.run(
      until: Date().addingTimeInterval(
        FanCurveServiceSmokeConstants.runLoopPumpInterval
      )
    )
  }
}

// MARK: - FanCurveServiceSmokeFailure

private enum FanCurveServiceSmokeFailure: LocalizedError {
  case commandFailed(operation: String, error: String)
  case processResolution
  case setup(String)
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case let .commandFailed(operation, error):
      return "\(operation) failed: \(error)"
    case .processResolution:
      return "The running Release app process could not be resolved"
    case .setup(let message):
      return "Release setup failed: \(message)"
    case .timedOut(let operation):
      return "Timed out waiting for \(operation)"
    }
  }
}
