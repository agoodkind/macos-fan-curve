//
//  ServiceOwnershipBoundaryTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

final class ServiceOwnershipBoundaryTests: XCTestCase {
  func testHelperServiceAdapterCompilesOnlyIntoAgentTarget() throws {
    let project = try generatedProject()

    let appSources = try sourcesBuildPhase(named: "FanCurve", in: project)
    let agentSources = try sourcesBuildPhase(named: "FanCurveAgent", in: project)

    expect(String(appSources)).toNot(contain("HelperServiceManagementAdapter.swift in Sources"))
    expect(String(agentSources)).to(contain("HelperServiceManagementAdapter.swift in Sources"))
  }

  private func generatedProject() throws -> String {
    let repositoryURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let projectURL =
      repositoryURL
      .appendingPathComponent("FanCurveApp.xcodeproj")
      .appendingPathComponent("project.pbxproj")
    return try String(
      contentsOf: projectURL,
      encoding: .utf8
    )
  }

  private func sourcesBuildPhase(
    named targetName: String,
    in project: String
  ) throws -> Substring {
    let targetBody = try nativeTargetBody(named: targetName, in: project)
    let sourcePhasePattern = #"([A-F0-9]+) /\* Sources \*/"#
    let sourcePhaseID = try firstCapture(
      pattern: sourcePhasePattern,
      in: targetBody,
      failureMessage: "Missing Sources build phase for \(targetName)"
    )
    let phasePattern =
      #"(?ms)^\s*\#(sourcePhaseID) /\* Sources \*/ = \{\n\s*isa = PBXSourcesBuildPhase;(.*?)^\s*\};"#
    return try firstCapture(
      pattern: phasePattern,
      in: project[...],
      failureMessage: "Missing Sources build phase body for \(targetName)"
    )
  }

  private func nativeTargetBody(
    named targetName: String,
    in project: String
  ) throws -> Substring {
    let escapedTargetName = NSRegularExpression.escapedPattern(for: targetName)
    let targetPattern =
      #"(?ms)^\s*[A-F0-9]+ /\* \#(escapedTargetName) \*/ = \{\n\s*isa = PBXNativeTarget;(.*?)^\s*\};"#
    return try firstCapture(
      pattern: targetPattern,
      in: project[...],
      failureMessage: "Missing native target \(targetName)"
    )
  }

  private func firstCapture(
    pattern: String,
    in value: Substring,
    failureMessage: String
  ) throws -> Substring {
    let expression = try NSRegularExpression(pattern: pattern)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = expression.firstMatch(in: String(value), range: range) else {
      throw NSError(
        domain: "ServiceOwnershipBoundaryTests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: failureMessage]
      )
    }
    guard let captureRange = Range(match.range(at: 1), in: value) else {
      throw NSError(
        domain: "ServiceOwnershipBoundaryTests",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: failureMessage]
      )
    }
    return value[captureRange]
  }
}
