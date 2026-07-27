#!/usr/bin/env swift

import Foundation

private struct ContractTestFailure: Error, CustomStringConvertible {
  let description: String
}

private struct ProcessResult {
  let status: Int32
  let standardOutput: String
  let standardError: String
}

private let fileManager = FileManager.default
private let repositoryURL = URL(
  fileURLWithPath: fileManager.currentDirectoryPath,
  isDirectory: true
).standardizedFileURL
private var temporaryDirectories: [URL] = []

// A hardcoded VM tool name in the generic runner is exactly the coupling this
// rework removes; any of these strings appearing there means a provider detail
// leaked out of Scripts/vm-providers/tart-provider.sh.
private let forbiddenGenericRunnerLeaks = [
  "tart run", "tart clone", "tart stop", "tart delete", "tart ip",
  "tart list", "sshpass", "TART_SSH_USER", "TART_SSH_PASSWORD", "TART_KEEP_VM",
]

private func fail(_ message: String) throws -> Never {
  throw ContractTestFailure(description: message)
}

private func makeTemporaryDirectory(name: String) throws -> URL {
  let directory = fileManager.temporaryDirectory.appendingPathComponent(
    "FanCurveE2EContract-\(name)-\(UUID().uuidString)",
    isDirectory: true
  )
  try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
  temporaryDirectories.append(directory)
  return directory
}

