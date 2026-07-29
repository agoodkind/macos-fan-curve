//
//  TestControlAgentSessionValidatorTests.swift
//  FanCurveTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

private let validatorTestRepositoryURL = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()

private struct ValidatorLaunchAgentPlist: Encodable {
  let label: String
  let environmentVariables: [String: String]

  private enum CodingKeys: String, CodingKey {
    case label = "Label"
    case environmentVariables = "EnvironmentVariables"
  }
}

// MARK: - TestControlAgentSessionValidatorTests

final class TestControlAgentSessionValidatorTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func setUpWithError() throws {
    try super.setUpWithError()
    temporaryDirectories.removeAll()
  }

  override func tearDownWithError() throws {
    for directory in temporaryDirectories
    where FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
    try super.tearDownWithError()
  }

  func testInstalledAgentSessionValidatorAcceptsAnExactEmbeddedSession() throws {
    let appURL = try makeControlledAppFixture(
      controlPath: "/tmp/fan-curve-ui-session"
    )

    let result = try runInstalledAgentSessionValidator(
      appURL: appURL,
      expectedSessionPath: "/tmp/fan-curve-ui-session"
    )

    expect(result.status) == 0
    expect(result.errorOutput).to(
      contain("validated controlled Background Agent session")
    )
  }

  func testInstalledAgentSessionValidatorRejectsAMismatchedEmbeddedSession() throws {
    let appURL = try makeControlledAppFixture(
      controlPath: "/tmp/stale-fan-curve-ui-session"
    )

    let result = try runInstalledAgentSessionValidator(
      appURL: appURL,
      expectedSessionPath: "/tmp/fan-curve-ui-session"
    )

    expect(result.status) != 0
    expect(result.errorOutput).to(contain("FANCURVE_TEST_CONTROL_PATH"))
    expect(result.errorOutput).to(contain("/tmp/fan-curve-ui-session"))
    expect(result.errorOutput).to(contain("rebuild and install"))
  }

  private func makeControlledAppFixture(controlPath: String) throws -> URL {
    let root = try makeTemporaryDirectory()
    let appURL = root.appendingPathComponent("Fan Curve.app", isDirectory: true)
    let launchAgentsURL =
      appURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("LaunchAgents", isDirectory: true)
    try FileManager.default.createDirectory(
      at: launchAgentsURL,
      withIntermediateDirectories: true
    )
    let plist = ValidatorLaunchAgentPlist(
      label: "io.goodkind.fancurveagent",
      environmentVariables: [
        "FANCURVE_TEST_CONTROL_PATH": controlPath
      ]
    )
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    let plistData = try encoder.encode(plist)
    try plistData.write(
      to: launchAgentsURL.appendingPathComponent("agent-launchd.plist"),
      options: .atomic
    )
    return appURL
  }

  private func runInstalledAgentSessionValidator(
    appURL: URL,
    expectedSessionPath: String
  ) throws -> (status: Int32, errorOutput: String) {
    let process = Process()
    process.executableURL = validatorTestRepositoryURL.appendingPathComponent(
      "Scripts/ValidateFanCurveUITestAgentSession.swift"
    )
    process.arguments = [appURL.path, expectedSessionPath]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
    return (process.terminationStatus, errorOutput)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "FanCurveAgentSessionValidator-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    temporaryDirectories.append(directory)
    return directory
  }
}
