//
//  FanCurveUITestDriver+Attachments.swift
//  FanCurveUITests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppKit
import Foundation
import XCTest

// MARK: - FanCurveUITestDriver

extension FanCurveUITestDriver {
  static func attachInitializationFailureArtifacts(
    to testCase: XCTestCase,
    name: String,
    error: Error
  ) {
    let stableName = sanitizedAttachmentName(name)
    let prefix = "initialization-\(stableName)"
    let initializationErrorDescription = error.localizedDescription
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "\(prefix)-screenshot"
    screenshot.lifetime = .keepAlways
    testCase.add(screenshot)

    let environment = ProcessInfo.processInfo.environment
    guard
      let sessionPath = environment["FANCURVE_TEST_CONTROL_PATH"],
      !sessionPath.isEmpty
    else {
      attachDiagnostic(
        "Driver initialization failed: \(initializationErrorDescription). "
          + "FANCURVE_TEST_CONTROL_PATH was unavailable.",
        name: "\(prefix)-diagnostic",
        to: testCase
      )
      return
    }

    let sessionURL = URL(
      fileURLWithPath: sessionPath,
      isDirectory: true
    ).standardizedFileURL
    let evidenceURL = sessionURL.deletingLastPathComponent().appendingPathComponent(
      "\(prefix)-evidence",
      isDirectory: true
    )
    do {
      let command = FanCurveTestControlCommand.exportEvidence(
        sessionPath: sessionURL.path,
        outputPath: evidenceURL.path
      )
      _ = try command.run()
      try attachEvidenceFiles(
        at: evidenceURL,
        prefix: prefix,
        to: testCase
      )
    } catch {
      let evidenceErrorDescription = error.localizedDescription
      fanCurveUITestLog.error(
        "ui_test.initialization_artifacts.evidence_failed initialization_error=\(initializationErrorDescription, privacy: .public) evidence_error=\(evidenceErrorDescription, privacy: .public) recovery=attach-diagnostic"
      )
      attachDiagnostic(
        "Driver initialization failed: \(initializationErrorDescription). "
          + "Evidence export also failed: \(evidenceErrorDescription)",
        name: "\(prefix)-diagnostic",
        to: testCase
      )
    }
  }

  func attachFailureArtifacts(name: String) {
    failureSequence += 1
    let stableName = sanitizedAttachmentName(name)
    let prefix = String(format: "%02d-%@", failureSequence, stableName)

    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "\(prefix)-screenshot"
    screenshot.lifetime = .keepAlways
    testCase.add(screenshot)

    let evidenceURL = sessionURL.deletingLastPathComponent().appendingPathComponent(
      "\(prefix)-evidence",
      isDirectory: true
    )
    do {
      let command = FanCurveTestControlCommand.exportEvidence(
        sessionPath: sessionURL.path,
        outputPath: evidenceURL.path
      )
      _ = try command.run()
      try Self.attachEvidenceFiles(
        at: evidenceURL,
        prefix: prefix,
        to: testCase
      )
    } catch {
      fanCurveUITestLog.error(
        "ui_test.evidence_export.failed error=\(error.localizedDescription, privacy: .public) recovery=attach-diagnostic"
      )
      attachEvidenceExportFailure(error, prefix: prefix)
    }
  }

  func assertCanonicalExecutablePath() throws {
    let mainWindow = try waitForElement(
      AppAccessibilityIdentifier.Application.mainWindow
    )
    guard
      let processIdentifierValue = mainWindow.value as? String,
      let launchedProcessIdentifier = pid_t(processIdentifierValue),
      launchedProcessIdentifier > 0,
      let runningApplication = NSRunningApplication(
        processIdentifier: launchedProcessIdentifier
      ),
      runningApplication.bundleIdentifier == generatedAppBundleID,
      !runningApplication.isTerminated,
      let executableURL = runningApplication.executableURL
    else {
      throw FanCurveUITestDriverError.unexpectedExecutablePath(
        "no running process resolved from the launched app's PID evidence"
      )
    }
    let resolvedExecutableURL =
      executableURL
      .resolvingSymlinksInPath()
      .standardizedFileURL
    let canonicalExecutableURL =
      URL(
        fileURLWithPath: "/Applications/Fan Curve.app/Contents/MacOS/FanCurve",
        isDirectory: false
      )
      .resolvingSymlinksInPath()
      .standardizedFileURL
    guard resolvedExecutableURL == canonicalExecutableURL else {
      throw FanCurveUITestDriverError.unexpectedExecutablePath(
        resolvedExecutableURL.path
      )
    }

    let attachment = XCTAttachment(string: resolvedExecutableURL.path)
    attachment.name = "canonical-app-executable-path"
    attachment.lifetime = .keepAlways
    testCase.add(attachment)
  }

  private static func attachEvidenceFiles(
    at directory: URL,
    prefix: String,
    to testCase: XCTestCase
  ) throws {
    let fileManager = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard
      let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }

    for case let fileURL as URL in enumerator {
      let values = try fileURL.resourceValues(forKeys: Set(keys))
      guard values.isRegularFile == true else {
        continue
      }
      let attachment = XCTAttachment(data: try Data(contentsOf: fileURL))
      attachment.name = "\(prefix)-\(fileURL.lastPathComponent)"
      attachment.lifetime = .keepAlways
      testCase.add(attachment)
    }
  }

  private func attachEvidenceExportFailure(_ error: Error, prefix: String) {
    let diagnostic = XCTAttachment(
      string: "Evidence export failed: \(error.localizedDescription)"
    )
    diagnostic.name = "\(prefix)-evidence-export-error"
    diagnostic.lifetime = .keepAlways
    testCase.add(diagnostic)
  }

  private static func attachDiagnostic(
    _ message: String,
    name: String,
    to testCase: XCTestCase
  ) {
    let diagnostic = XCTAttachment(string: message)
    diagnostic.name = name
    diagnostic.lifetime = .keepAlways
    testCase.add(diagnostic)
  }

  private static func sanitizedAttachmentName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    let transformed = value.lowercased().unicodeScalars.map { scalar -> Character in
      allowed.contains(scalar) ? Character(String(scalar)) : "-"
    }
    return String(transformed).replacingOccurrences(of: "--", with: "-")
  }

  private func sanitizedAttachmentName(_ value: String) -> String {
    Self.sanitizedAttachmentName(value)
  }
}
