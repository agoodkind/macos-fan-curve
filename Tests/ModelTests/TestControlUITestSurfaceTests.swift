//
//  TestControlUITestSurfaceTests.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

final class TestControlUITestSurfaceTests: XCTestCase {
  func testUITestTargetOwnsSharedContractsWithoutAnAppDependency() throws {
    let helper = try source(
      "Tuist/ProjectDescriptionHelpers/FanCurveUITestProject.swift"
    )

    expect(helper).to(contain("product: .uiTests"))
    expect(helper).to(contain("\"Tests/FanCurveUITests/**\""))
    expect(helper).to(contain("\"Sources/Common/AppAccessibilityIdentifier.swift\""))
    expect(helper).to(contain("\"Sources/TestControl/**\""))
    expect(helper).to(contain(".external(name: \"AppLog\")"))
    expect(helper).toNot(contain(".target(name: \"FanCurve\")"))
    expect(helper).to(contain("configuration: \"Debug\""))
    expect(helper).to(contain("\"TEST_HOST\": \"\""))
    expect(helper).to(contain("\"TEST_TARGET_NAME\": \"\""))
  }

  func testMakeTargetRunsHostlessUITestsWithExplicitSessionAndResultPaths() throws {
    let makefile = try source("Makefile")
    let helper = try source(
      "Tuist/ProjectDescriptionHelpers/FanCurveUITestProject.swift"
    )
    let runner = try source("Scripts/RunFanCurveUITests.sh")

    expect(makefile).to(contain("test-ui:"))
    expect(makefile).to(contain("UI_TEST_SESSION_PATH"))
    expect(makefile).to(contain("UI_TEST_RESULT_BUNDLE_PATH"))
    expect(makefile).to(contain("Scripts/RunFanCurveUITests.sh"))
    expect(helper).to(contain("FANCURVE_TEST_CONTROL_PATH"))
    expect(runner).to(contain("toolchain test"))
    expect(runner).to(contain("--scheme FanCurveUITests"))
    expect(runner).to(contain("/Applications/Fan Curve.app"))
    expect(runner).to(contain("Test-FanCurveUITests-*.xcresult"))
  }

  func testReleaseAppSchemeDoesNotBuildOrRunUITests() throws {
    let project = try source("Project.swift")
    let appScheme = try firstCapture(
      pattern:
        #"(?ms)\.scheme\(\n\s*name: appName,(.*?)archiveAction: \.archiveAction\(configuration: "Release"\)"#,
      in: project,
      failureMessage: "Missing FanCurve app scheme"
    )

    expect(String(appScheme)).to(contain("buildAction: .buildAction(targets: [.target(appName)])"))
    expect(String(appScheme)).toNot(contain("FanCurveUITests"))
  }

  func testScenarioSourcesCoverTheRequiredUIAndProtocolBoundaries() throws {
    let setup = try source("Tests/FanCurveUITests/FanCurveUISetupTests.swift")
    let runtime = try source("Tests/FanCurveUITests/FanCurveUIRuntimeTests.swift")
    let controls = try source("Tests/FanCurveUITests/FanCurveUIControlTests.swift")
    let faults = try source("Tests/FanCurveUITests/FanCurveUIProtocolFaultTests.swift")

    for expectedState in [
      "Enable Background Control",
      "Allow Fan Curve in Background",
      "Install the System Helper",
      "Allow the System Helper",
    ] {
      expect(setup).to(contain(expectedState))
    }
    for expectedState in [
      "Telemetry Unavailable",
      "Telemetry Stale",
      "Fan Control Preempted",
      "All systems go",
    ] {
      expect(runtime).to(contain(expectedState))
    }
    for expectedIdentifier in [
      "Dashboard.fanControl",
      "Dashboard.boost",
      "Settings.applyInBackground",
      "Settings.ownershipDisclosure",
      "Learn.confirmProbe",
      "Application.quitCommand",
    ] {
      expect(controls).to(contain(expectedIdentifier))
    }
    for expectedFault in [
      ".malformedInitialState",
      ".duplicateEvent",
      ".malformedEvent",
      ".invalidation",
      ".interruption",
      ".reconnect",
      ".rejectedCommand",
      ".malformedReply",
    ] {
      expect(faults).to(contain(expectedFault))
    }
    expect(faults).to(contain("injectOutOfOrderRevision"))
  }

  private func source(_ relativePath: String) throws -> String {
    let sourceURL = repositoryURL.appendingPathComponent(relativePath)
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }

  private var repositoryURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func firstCapture(
    pattern: String,
    in value: String,
    failureMessage: String
  ) throws -> Substring {
    let expression = try NSRegularExpression(pattern: pattern)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = expression.firstMatch(in: value, range: range) else {
      throw NSError(
        domain: "TestControlUITestSurfaceTests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: failureMessage]
      )
    }
    guard let captureRange = Range(match.range(at: 1), in: value) else {
      throw NSError(
        domain: "TestControlUITestSurfaceTests",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: failureMessage]
      )
    }
    return value[captureRange]
  }
}