private func runProcess(
  executableURL: URL,
  arguments: [String],
  environment: [String: String] = [:]
) throws -> ProcessResult {
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
  return ProcessResult(
    status: process.terminationStatus,
    standardOutput: String(
      decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    ),
    standardError: String(
      decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
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
    "FANCURVE_E2E_RUN_ID": "contract-test",
  ]
}

private func testInstanceNameValidation() throws {
  let scriptURL = repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift")
  let valid = try runProcess(
    executableURL: scriptURL,
    arguments: [
      "validate-instance-name",
      "fancurve-e2e-run-20260727T031500Z-a1b2c3d4-debug",
    ]
  )
  guard valid.status == 0, valid.standardOutput.contains("instance_name_valid") else {
    try fail("valid disposable instance name was rejected: \(valid.standardError)")
  }
  for rejectedName in [
    "fancurve-e2e-20260725",
    "fancurve-e2e-run-../../fancurve-e2e-20260725",
    "other-project-e2e-run-20260727T031500Z-a1b2c3d4-debug",
  ] {
    let result = try runProcess(
      executableURL: scriptURL,
      arguments: ["validate-instance-name", rejectedName]
    )
    guard
      result.status != 0,
      result.standardError.contains("refusing unsafe disposable instance name")
    else {
      try fail("unsafe instance name was accepted: \(rejectedName)")
    }
  }
}

private func testGenericRunnerNamesNoSpecificVMTool() throws {
  let harnessURL = repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift")
  let source = try String(contentsOf: harnessURL, encoding: .utf8)
  for forbidden in forbiddenGenericRunnerLeaks {
    guard !source.contains(forbidden) else {
      try fail("generic runner leaked a provider-specific detail: \(forbidden)")
    }
  }
  guard source.contains(#"requiredEnvironment("E2E_VM_PROVIDER")"#) else {
    try fail("generic runner does not resolve its VM provider from configuration")
  }
}

private func testProviderOwnsCredentialsWithNoHardcodedFallback() throws {
  let providerURL = repositoryURL.appendingPathComponent(
    "Scripts/vm-providers/tart-provider.sh"
  )
  let source = try String(contentsOf: providerURL, encoding: .utf8)
  guard source.contains(#"SSHPASS="$password""#) else {
    try fail("Tart provider does not pass the guest password through the sshpass environment")
  }
  guard source.contains(#""IdentitiesOnly=yes""#), source.contains(#""PreferredAuthentications=password""#)
  else {
    try fail("Tart provider SSH may exhaust unrelated host identities before password auth")
  }
  guard !source.contains(#""BatchMode=yes""#) else {
    try fail("Tart provider disables password authentication with BatchMode")
  }
  guard !source.contains(#"E2E_VM_SSH_PASSWORD:-admin"#) else {
    try fail("Tart provider must not fall back to a hardcoded guest password default")
  }
  guard source.contains("E2E_VM_SSH_PASSWORD is required") else {
    try fail("Tart provider does not fail loudly when the guest password is absent")
  }
}

private func testDesktopProbeDiscardsLargeLaunchctlOutput() throws {
  let harnessURL = repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift")
  let source = try String(contentsOf: harnessURL, encoding: .utf8)
  guard
    source.contains(#"remoteCommand: "/bin/launchctl print gui/\(userID) >/dev/null""#)
  else {
    try fail("desktop readiness may deadlock on unread launchctl output")
  }
}

private func testGuestUserIDProbeUsesTheReadinessRetry() throws {
  let harnessURL = repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift")
  let source = try String(contentsOf: harnessURL, encoding: .utf8)
  guard
    source.contains(#"name: "guest user ID""#),
    source.contains("let userIDResult = try waitForCondition(")
  else {
    try fail("guest user ID lookup does not tolerate transient reachability failures")
  }
}

private func testDebugWorkflowInvokesTheTestControlBuildTarget() throws {
  let guestURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
  let source = try String(contentsOf: guestURL, encoding: .utf8)
  guard
    source.contains(
      """
      run_make test-control-build \\
              CODE_SIGN_IDENTITY="-" \\
              CODE_SIGN_STYLE="Manual" \\
              test-control-build \\
      """
    )
  else {
    try fail("Debug guest workflow labels but does not invoke test-control-build")
  }
}

private func testGuestExposesPreinstalledHomebrewToolsToMake() throws {
  let guestURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
  let source = try String(contentsOf: guestURL, encoding: .utf8)
  guard
    source.contains(
      #"export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin""#
    ),
    source.contains("command -v tuist")
  else {
    try fail("guest workflow does not expose or record its Tuist executable")
  }
}

private func testGuestBootstrapsPinnedSignedTuist() throws {
  let guestURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
  let source = try String(contentsOf: guestURL, encoding: .utf8)
  for requiredContract in [
    #"TUIST_VERSION="4.195.14""#,
    #"releases/download/$TUIST_VERSION/tuist.zip"#,
    "CaptureCodeSigningEvidence.swift",
    "U6LC622NKF",
    "prepare_tuist",
  ] {
    guard source.contains(requiredContract) else {
      try fail("guest Tuist bootstrap omitted contract: \(requiredContract)")
    }
  }
}

private func testGuestInstallsRepositoryAnalysisToolsBeforeBuild() throws {
  let guestURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
  let source = try String(contentsOf: guestURL, encoding: .utf8)
  guard
    let analysisRange = source.range(
      of: "run_make analysis-tools install-analysis-tools"
    ),
    let debugRange = source.range(of: "run_debug_workflow", options: .backwards),
    analysisRange.lowerBound < debugRange.lowerBound
  else {
    try fail("guest build starts before repository analysis tools are installed")
  }
}

private func testGuestUsesLocalSigningOnlyForDebug() throws {
  let guestURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
  let source = try String(contentsOf: guestURL, encoding: .utf8)
  guard
    !source.contains(#"export CODE_SIGN_IDENTITY="-""#),
    source.components(separatedBy: #"CODE_SIGN_IDENTITY="-""#).count - 1 == 3,
    source.components(separatedBy: #"CODE_SIGN_STYLE="Manual""#).count - 1 == 3
  else {
    try fail("ad hoc signing is not scoped to the three Debug Make invocations")
  }
}

private func testReleaseArtifactsComeFromTheSignedHostCommit() throws {
  let hostHarnessURL = repositoryURL.appendingPathComponent("Scripts/EndToEndVM.swift")
  let guestScriptURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
  let makefileURL = repositoryURL.appendingPathComponent("Makefile")
  let hostSource = try String(contentsOf: hostHarnessURL, encoding: .utf8)
  let guestSource = try String(contentsOf: guestScriptURL, encoding: .utf8)
  let makefile = try String(contentsOf: makefileURL, encoding: .utf8)

  for requiredHostContract in [
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
  ] {
    guard hostSource.contains(requiredHostContract) else {
      try fail("host Release preparation omitted contract: \(requiredHostContract)")
    }
  }
  for requiredGuestContract in [
    "verify_release_source",
    "install-e2e-release-app",
    "test-service-smoke-prebuilt",
    "FANCURVE_E2E_RELEASE_APP_SOURCE",
    "FANCURVE_E2E_RELEASE_XCTESTRUN_PATH",
    "H3BMXM4W7H",
  ] {
    guard guestSource.contains(requiredGuestContract) else {
      try fail("guest Release workflow omitted contract: \(requiredGuestContract)")
    }
  }
  guard !guestSource.contains("release-install install-app") else {
    try fail("guest Release workflow still builds an unsigned local app")
  }
  guard makefile.contains("toolchain build-for-testing") else {
    try fail("Release smoke staging does not produce a portable xctestrun")
  }
  guard makefile.contains("test-service-smoke-prebuilt:") else {
    try fail("Makefile omits the canonical prebuilt Release smoke entry point")
  }
  for forbiddenSecretTransfer in ["security export", "security import", ".p12", "PRIVATE_KEY"] {
    guard
      !hostSource.localizedCaseInsensitiveContains(forbiddenSecretTransfer),
      !guestSource.localizedCaseInsensitiveContains(forbiddenSecretTransfer)
    else {
      try fail("Release workflow may transfer signing secrets: \(forbiddenSecretTransfer)")
    }
  }
}

private func testMakeTargetsAreProviderAgnosticallyNamed() throws {
  let makefileURL = repositoryURL.appendingPathComponent("Makefile")
  let makefile = try String(contentsOf: makefileURL, encoding: .utf8)
  for requiredTarget in ["e2e-debug:", "e2e-release-smoke:", "test-e2e-harness:"] {
    guard makefile.contains(requiredTarget) else {
      try fail("Makefile is missing the provider-agnostic target: \(requiredTarget)")
    }
  }
  for legacyTartTarget in ["tart-e2e-debug:", "tart-e2e-release-smoke:"] {
    guard !makefile.contains(legacyTartTarget) else {
      try fail("Makefile still exposes a Tart-named target: \(legacyTartTarget)")
    }
  }
  guard makefile.contains("E2E_VM_PROVIDER ?=") else {
    try fail("Makefile does not default a swappable E2E_VM_PROVIDER")
  }
}

private func testGuestMountAndCopyValidation() throws {
  let scriptURL = repositoryURL.appendingPathComponent("Scripts/e2e-guest.sh")
  let scriptSource = try String(contentsOf: scriptURL, encoding: .utf8)
  guard
    scriptSource.contains(".e2e-read-only-probe-"),
    scriptSource.contains(#"/usr/bin/touch "$probe_path""#)
  else {
    try fail("guest source validation does not prove that writes are denied")
  }
  let sourceDirectory = try makeTemporaryDirectory(name: "source")
  let artifactsDirectory = try makeTemporaryDirectory(name: "artifacts")
  let workspaceDirectory = try makeTemporaryDirectory(name: "workspace")
  let markerURL = sourceDirectory.appendingPathComponent("source-marker.txt")
  try Data("mounted-source\n".utf8).write(to: markerURL, options: .atomic)
  let staleBuildURL = sourceDirectory.appendingPathComponent(
    "Tuist/.build/stale-host-path.txt"
  )
  try fileManager.createDirectory(
    at: staleBuildURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try Data("/Users/host/worktree\n".utf8).write(to: staleBuildURL, options: .atomic)

  let writableResult = try runProcess(
    executableURL: scriptURL,
    arguments: ["validate-environment", "debug"],
    environment: guestEnvironment(
      sourceDirectory: sourceDirectory,
      artifactsDirectory: artifactsDirectory,
      workspaceDirectory: workspaceDirectory
    )
  )
  guard
    writableResult.status != 0,
    writableResult.standardError.contains("source mount must be read-only")
  else {
    try fail("guest workflow accepted a writable source mount")
  }
  let sourceEntries = try fileManager.contentsOfDirectory(atPath: sourceDirectory.path)
  guard !sourceEntries.contains(where: { $0.hasPrefix(".e2e-read-only-probe-") }) else {
    try fail("read-only source probe left a mutation behind")
  }

  try fileManager.setAttributes(
    [.posixPermissions: 0o555],
    ofItemAtPath: sourceDirectory.path
  )
  let copyResult = try runProcess(
    executableURL: scriptURL,
    arguments: ["copy-source", "debug"],
    environment: guestEnvironment(
      sourceDirectory: sourceDirectory,
      artifactsDirectory: artifactsDirectory,
      workspaceDirectory: workspaceDirectory
    )
  )
  guard copyResult.status == 0 else {
    try fail("guest-local source copy failed: \(copyResult.standardError)")
  }
  let copiedMarkerURL = workspaceDirectory.appendingPathComponent(
    "macos-fan-curve/source-marker.txt"
  )
  guard fileManager.fileExists(atPath: copiedMarkerURL.path) else {
    try fail("guest-local source copy did not contain the source marker")
  }
  let copiedStaleBuildURL = workspaceDirectory.appendingPathComponent(
    "macos-fan-curve/Tuist/.build/stale-host-path.txt"
  )
  guard !fileManager.fileExists(atPath: copiedStaleBuildURL.path) else {
    try fail("guest-local source copied host-derived .build state")
  }
  try Data("guest-local\n".utf8).write(to: copiedMarkerURL, options: .atomic)
  let sourceContents = try String(contentsOf: markerURL, encoding: .utf8)
  guard sourceContents == "mounted-source\n" else {
    try fail("guest-local write mutated the mounted source")
  }
}

private func testStaleUIResultCannotSurvive() throws {
  let logsDirectory = try makeTemporaryDirectory(name: "logs")
  let outputDirectory = try makeTemporaryDirectory(name: "output")
  let resultBundleURL = outputDirectory.appendingPathComponent(
    "FanCurveUITests.xcresult",
    isDirectory: true
  )
  try fileManager.createDirectory(at: resultBundleURL, withIntermediateDirectories: false)
  try Data("stale\n".utf8).write(
    to: resultBundleURL.appendingPathComponent("stale.txt"),
    options: .atomic
  )
  let result = try runProcess(
    executableURL: repositoryURL.appendingPathComponent("Scripts/RunFanCurveUITests.sh"),
    arguments: ["collect-result-bundle", logsDirectory.path, resultBundleURL.path]
  )
  guard result.status != 0 else {
    try fail("result collector succeeded without a fresh result bundle")
  }
  guard !fileManager.fileExists(atPath: resultBundleURL.path) else {
    try fail("stale requested result bundle survived failed collection")
  }
  guard result.standardError.contains("no fresh FanCurveUITests result bundle") else {
    try fail("result collector did not report the missing fresh bundle")
  }
}

private func testSigningEvidenceUsesSecurityFrameworkData() throws {
  let result = try runProcess(
    executableURL: repositoryURL.appendingPathComponent(
      "Scripts/CaptureCodeSigningEvidence.swift"
    ),
    arguments: ["/bin/ls"]
  )
  guard result.status == 0 else {
    try fail("code-signing evidence capture failed: \(result.standardError)")
  }
  guard
    result.standardOutput.contains(#""path""#),
    result.standardOutput.contains(#""authorities""#),
    result.standardOutput.contains(#""designatedRequirement""#),
    result.standardOutput.contains(#""entitlements""#)
  else {
    try fail("code-signing evidence omitted required fields")
  }
}

private func testReleaseSmokeOwnsRealServiceAndWriteSafetyChecks() throws {
  let smokeDriverURL = repositoryURL.appendingPathComponent(
    "Tests/FanCurveServiceSmokeTests/FanCurveServiceSmokeDriver.swift"
  )
  let source = try String(contentsOf: smokeDriverURL, encoding: .utf8)
  for requiredContract in [
    "AppAccessibilityIdentifier.Setup.action",
    "com.apple.systempreferences",
    "launchctl",
    "SIGKILL",
    "NSRunningApplication.runningApplications",
    "agentPID",
    "agentLastTick",
    "AppAccessibilityIdentifier.Dashboard.fanRow(",
    "firstFanIndex",
    "agent_client.connection.disconnected",
    "agent_client.connection.ready",
    "agent.hardware.rpm.requested",
    "smcSetFanRPM",
  ] {
    guard source.contains(requiredContract) else {
      try fail("Release smoke omitted contract: \(requiredContract)")
    }
  }
}

do {
  defer {
    for directory in temporaryDirectories where fileManager.fileExists(atPath: directory.path) {
      try? fileManager.removeItem(at: directory)
    }
  }
  try testInstanceNameValidation()
  try testGenericRunnerNamesNoSpecificVMTool()
  try testProviderOwnsCredentialsWithNoHardcodedFallback()
  try testDesktopProbeDiscardsLargeLaunchctlOutput()
  try testGuestUserIDProbeUsesTheReadinessRetry()
  try testDebugWorkflowInvokesTheTestControlBuildTarget()
  try testGuestExposesPreinstalledHomebrewToolsToMake()
  try testGuestBootstrapsPinnedSignedTuist()
  try testGuestInstallsRepositoryAnalysisToolsBeforeBuild()
  try testGuestUsesLocalSigningOnlyForDebug()
  try testReleaseArtifactsComeFromTheSignedHostCommit()
  try testMakeTargetsAreProviderAgnosticallyNamed()
  try testGuestMountAndCopyValidation()
  try testStaleUIResultCannotSurvive()
  try testSigningEvidenceUsesSecurityFrameworkData()
  try testReleaseSmokeOwnsRealServiceAndWriteSafetyChecks()
  print("EndToEndVMContractTests: ok")
} catch let failure as ContractTestFailure {
  FileHandle.standardError.write(Data("\(failure.description)\n".utf8))
  exit(1)
} catch {
  FileHandle.standardError.write(
    Data("EndToEndVMContractTests failed: \(error.localizedDescription)\n".utf8)
  )
  exit(1)
}
