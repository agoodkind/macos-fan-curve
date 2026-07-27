//
//  ServiceSmokeProcessRunner.swift
//  FanCurveServiceSmokeTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - ServiceSmokeProcessResult

struct ServiceSmokeProcessResult {
  let status: Int32
  let output: String
  let error: String
}

// MARK: - ServiceSmokeProcessRunner

@MainActor
struct ServiceSmokeProcessRunner {
  func run(
    _ executablePath: String,
    arguments: [String]
  ) throws -> ServiceSmokeProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    let outputURL = temporaryOutputURL(suffix: "stdout")
    let errorURL = temporaryOutputURL(suffix: "stderr")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let temporaryURLs = [outputURL, errorURL]
    do {
      let outputHandle = try FileHandle(forWritingTo: outputURL)
      let errorHandle = try FileHandle(forWritingTo: errorURL)
      process.standardOutput = outputHandle
      process.standardError = errorHandle
      try process.run()
      process.waitUntilExit()
      try outputHandle.close()
      try errorHandle.close()
      let outputData = try Data(contentsOf: outputURL)
      let errorData = try Data(contentsOf: errorURL)
      guard
        let output = String(bytes: outputData, encoding: .utf8),
        let error = String(bytes: errorData, encoding: .utf8)
      else {
        throw ServiceSmokeProcessRunnerFailure.invalidCommandOutput
      }
      try removeTemporaryOutputs(temporaryURLs)
      return ServiceSmokeProcessResult(
        status: process.terminationStatus,
        output: output,
        error: error
      )
    } catch {
      let primaryError = error
      do {
        try removeTemporaryOutputs(temporaryURLs)
      } catch {
        throw ServiceSmokeProcessRunnerFailure.cleanupFailed(
          primary: primaryError.localizedDescription,
          cleanup: error.localizedDescription
        )
      }
      throw primaryError
    }
  }

  private func temporaryOutputURL(suffix: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "FanCurveServiceSmoke-\(UUID().uuidString).\(suffix)"
    )
  }

  private func removeTemporaryOutputs(_ urls: [URL]) throws {
    for url in urls
    where FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}

// MARK: - ServiceSmokeProcessRunnerFailure

private enum ServiceSmokeProcessRunnerFailure: Error {
  case cleanupFailed(primary: String, cleanup: String)
  case invalidCommandOutput
}
