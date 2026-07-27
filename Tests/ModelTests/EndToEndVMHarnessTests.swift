//
//  EndToEndVMHarnessTests.swift
//  ModelTests
//
//  Created by Claude Opus 5 (1M context) <noreply@anthropic.com> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

private struct EndToEndVMProcessResult {
  let status: Int32
  let standardOutput: String
  let standardError: String
}

private let releaseHostContracts = [
  "git status --porcelain",
  "git verify-commit HEAD",
  "git cat-file commit HEAD",
  "gpgsig",
  "git ls-files --stage",
  "make app CONFIGURATION=Release",
  "make test-service-smoke-build",
  #"requiredEnvironment("DEVELOPMENT_TEAM")"#,
  "host-release/Fan Curve.app",
  "host-release/source-files.txt",
  "host-release/source-commit.txt",
]
private let releaseGuestContracts = [
  "verify_release_source",
  "install-e2e-release-app",
  "test-service-smoke-prebuilt",
  "FANCURVE_E2E_RELEASE_APP_SOURCE",
  "FANCURVE_E2E_RELEASE_XCTESTRUN_PATH",
  "H3BMXM4W7H",
]
private let forbiddenSigningSecretTransfers = ["security export", "security import", ".p12", "PRIVATE_KEY"]
// A hardcoded VM tool name in the generic runner is exactly the coupling this
// rework removes; any of these strings appearing there means a provider detail
// leaked out of Scripts/vm-providers/tart-provider.sh.
private let forbiddenGenericRunnerLeaks = [
  "tart run", "tart clone", "tart stop", "tart delete", "tart ip",
  "tart list", "sshpass", "TART_SSH_USER", "TART_SSH_PASSWORD", "TART_KEEP_VM",
]

// MARK: - EndToEndVMHarnessTests

