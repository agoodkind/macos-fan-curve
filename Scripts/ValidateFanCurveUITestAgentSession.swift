#!/usr/bin/env swift

import Foundation

private enum AgentSessionValidationError: LocalizedError {
  case invalidArguments
  case missingPlist(String)
  case unreadablePlist(String)
  case missingEnvironment(String)
  case mismatchedSession(expected: String, actual: String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments:
      return
        "usage: ValidateFanCurveUITestAgentSession.swift <canonical-app> <expected-session>"
    case .missingPlist(let path):
      return
        "test-ui: canonical Background Agent plist is missing at \(path); rebuild and install the controlled app before running UI tests"
    case .unreadablePlist(let path):
      return
        "test-ui: canonical Background Agent plist is unreadable at \(path); rebuild and install the controlled app before running UI tests"
    case .missingEnvironment(let expected):
      return
        "test-ui: canonical Background Agent plist does not define FANCURVE_TEST_CONTROL_PATH=\(expected); rebuild and install the controlled app before running UI tests"
    case .mismatchedSession(let expected, let actual):
      return
        "test-ui: canonical Background Agent FANCURVE_TEST_CONTROL_PATH is \(actual), expected \(expected); rebuild and install the controlled app before running UI tests"
    }
  }
}

private let launchAgentRelativePath =
  "Contents/Library/LaunchAgents/agent-launchd.plist"
private let controlPathKey = "FANCURVE_TEST_CONTROL_PATH"

private func writeStandardError(_ message: String) {
  let data = Data("\(message)\n".utf8)
  FileHandle.standardError.write(data)
}

private func validateInstalledAgentSession(arguments: [String]) throws {
  guard arguments.count == 3 else {
    throw AgentSessionValidationError.invalidArguments
  }
  let canonicalAppURL = URL(
    fileURLWithPath: arguments[1],
    isDirectory: true
  ).standardizedFileURL
  let expectedSessionPath = URL(
    fileURLWithPath: arguments[2],
    isDirectory: true
  ).standardizedFileURL.path
  let launchAgentURL = canonicalAppURL.appendingPathComponent(
    launchAgentRelativePath,
    isDirectory: false
  )
  guard FileManager.default.fileExists(atPath: launchAgentURL.path) else {
    throw AgentSessionValidationError.missingPlist(launchAgentURL.path)
  }
  let data = try Data(contentsOf: launchAgentURL)
  guard
    let plist = try PropertyListSerialization.propertyList(
      from: data,
      options: [],
      format: nil
    ) as? [String: Any],
    let environment = plist["EnvironmentVariables"] as? [String: String]
  else {
    throw AgentSessionValidationError.unreadablePlist(launchAgentURL.path)
  }
  guard let embeddedSessionPath = environment[controlPathKey] else {
    throw AgentSessionValidationError.missingEnvironment(expectedSessionPath)
  }
  let standardizedEmbeddedSessionPath = URL(
    fileURLWithPath: embeddedSessionPath,
    isDirectory: true
  ).standardizedFileURL.path
  guard standardizedEmbeddedSessionPath == expectedSessionPath else {
    throw AgentSessionValidationError.mismatchedSession(
      expected: expectedSessionPath,
      actual: standardizedEmbeddedSessionPath
    )
  }
  writeStandardError(
    "test-ui: validated controlled Background Agent session \(expectedSessionPath)"
  )
}

do {
  try validateInstalledAgentSession(arguments: CommandLine.arguments)
} catch {
  writeStandardError(error.localizedDescription)
  exit(1)
}
