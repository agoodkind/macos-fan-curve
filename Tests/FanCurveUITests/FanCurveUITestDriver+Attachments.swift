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
      try attachEvidenceFiles(at: evidenceURL, prefix: prefix)
    } catch {
      fanCurveUITestLog.error(
        "ui_test.evidence_export.failed error=\(error.localizedDescription, privacy: .public) recovery=attach-diagnostic"
      )
      attachEvidenceExportFailure(error, prefix: prefix)
    }
  }

  func assertCanonicalExecutablePath() throws {
    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: generatedAppBundleID
    )
    guard
      let runningApplication = runningApplications.first(where: { !$0.isTerminated }),
      let executableURL = runningApplication.executableURL
    else {
      throw FanCurveUITestDriverError.unexpectedExecutablePath(
        "no running process resolved for \(generatedAppBundleID)"
      )
    }
    let resolvedPath =
      executableURL
      .resolvingSymlinksInPath()
      .standardizedFileURL
      .path
    let canonicalBundlePrefix =
      URL(
        fileURLWithPath: "/Applications/Fan Curve.app/Contents/MacOS/",
        isDirectory: true
      )
      .resolvingSymlinksInPath()
      .standardizedFileURL
      .path
    guard resolvedPath.hasPrefix(canonicalBundlePrefix) else {
      throw FanCurveUITestDriverError.unexpectedExecutablePath(resolvedPath)
    }

    let attachment = XCTAttachment(string: resolvedPath)
    attachment.name = "canonical-app-executable-path"
    attachment.lifetime = .keepAlways
    testCase.add(attachment)
  }

  private func attachEvidenceFiles(at directory: URL, prefix: String) throws {
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

  private func sanitizedAttachmentName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    let transformed = value.lowercased().unicodeScalars.map { scalar -> Character in
      allowed.contains(scalar) ? Character(String(scalar)) : "-"
    }
    return String(transformed).replacingOccurrences(of: "--", with: "-")
  }
}