final class EndToEndVMHarnessTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func setUpWithError() throws {
    try super.setUpWithError()
    temporaryDirectories = []
  }

  override func tearDownWithError() throws {
    for directory in temporaryDirectories
    where FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
    try super.tearDownWithError()
  }

  func testInstanceNameValidationAcceptsOnlyDisposableFanCurveNames() throws {
    let accepted = try runHostRunner(
      arguments: [
        "validate-instance-name",
        "fancurve-e2e-run-20260727T031500Z-a1b2c3d4-debug",
      ]
    )
    expect(accepted.status) == 0
    expect(accepted.standardOutput).to(contain("instance_name_valid"))

    for rejectedName in [
      "fancurve-e2e-20260725",
      "fancurve-release-smoke-20260726-194146",
      "fancurve-e2e-run-../../fancurve-e2e-20260725",
      "other-project-e2e-run-20260727T031500Z-a1b2c3d4-debug",
    ] {
      let rejected = try runHostRunner(arguments: ["validate-instance-name", rejectedName])
      expect(rejected.status) != 0
      expect(rejected.standardError).to(contain("refusing unsafe disposable instance name"))
    }
  }

  func testGenericRunnerResolvesItsProviderFromConfiguration() throws {
    let harnessURL = repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift")
    let source = try String(contentsOf: harnessURL, encoding: .utf8)

    for forbidden in forbiddenGenericRunnerLeaks {
      expect(source).toNot(
        contain(forbidden),
        description: "generic runner leaked a provider-specific detail: \(forbidden)"
      )
    }
    expect(source).to(contain(#"requiredEnvironment("E2E_VM_PROVIDER")"#))
  }

  func testTartProviderRequiresAGuestPasswordWithNoHardcodedFallback() throws {
    let providerURL = repositoryURL.appendingPathComponent(
      "Scripts/vm-providers/tart-provider.sh"
    )
    let source = try String(contentsOf: providerURL, encoding: .utf8)

    expect(source).to(contain(#"SSHPASS="$password""#))
    expect(source).to(contain(#""IdentitiesOnly=yes""#))
    expect(source).to(contain(#""PreferredAuthentications=password""#))
    expect(source).toNot(contain(#""BatchMode=yes""#))
    expect(source).toNot(contain(#"E2E_VM_SSH_PASSWORD:-admin"#))
    expect(source).to(contain("E2E_VM_SSH_PASSWORD is required"))
  }

  func testGuestValidationRejectsAWritableSourceMount() throws {
    let guestScriptURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
    let guestScript = try String(contentsOf: guestScriptURL, encoding: .utf8)
    let sourceDirectory = try makeTemporaryDirectory(name: "source")
    let artifactsDirectory = try makeTemporaryDirectory(name: "artifacts")
    let workspaceDirectory = try makeTemporaryDirectory(name: "workspace")

    let result = try runGuestScript(
      arguments: ["validate-environment", "debug"],
      environment: guestEnvironment(
        sourceDirectory: sourceDirectory,
        artifactsDirectory: artifactsDirectory,
        workspaceDirectory: workspaceDirectory
      )
    )

    expect(guestScript).to(contain(".e2e-read-only-probe-"))
    expect(guestScript).to(contain(#"/usr/bin/touch "$probe_path""#))
    expect(result.status) != 0
    expect(result.standardError).to(contain("source mount must be read-only"))
    expect(
      try FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path)
    ).to(beEmpty())
  }

  func testDesktopProbeDiscardsLargeLaunchctlOutput() throws {
    let harnessURL = repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift")
    let source = try String(contentsOf: harnessURL, encoding: .utf8)

    expect(source).to(
      contain(#"remoteCommand: "/bin/launchctl print gui/\(userID) >/dev/null""#)
    )
  }

  func testGuestUserIDProbeUsesTheReadinessRetry() throws {
    let harnessURL = repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift")
    let source = try String(contentsOf: harnessURL, encoding: .utf8)

    expect(source).to(contain(#"name: "guest user ID""#))
    expect(source).to(contain("let userIDResult = try waitForCondition("))
  }

  func testDebugWorkflowInvokesTheTestControlBuildTarget() throws {
    let guestScriptURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
    let source = try String(contentsOf: guestScriptURL, encoding: .utf8)

    expect(source).to(
      contain(
        """
        run_make test-control-build \\
                CODE_SIGN_IDENTITY="-" \\
                CODE_SIGN_STYLE="Manual" \\
                test-control-build \\
        """
      )
    )
  }

  func testGuestExposesPreinstalledHomebrewToolsToMake() throws {
    let guestScriptURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
    let source = try String(contentsOf: guestScriptURL, encoding: .utf8)

    expect(source).to(
      contain(
        #"export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin""#
      )
    )
    expect(source).to(contain("command -v tuist"))
  }

  func testGuestBootstrapsPinnedSignedTuist() throws {
    let guestScriptURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
    let source = try String(contentsOf: guestScriptURL, encoding: .utf8)

    expect(source).to(contain(#"TUIST_VERSION="4.195.14""#))
    expect(source).to(contain(#"releases/download/$TUIST_VERSION/tuist.zip"#))
    expect(source).to(contain("CaptureCodeSigningEvidence.swift"))
    expect(source).to(contain("U6LC622NKF"))
    expect(source).to(contain("prepare_tuist"))
  }

  func testGuestInstallsRepositoryAnalysisToolsBeforeBuild() throws {
    let guestScriptURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
    let source = try String(contentsOf: guestScriptURL, encoding: .utf8)

    let analysisRange = try XCTUnwrap(
      source.range(of: "run_make analysis-tools install-analysis-tools")
    )
    let debugRange = try XCTUnwrap(source.range(of: "run_debug_workflow", options: .backwards))
    expect(analysisRange.lowerBound < debugRange.lowerBound) == true
  }

  func testGuestUsesLocalSigningOnlyForDebug() throws {
    let guestScriptURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
    let source = try String(contentsOf: guestScriptURL, encoding: .utf8)

    expect(source).toNot(contain(#"export CODE_SIGN_IDENTITY="-""#))
    expect(source.components(separatedBy: #"CODE_SIGN_IDENTITY="-""#).count - 1) == 3
    expect(source.components(separatedBy: #"CODE_SIGN_STYLE="Manual""#).count - 1) == 3
  }
}

// MARK: - Release Harness Contracts

extension EndToEndVMHarnessTests {
  func testReleaseArtifactsComeFromTheSignedHostCommit() throws {
    let hostSource = try String(
      contentsOf: repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift"),
      encoding: .utf8
    )
    let guestSource = try String(
      contentsOf: repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh"),
      encoding: .utf8
    )
    let makefile = try String(
      contentsOf: repositoryURL.appendingPathComponent("Makefile"),
      encoding: .utf8
    )

    for requiredHostContract in releaseHostContracts {
      expect(hostSource).to(
        contain(requiredHostContract),
        description: "Missing host Release contract: \(requiredHostContract)"
      )
    }
    for requiredGuestContract in releaseGuestContracts {
      expect(guestSource).to(
        contain(requiredGuestContract),
        description: "Missing guest Release contract: \(requiredGuestContract)"
      )
    }
    expect(guestSource).toNot(contain("release-install install-app"))
    expect(makefile).to(contain("toolchain build-for-testing"))
    expect(makefile).to(contain("test-service-smoke-prebuilt:"))
    for forbiddenSecretTransfer in forbiddenSigningSecretTransfers {
      expect(hostSource.localizedCaseInsensitiveContains(forbiddenSecretTransfer)) == false
      expect(guestSource.localizedCaseInsensitiveContains(forbiddenSecretTransfer)) == false
    }
  }

  func testMakeTargetsAreProviderAgnosticallyNamed() throws {
    let makefile = try String(
      contentsOf: repositoryURL.appendingPathComponent("Makefile"),
      encoding: .utf8
    )

    for requiredTarget in ["e2e-debug:", "e2e-release-smoke:", "test-e2e-harness:"] {
      expect(makefile).to(contain(requiredTarget))
    }
    for legacyTartTarget in ["tart-e2e-debug:", "tart-e2e-release-smoke:"] {
      expect(makefile).toNot(contain(legacyTartTarget))
    }
    expect(makefile).to(contain("E2E_VM_PROVIDER ?="))
  }

  func testGuestCopyUsesGuestLocalStorageWithoutMutatingTheSource() throws {
    let sourceDirectory = try makeTemporaryDirectory(name: "source")
    let artifactsDirectory = try makeTemporaryDirectory(name: "artifacts")
    let workspaceDirectory = try makeTemporaryDirectory(name: "workspace")
    let sourceMarker = sourceDirectory.appendingPathComponent("source-marker.txt")
    try Data("mounted-source\n".utf8).write(to: sourceMarker, options: .atomic)
    let staleBuild = sourceDirectory.appendingPathComponent(
      "Tuist/.build/stale-host-path.txt"
    )
    try FileManager.default.createDirectory(
      at: staleBuild.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("/Users/host/worktree\n".utf8).write(to: staleBuild, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555],
      ofItemAtPath: sourceDirectory.path
    )

    let result = try runGuestScript(
      arguments: ["copy-source", "debug"],
      environment: guestEnvironment(
        sourceDirectory: sourceDirectory,
        artifactsDirectory: artifactsDirectory,
        workspaceDirectory: workspaceDirectory
      )
    )

    expect(result.status) == 0
    let copiedMarker = workspaceDirectory.appendingPathComponent(
      "macos-fan-curve/source-marker.txt"
    )
    expect(FileManager.default.fileExists(atPath: copiedMarker.path)) == true
    let copiedStaleBuild = workspaceDirectory.appendingPathComponent(
      "macos-fan-curve/Tuist/.build/stale-host-path.txt"
    )
    expect(FileManager.default.fileExists(atPath: copiedStaleBuild.path)) == false
    try Data("guest-local\n".utf8).write(to: copiedMarker, options: .atomic)
    expect(try String(contentsOf: sourceMarker, encoding: .utf8)) == "mounted-source\n"
  }

  func testUIResultCollectionRemovesAStaleDestinationBeforeLookingForFreshOutput() throws {
    let logsDirectory = try makeTemporaryDirectory(name: "logs")
    let outputDirectory = try makeTemporaryDirectory(name: "output")
    let resultBundle = outputDirectory.appendingPathComponent(
      "FanCurveUITests.xcresult",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: resultBundle, withIntermediateDirectories: false)
    try Data("stale\n".utf8).write(
      to: resultBundle.appendingPathComponent("stale.txt"),
      options: .atomic
    )

    let result = try runProcess(
      executableURL: repositoryURL.appendingPathComponent("Scripts/RunFanCurveUITests.sh"),
      arguments: ["collect-result-bundle", logsDirectory.path, resultBundle.path]
    )

    expect(result.status) != 0
    expect(FileManager.default.fileExists(atPath: resultBundle.path)) == false
    expect(result.standardError).to(contain("no fresh FanCurveUITests result bundle"))
  }

  func testReleaseSmokeProvesCanonicalProcessAndReconnectEvidence() throws {
    let smokeDriverURL = repositoryURL.appendingPathComponent(
      "Tests/FanCurveServiceSmokeTests/FanCurveServiceSmokeDriver.swift"
    )
    let source = try String(contentsOf: smokeDriverURL, encoding: .utf8)

    for requiredContract in [
      "NSRunningApplication.runningApplications",
      "agentLastTick",
      "agent_client.connection.disconnected",
      "agent_client.connection.ready",
    ] {
      expect(source).to(contain(requiredContract))
    }
  }

  private func runHostRunner(arguments: [String]) throws -> EndToEndVMProcessResult {
    try runProcess(
      executableURL: repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift"),
      arguments: arguments
    )
  }

  private func runGuestScript(
    arguments: [String],
    environment: [String: String]
  ) throws -> EndToEndVMProcessResult {
    try runProcess(
      executableURL: repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh"),
      arguments: arguments,
      environment: environment
    )
  }

  private func runProcess(
    executableURL: URL,
    arguments: [String],
    environment: [String: String] = [:]
  ) throws -> EndToEndVMProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = repositoryURL
    process.environment = ProcessInfo.processInfo.environment.merging(
      environment
    ) { _, newValue in newValue }

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError
    try process.run()
    process.waitUntilExit()

    let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
    let output = try XCTUnwrap(String(bytes: outputData, encoding: .utf8))
    let error = try XCTUnwrap(String(bytes: errorData, encoding: .utf8))
    return EndToEndVMProcessResult(
      status: process.terminationStatus,
      standardOutput: output,
      standardError: error
    )
  }

  private func guestEnvironment(
    sourceDirectory: URL,
    artifactsDirectory: URL,
    workspaceDirectory: URL
  ) -> [String: String] {
    [
      "FANCURVE_E2E_SOURCE_MOUNT": sourceDirectory.path,
      "FANCURVE_E2E_ARTIFACT_MOUNT": artifactsDirectory.path,
      "FANCURVE_E2E_GUEST_WORKSPACE": workspaceDirectory.path,
      "FANCURVE_E2E_RUN_ID": "test-run",
    ]
  }

  private func makeTemporaryDirectory(name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "FanCurveE2EHarness-\(name)-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    temporaryDirectories.append(directory)
    return directory
  }

  private var repositoryURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
