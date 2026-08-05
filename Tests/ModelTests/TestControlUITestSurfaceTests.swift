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
      "Registration Needs Repair",
      "Approval Required",
      "Repair Failed",
      "Updating",
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

  func testCanonicalExecutableProofUsesTheLaunchedProcessAndExactPath() throws {
    let attachments = try source(
      "Tests/FanCurveUITests/FanCurveUITestDriver+Attachments.swift"
    )
    let content = try source("Sources/Views/ContentView.swift")

    expect(content).to(
      contain(
        ".accessibilityValue(String(ProcessInfo.processInfo.processIdentifier))"
      ))
    expect(attachments).to(contain("processIdentifierValue = mainWindow.value"))
    expect(attachments).to(
      contain(
        "processIdentifier: launchedProcessIdentifier"
      ))
    expect(attachments).to(
      contain(
        "runningApplication.bundleIdentifier == generatedAppBundleID"
      ))
    expect(attachments).to(
      contain(
        #"fileURLWithPath: "/Applications/Fan Curve.app/Contents/MacOS/FanCurve""#
      ))
    expect(attachments).to(contain("resolvedExecutableURL == canonicalExecutableURL"))
    expect(attachments).toNot(contain("resolvedPath.hasPrefix"))
  }

  func testControlScenarioObservesAndRestoresPersistentStateThroughXCUI() throws {
    let controls = try source("Tests/FanCurveUITests/FanCurveUIControlTests.swift")
    let assertions = try source(
      "Tests/FanCurveUITests/FanCurveUITestDriver+Assertions.swift"
    )

    expect(assertions).to(contain("func booleanControlValue("))
    expect(assertions).to(contain("func setBooleanControl("))
    expect(assertions).to(contain("func controlPointFrames("))
    expect(assertions).to(contain("func restoreControlPointFrames("))
    expect(controls).to(contain("registerCleanup"))
    expect(controls).to(contain("restoreDashboardPersistentState"))
    expect(controls).to(contain("restoreSettingsPersistentState"))
    expect(controls).toNot(contain("UserDefaults"))
  }

  func testRunnerValidatesTheInstalledAgentSessionBeforeXCTest() throws {
    let runner = try source("Scripts/RunFanCurveUITests.sh")
    let validator = try source("Scripts/ValidateFanCurveUITestAgentSession.swift")

    expect(runner).to(contain("ValidateFanCurveUITestAgentSession.swift"))
    expect(runner).to(contain("UI_TEST_SESSION_PATH"))
    expect(validator).to(contain("Contents/Library/LaunchAgents/agent-launchd.plist"))
    expect(validator).to(contain("EnvironmentVariables"))
    expect(validator).to(contain("FANCURVE_TEST_CONTROL_PATH"))
    expect(validator).to(contain("expectedSessionPath"))
  }

  func testContractTestsDoNotBuildAUIRunnerAndUICompilationHasItsOwnTarget() throws {
    let helper = try source(
      "Tuist/ProjectDescriptionHelpers/FanCurveUITestProject.swift"
    )
    let makefile = try source("Makefile")

    expect(helper).to(
      contain(
        #"buildAction: .buildAction(targets: [.target("TestControlContractTests")])"#
      ))
    expect(helper).toNot(
      contain(
        #"targets: [.target("TestControlContractTests"), .target("FanCurveUITests")]"#
      ))
    expect(makefile).to(contain("test-ui-build:"))
    expect(makefile).to(contain("--scheme FanCurveUITests"))
  }

  func testAboutWindowAndContentUseDistinctAccessibilityIdentifiers() throws {
    let identifiers = try source("Sources/Common/AppAccessibilityIdentifier.swift")
    let app = try source("Sources/App/FanCurveApp.swift")
    let about = try source("Sources/Views/AboutContentView.swift")

    expect(identifiers).to(contain(#"aboutContent = "app.about-content""#))
    expect(app).to(contain("Application.aboutWindow"))
    expect(about).to(contain("Application.aboutContent"))
    expect(about).toNot(contain("Application.aboutWindow"))
  }

  func testRuntimeScenarioSeparatesHelperReachabilityFromHardwareFailure() throws {
    let runtime = try source("Tests/FanCurveUITests/FanCurveUIRuntimeTests.swift")

    expect(runtime).to(contain("verifyHelperUnreachable"))
    expect(runtime).to(contain("helperReachable: false"))
    expect(runtime).to(contain("verifyHardwareOperationFailure"))
    expect(runtime).to(contain("hardwareOperation: .fail"))
    expect(runtime).to(contain("helperReachable: true"))
  }

  func testEverySetupMutationFailureAssertsItsExactVisibleMessage() throws {
    let setup = try source("Tests/FanCurveUITests/FanCurveUISetupTests.swift")

    for expectedMessage in [
      "Background registration refused",
      "System Settings unavailable",
      "Helper registration refused",
      "Helper repair refused",
    ] {
      expect(setup).to(
        contain(
          "verifyVisibleError(driver, message: \"\(expectedMessage)\")"
        ))
    }
    expect(
      self.occurrenceCount(
        of: #"verifyVisibleError(driver, message: "System Settings unavailable")"#,
        in: setup
      )) == 2
  }

  func testEveryProtocolFaultAssertsTypedEvidenceAndVisibleState() throws {
    let faults = try source("Tests/FanCurveUITests/FanCurveUIProtocolFaultTests.swift")
    let state = try source("Sources/TestControl/TestControlState.swift")

    for expectedState in [
      ".commandRejected",
      ".commandReplyMalformed",
      ".initialStateRejected",
      ".runtimeEventAccepted",
      ".runtimeEventRejected",
      ".disconnected",
      ".reconnectScheduled",
    ] {
      expect(faults).to(contain(expectedState))
    }
    expect(faults).to(
      contain(
        ".processLifecycle(process: .agent, phase: .terminated)"
      ))
    expect(faults).to(contain("verifyDashboardPreserved"))
    expect(state).to(contain("case commandRejected"))
    expect(state).to(contain("case commandReplyMalformed"))
    expect(state).to(contain("case initialStateRejected"))
  }

  func testScenarioCapturesArtifactsWhenDriverInitializationFails() throws {
    let scenario = try source("Tests/FanCurveUITests/FanCurveUIScenario.swift")
    let attachments = try source(
      "Tests/FanCurveUITests/FanCurveUITestDriver+Attachments.swift"
    )

    expect(scenario).to(contain("catch"))
    expect(scenario).to(contain("attachInitializationFailureArtifacts"))
    expect(attachments).to(contain("static func attachInitializationFailureArtifacts("))
    expect(attachments).to(contain("XCUIScreen.main.screenshot()"))
    expect(attachments).to(contain("FANCURVE_TEST_CONTROL_PATH"))
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

  private func occurrenceCount(of needle: String, in value: String) -> Int {
    value.components(separatedBy: needle).count - 1
  }
}
