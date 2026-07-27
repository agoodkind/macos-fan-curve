#!/usr/bin/env swift

import Darwin
import Foundation

// Runs the Debug UI suite or the Release service-smoke suite inside a disposable
// macOS VM. This file holds no VM-tool-specific logic: every VM lifecycle
// operation is delegated to a provider script (E2E_VM_PROVIDER) that speaks the
// verb contract documented in Docs/e2e-vm-provider-contract.md. Swapping the
// provider swaps the backing VM tool without editing this runner.

private enum EndToEndVMMode: String {
  case debug
  case releaseSmoke = "release-smoke"
}

private enum EndToEndVMError: Error, LocalizedError {
  case commandFailed(command: String, status: Int32, error: String)
  case interrupted
  case invalidArguments
  case invalidInstanceName(String)
  case invalidReleaseArtifact(String)
  case missingBaseImage(String)
  case missingRequiredEnvironment(String)
  case releaseRequiresCleanWorkingTree(String)
  case releaseRequiresSignedCommit
  case timeout(condition: String, evidence: String)

  var errorDescription: String? {
    switch self {
    case let .commandFailed(command, status, error):
      return "command failed status=\(status) command=\(command) error=\(error)"
    case .interrupted:
      return "end-to-end VM run interrupted"
    case .invalidArguments:
      return
        "usage: EndToEndVM.swift <debug|release-smoke> or "
        + "EndToEndVM.swift validate-instance-name NAME"
    case .invalidInstanceName(let name):
      return "refusing unsafe disposable instance name: \(name)"
    case .invalidReleaseArtifact(let detail):
      return "invalid host Release artifact: \(detail)"
    case .missingBaseImage(let name):
      return "required immutable base image is missing: \(name)"
    case .missingRequiredEnvironment(let name):
      return "missing required environment variable: \(name)"
    case .releaseRequiresCleanWorkingTree(let status):
      return "Release smoke requires a clean working tree: \(status)"
    case .releaseRequiresSignedCommit:
      return "Release smoke requires HEAD to contain a verifiable gpgsig signature"
    case let .timeout(condition, evidence):
      return "timed out waiting for \(condition); last evidence: \(evidence)"
    }
  }
}

private struct ProcessResult {
  let status: Int32
  let standardOutput: String
  let standardError: String
}

private struct SigningEvidence: Decodable {
  let authorities: [String]
  let teamIdentifier: String
}

private final class EndToEndVMRuntime: @unchecked Sendable {
  private let lock = NSLock()
  private var childProcesses: [ObjectIdentifier: Process] = [:]
  private var interrupted = false

  func track(_ process: Process) {
    lock.withLock {
      childProcesses[ObjectIdentifier(process)] = process
    }
  }

  func untrack(_ process: Process) {
    _ = lock.withLock {
      childProcesses.removeValue(forKey: ObjectIdentifier(process))
    }
  }

  func requestInterruption(signal: Int32) {
    let processes = lock.withLock { () -> [Process] in
      interrupted = true
      return Array(childProcesses.values)
    }
    writeStandardError("e2e-vm: signal=\(signal) action=terminate-children")
    for process in processes where process.isRunning {
      process.terminate()
    }
  }

  func throwIfInterrupted() throws {
    let wasInterrupted = lock.withLock { interrupted }
    if wasInterrupted {
      throw EndToEndVMError.interrupted
    }
  }
}

private let defaultInstancePrefix = "fancurve-e2e-run-"
private let reachableDeadline: TimeInterval = 180
private let readyDeadline: TimeInterval = 120
private let desktopDeadline: TimeInterval = 180
private let pollInterval: TimeInterval = 2

private func writeStandardError(_ message: String) {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
}

private func requiredEnvironment(_ name: String) throws -> String {
  guard
    let value = ProcessInfo.processInfo.environment[name],
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  else {
    throw EndToEndVMError.missingRequiredEnvironment(name)
  }
  return value
}

private func shellQuote(_ value: String) -> String {
  "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
}

private func validateInstanceName(_ name: String, prefix: String) throws {
  let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
  let pattern =
    "^\(escapedPrefix)[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}-(debug|release-smoke)$"
  guard
    name.range(of: pattern, options: .regularExpression) != nil,
    !name.contains("/"),
    !name.contains("..")
  else {
    throw EndToEndVMError.invalidInstanceName(name)
  }
}

private func makeRunIdentifier(mode: EndToEndVMMode) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
  let unique = UUID().uuidString.lowercased().prefix(8)
  return "\(formatter.string(from: Date()))-\(unique)-\(mode.rawValue)"
}

private func makeProcess(
  command: String,
  arguments: [String],
  currentDirectoryURL: URL? = nil,
  environment: [String: String] = [:]
) -> Process {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = [command] + arguments
  process.currentDirectoryURL = currentDirectoryURL
  process.environment = ProcessInfo.processInfo.environment.merging(
    environment
  ) { _, newValue in newValue }
  return process
}

private func runCapture(
  runtime: EndToEndVMRuntime,
  command: String,
  arguments: [String],
  currentDirectoryURL: URL? = nil,
  environment: [String: String] = [:]
) throws -> ProcessResult {
  try runtime.throwIfInterrupted()
  let process = makeProcess(
    command: command,
    arguments: arguments,
    currentDirectoryURL: currentDirectoryURL,
    environment: environment
  )
  let standardOutput = Pipe()
  let standardError = Pipe()
  process.standardOutput = standardOutput
  process.standardError = standardError
  runtime.track(process)
  defer {
    runtime.untrack(process)
  }
  try process.run()
  process.waitUntilExit()
  try runtime.throwIfInterrupted()
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

private func runLogged(
  runtime: EndToEndVMRuntime,
  command: String,
  arguments: [String],
  currentDirectoryURL: URL,
  logURL: URL,
  environment: [String: String] = [:]
) throws {
  try runtime.throwIfInterrupted()
  if !FileManager.default.fileExists(atPath: logURL.path) {
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
  }
  let log = try FileHandle(forWritingTo: logURL)
  try log.seekToEnd()
  defer {
    try? log.close()
  }
  let process = makeProcess(
    command: command,
    arguments: arguments,
    currentDirectoryURL: currentDirectoryURL,
    environment: environment
  )
  process.standardOutput = log
  process.standardError = log
  runtime.track(process)
  defer {
    runtime.untrack(process)
  }
  try process.run()
  process.waitUntilExit()
  try runtime.throwIfInterrupted()
  guard process.terminationStatus == 0 else {
    throw EndToEndVMError.commandFailed(
      command: ([command] + arguments).joined(separator: " "),
      status: process.terminationStatus,
      error: "see \(logURL.path)"
    )
  }
}

private func requireSuccess(_ result: ProcessResult, command: String) throws {
  guard result.status == 0 else {
    let error = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
    throw EndToEndVMError.commandFailed(command: command, status: result.status, error: error)
  }
}

private func waitForCondition(
  runtime: EndToEndVMRuntime,
  name: String,
  deadline: TimeInterval,
  probe: () throws -> ProcessResult
) throws -> ProcessResult {
  let expiresAt = Date().addingTimeInterval(deadline)
  var lastEvidence = "condition has not been probed"
  while Date() < expiresAt {
    try runtime.throwIfInterrupted()
    let result = try probe()
    if result.status == 0 {
      writeStandardError("e2e-vm: wait=\(name) status=ready")
      return result
    }
    let evidence = result.standardError.isEmpty ? result.standardOutput : result.standardError
    lastEvidence = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
    writeStandardError("e2e-vm: wait=\(name) status=pending evidence=\(lastEvidence)")
    Thread.sleep(forTimeInterval: pollInterval)
  }
  throw EndToEndVMError.timeout(condition: name, evidence: lastEvidence)
}

/// One shipped VM tool, resolved from configuration rather than named here. Every
/// lifecycle operation below funnels through this type so a different provider
/// script runs the same orchestration unmodified.
private struct VMProvider {
  let executableURL: URL

  private func invoke(
    runtime: EndToEndVMRuntime,
    arguments: [String]
  ) throws -> ProcessResult {
    try runCapture(runtime: runtime, command: executableURL.path, arguments: arguments)
  }

  func requireImage(runtime: EndToEndVMRuntime, imageID: String) throws {
    let result = try invoke(runtime: runtime, arguments: ["require-image", imageID])
    guard result.status == 0 else {
      throw EndToEndVMError.missingBaseImage(imageID)
    }
  }

  func clone(runtime: EndToEndVMRuntime, imageID: String, instanceName: String) throws {
    let result = try invoke(runtime: runtime, arguments: ["clone", imageID, instanceName])
    try requireSuccess(result, command: "provider clone \(imageID) \(instanceName)")
  }

  func mountPath(runtime: EndToEndVMRuntime, instanceName: String, tag: String) throws -> String {
    let result = try invoke(runtime: runtime, arguments: ["mount-path", instanceName, tag])
    try requireSuccess(result, command: "provider mount-path \(instanceName) \(tag)")
    let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
      throw EndToEndVMError.invalidReleaseArtifact("provider mount-path \(tag) returned no path")
    }
    return path
  }

  func exec(
    runtime: EndToEndVMRuntime,
    instanceName: String,
    remoteCommand: String
  ) throws -> ProcessResult {
    try invoke(runtime: runtime, arguments: ["exec", instanceName, "--", remoteCommand])
  }

  func ready(runtime: EndToEndVMRuntime, instanceName: String) throws -> ProcessResult {
    try invoke(runtime: runtime, arguments: ["ready", instanceName])
  }

  func address(runtime: EndToEndVMRuntime, instanceName: String) -> String {
    (try? invoke(runtime: runtime, arguments: ["address", instanceName]))
      .map { $0.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 } ?? "n/a"
  }

  func describe(runtime: EndToEndVMRuntime) -> String {
    (try? invoke(runtime: runtime, arguments: ["describe"]))
      .map { $0.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "n/a"
  }

  func stop(runtime: EndToEndVMRuntime, instanceName: String) -> ProcessResult? {
    try? invoke(runtime: runtime, arguments: ["stop", instanceName])
  }

  func delete(runtime: EndToEndVMRuntime, instanceName: String) -> ProcessResult? {
    try? invoke(runtime: runtime, arguments: ["delete", instanceName])
  }

  func startProcess(instanceName: String, sourcePath: String, artifactPath: String) -> Process {
    makeProcess(
      command: executableURL.path,
      arguments: [
        "start", instanceName,
        "--source", sourcePath,
        "--artifacts", artifactPath,
      ]
    )
  }
}

private final class EndToEndVMOrchestrator {
  private let runtime: EndToEndVMRuntime
  private let mode: EndToEndVMMode
  private let repositoryURL: URL
  private let artifactURL: URL
  private let runIdentifier: String
  private let instanceName: String
  private let provider: VMProvider
  private let baseImage: String
  private let releaseTeamID: String
  private let keepInstance: Bool
  private var instanceCreated = false
  private var releaseXCTestRunRelativePath: String?
  private var instanceProcess: Process?

  init(runtime: EndToEndVMRuntime, mode: EndToEndVMMode) throws {
    self.runtime = runtime
    self.mode = mode
    repositoryURL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath,
      isDirectory: true
    ).standardizedFileURL
    runIdentifier = makeRunIdentifier(mode: mode)
    let providerPath = try requiredEnvironment("E2E_VM_PROVIDER")
    provider = VMProvider(executableURL: URL(fileURLWithPath: providerPath))
    baseImage = try requiredEnvironment("E2E_VM_BASE_IMAGE")
    releaseTeamID = try requiredEnvironment("DEVELOPMENT_TEAM")
    let instancePrefix =
      ProcessInfo.processInfo.environment["E2E_VM_INSTANCE_PREFIX"] ?? defaultInstancePrefix
    instanceName = "\(instancePrefix)\(runIdentifier)"
    try validateInstanceName(instanceName, prefix: instancePrefix)
    artifactURL = repositoryURL
      .appendingPathComponent("build", isDirectory: true)
      .appendingPathComponent("e2e", isDirectory: true)
      .appendingPathComponent(runIdentifier, isDirectory: true)
    keepInstance = ProcessInfo.processInfo.environment["E2E_VM_KEEP"] == "1"
  }

  func run() throws {
    try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)
    print("e2e-vm: run_id=\(runIdentifier)")
    print("e2e-vm: artifact_directory=\(artifactURL.path)")
    defer {
      cleanup()
      print("e2e-vm: final_artifact_directory=\(artifactURL.path)")
    }

    if mode == .releaseSmoke {
      try prepareReleaseArtifacts()
    }
    try recordHostEnvironment()
    try provider.requireImage(runtime: runtime, imageID: baseImage)
    writeStandardError("e2e-vm: base_image=\(baseImage) status=present preservation=immutable")
    try provider.clone(runtime: runtime, imageID: baseImage, instanceName: instanceName)
    instanceCreated = true
    writeStandardError("e2e-vm: instance=\(instanceName) source=\(baseImage) status=created")
    try startInstance()
    try waitForReachable()
    try waitForReady()
    try waitForDesktop()
    let sourceMount = try provider.mountPath(
      runtime: runtime, instanceName: instanceName, tag: "source"
    )
    let artifactMount = try provider.mountPath(
      runtime: runtime, instanceName: instanceName, tag: "artifacts"
    )
    try runGuestWorkflow(sourceMount: sourceMount, artifactMount: artifactMount)
  }

  private func prepareReleaseArtifacts() throws {
    let workingTree = try runCapture(
      runtime: runtime,
      command: "git",
      arguments: ["status", "--porcelain"],
      currentDirectoryURL: repositoryURL
    )
    try requireSuccess(workingTree, command: "git status --porcelain")
    let status = workingTree.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard status.isEmpty else {
      throw EndToEndVMError.releaseRequiresCleanWorkingTree(status)
    }

    let signature = try runCapture(
      runtime: runtime,
      command: "git",
      arguments: ["verify-commit", "HEAD"],
      currentDirectoryURL: repositoryURL
    )
    try requireSuccess(signature, command: "git verify-commit HEAD")
    let commitObject = try runCapture(
      runtime: runtime,
      command: "git",
      arguments: ["cat-file", "commit", "HEAD"],
      currentDirectoryURL: repositoryURL
    )
    try requireSuccess(commitObject, command: "git cat-file commit HEAD")
    guard
      commitObject.standardOutput.hasPrefix("gpgsig "),
      commitObject.standardOutput.contains("\n ")
    else {
      throw EndToEndVMError.releaseRequiresSignedCommit
    }
    let sourceCommit = try runCapture(
      runtime: runtime,
      command: "git",
      arguments: ["rev-parse", "HEAD"],
      currentDirectoryURL: repositoryURL
    )
    try requireSuccess(sourceCommit, command: "git rev-parse HEAD")
    let sourceFiles = try runCapture(
      runtime: runtime,
      command: "git",
      arguments: ["ls-files", "--stage"],
      currentDirectoryURL: repositoryURL
    )
    try requireSuccess(sourceFiles, command: "git ls-files --stage")

    let releaseRootURL = artifactURL.appendingPathComponent("host-release", isDirectory: true)
    try FileManager.default.createDirectory(
      at: releaseRootURL, withIntermediateDirectories: true
    )
    try Data(sourceCommit.standardOutput.utf8).write(
      to: artifactURL.appendingPathComponent("host-release/source-commit.txt"),
      options: .atomic
    )
    try Data(sourceFiles.standardOutput.utf8).write(
      to: artifactURL.appendingPathComponent("host-release/source-files.txt"),
      options: .atomic
    )
    try Data(commitObject.standardOutput.utf8).write(
      to: releaseRootURL.appendingPathComponent("source-commit-object.txt"),
      options: .atomic
    )
    let signatureEvidence = signature.standardOutput + signature.standardError
    try Data(signatureEvidence.utf8).write(
      to: releaseRootURL.appendingPathComponent("source-signature.txt"),
      options: .atomic
    )

    let buildLogURL = releaseRootURL.appendingPathComponent("host-release-build.log")
    writeStandardError("e2e-vm: release_build=started command=make app CONFIGURATION=Release")
    try runLogged(
      runtime: runtime,
      command: "make",
      arguments: ["app", "CONFIGURATION=Release"],
      currentDirectoryURL: repositoryURL,
      logURL: buildLogURL
    )
    writeStandardError(
      "e2e-vm: release_test_build=started command=make test-service-smoke-build"
    )
    try runLogged(
      runtime: runtime,
      command: "make",
      arguments: ["test-service-smoke-build"],
      currentDirectoryURL: repositoryURL,
      logURL: buildLogURL
    )

    let sourceAppURL = repositoryURL.appendingPathComponent(
      "Products/Fan Curve.app", isDirectory: true
    )
    let stagedAppURL = releaseRootURL.appendingPathComponent(
      "Fan Curve.app", isDirectory: true
    )
    try replaceItem(sourceURL: sourceAppURL, destinationURL: stagedAppURL)

    let sourceProductsURL = repositoryURL.appendingPathComponent(
      "build/ServiceSmoke/Build/Products", isDirectory: true
    )
    let stagedProductsURL = releaseRootURL.appendingPathComponent(
      "ServiceSmoke/Build/Products", isDirectory: true
    )
    try replaceItem(sourceURL: sourceProductsURL, destinationURL: stagedProductsURL)
    let testRuns = try testRunFiles(in: stagedProductsURL)
    guard testRuns.count == 1, let testRunURL = testRuns.first else {
      throw EndToEndVMError.invalidReleaseArtifact(
        "expected one staged xctestrun, found \(testRuns.count)"
      )
    }
    let relativeTestRunPath = String(testRunURL.path.dropFirst(artifactURL.path.count + 1))
    releaseXCTestRunRelativePath = relativeTestRunPath
    try Data("\(relativeTestRunPath)\n".utf8).write(
      to: releaseRootURL.appendingPathComponent("xctestrun-relative-path.txt"),
      options: .atomic
    )

    try captureSigningEvidence(
      pathURL: stagedAppURL,
      outputURL: releaseRootURL.appendingPathComponent("codesign-app.json")
    )
    try captureSigningEvidence(
      pathURL: stagedAppURL.appendingPathComponent("Contents/MacOS/FanCurveAgent"),
      outputURL: releaseRootURL.appendingPathComponent("codesign-agent.json")
    )
    try captureSigningEvidence(
      pathURL: stagedAppURL.appendingPathComponent(
        "Contents/MacOS/io.goodkind.smcfanhelper"
      ),
      outputURL: releaseRootURL.appendingPathComponent("codesign-helper.json")
    )
    writeStandardError(
      "e2e-vm: release_source_commit="
        + sourceCommit.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        + " signature=verified team=\(releaseTeamID)"
    )
  }

  private func replaceItem(sourceURL: URL, destinationURL: URL) throws {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw EndToEndVMError.invalidReleaseArtifact("source is missing: \(sourceURL.path)")
    }
    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try FileManager.default.removeItem(at: destinationURL)
    }
    try FileManager.default.createDirectory(
      at: destinationURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
  }

  private func testRunFiles(in directoryURL: URL) throws -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey]
      )
    else {
      throw EndToEndVMError.invalidReleaseArtifact("cannot enumerate \(directoryURL.path)")
    }
    var testRuns: [URL] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "xctestrun" {
      testRuns.append(fileURL)
    }
    return testRuns.sorted { $0.path < $1.path }
  }

  private func captureSigningEvidence(pathURL: URL, outputURL: URL) throws {
    let scriptURL = repositoryURL.appendingPathComponent(
      "Scripts/CaptureCodeSigningEvidence.swift"
    )
    let result = try runCapture(
      runtime: runtime,
      command: scriptURL.path,
      arguments: [pathURL.path],
      currentDirectoryURL: repositoryURL
    )
    try requireSuccess(result, command: "CaptureCodeSigningEvidence.swift \(pathURL.path)")
    let data = Data(result.standardOutput.utf8)
    let evidence = try JSONDecoder().decode(SigningEvidence.self, from: data)
    guard evidence.teamIdentifier == releaseTeamID else {
      throw EndToEndVMError.invalidReleaseArtifact(
        "\(pathURL.path) has team \(evidence.teamIdentifier)"
      )
    }
    guard evidence.authorities.contains(where: { $0.contains("Developer ID Application") }) else {
      throw EndToEndVMError.invalidReleaseArtifact(
        "\(pathURL.path) is not Developer ID signed"
      )
    }
    try data.write(to: outputURL, options: .atomic)
  }

  private func recordHostEnvironment() throws {
    let contents = """
      run_id=\(runIdentifier)
      mode=\(mode.rawValue)
      base_image=\(baseImage)
      instance_name=\(instanceName)
      repository=\(repositoryURL.path)
      source_mount=read-only
      artifact_mount=read-write
      provider=\(provider.executableURL.path)
      provider_description=\(provider.describe(runtime: runtime))
      """
    try Data("\(contents)\n".utf8).write(
      to: artifactURL.appendingPathComponent("host-environment.txt"),
      options: .atomic
    )
  }

  private func startInstance() throws {
    let sourcePath = repositoryURL.path
    let artifactPath = artifactURL.path
    let vmLogURL = artifactURL.appendingPathComponent("instance-run.log")
    FileManager.default.createFile(atPath: vmLogURL.path, contents: nil)
    let vmLog = try FileHandle(forWritingTo: vmLogURL)
    let process = provider.startProcess(
      instanceName: instanceName,
      sourcePath: sourcePath,
      artifactPath: artifactPath
    )
    process.standardOutput = vmLog
    process.standardError = vmLog
    process.terminationHandler = { [runtime] process in
      runtime.untrack(process)
      try? vmLog.close()
    }
    runtime.track(process)
    try process.run()
    instanceProcess = process
    writeStandardError(
      "e2e-vm: instance=\(instanceName) status=starting graphics=headless "
        + "source_mount=read-only artifact_mount=read-write"
    )
  }

  private func waitForReachable() throws {
    _ = try waitForCondition(
      runtime: runtime,
      name: "guest reachable",
      deadline: reachableDeadline
    ) {
      try self.provider.exec(
        runtime: self.runtime,
        instanceName: self.instanceName,
        remoteCommand: "/usr/bin/true"
      )
    }
    let address = provider.address(runtime: runtime, instanceName: instanceName)
    try Data("\(address)\n".utf8).write(
      to: artifactURL.appendingPathComponent("instance-address.txt"),
      options: .atomic
    )
  }

  private func waitForReady() throws {
    _ = try waitForCondition(
      runtime: runtime,
      name: "provider readiness",
      deadline: readyDeadline
    ) {
      try self.provider.ready(runtime: self.runtime, instanceName: self.instanceName)
    }
  }

  private func waitForDesktop() throws {
    let userIDResult = try waitForCondition(
      runtime: runtime,
      name: "guest user ID",
      deadline: reachableDeadline
    ) {
      try self.provider.exec(
        runtime: self.runtime,
        instanceName: self.instanceName,
        remoteCommand: "/usr/bin/id -u"
      )
    }
    let userID = userIDResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !userID.isEmpty, userID.allSatisfy(\.isNumber) else {
      throw EndToEndVMError.timeout(
        condition: "logged-in desktop session",
        evidence: "guest user ID was invalid: \(userID)"
      )
    }
    _ = try waitForCondition(
      runtime: runtime,
      name: "logged-in desktop launchd domain",
      deadline: desktopDeadline
    ) {
      try self.provider.exec(
        runtime: self.runtime,
        instanceName: self.instanceName,
        remoteCommand: "/bin/launchctl print gui/\(userID) >/dev/null"
      )
    }
    _ = try waitForCondition(
      runtime: runtime,
      name: "logged-in desktop Dock",
      deadline: desktopDeadline
    ) {
      try self.provider.exec(
        runtime: self.runtime,
        instanceName: self.instanceName,
        remoteCommand: "/usr/bin/pgrep -x Dock"
      )
    }
  }

  private func runGuestWorkflow(sourceMount: String, artifactMount: String) throws {
    let guestUserResult = try provider.exec(
      runtime: runtime,
      instanceName: instanceName,
      remoteCommand: "/usr/bin/whoami"
    )
    let guestUser = guestUserResult.standardOutput.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let guestWorkspace = "/Users/\(guestUser)/fan-curve-e2e/\(runIdentifier)"
    let scriptPath = "\(sourceMount)/Scripts/e2e-guest.sh"
    var environmentArguments = [
      "env",
      "FANCURVE_E2E_SOURCE_MOUNT=\(shellQuote(sourceMount))",
      "FANCURVE_E2E_ARTIFACT_MOUNT=\(shellQuote(artifactMount))",
      "FANCURVE_E2E_GUEST_WORKSPACE=\(shellQuote(guestWorkspace))",
      "FANCURVE_E2E_RUN_ID=\(shellQuote(runIdentifier))",
    ]
    if mode == .releaseSmoke {
      guard let releaseXCTestRunRelativePath else {
        throw EndToEndVMError.invalidReleaseArtifact("Release xctestrun path was not prepared")
      }
      environmentArguments.append(
        "FANCURVE_E2E_RELEASE_APP_SOURCE="
          + shellQuote("\(artifactMount)/host-release/Fan Curve.app")
      )
      environmentArguments.append(
        "FANCURVE_E2E_RELEASE_XCTESTRUN_PATH="
          + shellQuote("\(artifactMount)/\(releaseXCTestRunRelativePath)")
      )
    }
    let remoteCommand = (
      environmentArguments + [
        "/bin/bash", shellQuote(scriptPath), "run", shellQuote(mode.rawValue),
      ]
    ).joined(separator: " ")
    let guestLogURL = artifactURL.appendingPathComponent("guest-runner.log")
    FileManager.default.createFile(atPath: guestLogURL.path, contents: nil)
    let guestLog = try FileHandle(forWritingTo: guestLogURL)
    defer {
      try? guestLog.close()
    }
    let result = try provider.exec(
      runtime: runtime,
      instanceName: instanceName,
      remoteCommand: remoteCommand
    )
    try guestLog.write(contentsOf: Data(result.standardOutput.utf8))
    try guestLog.write(contentsOf: Data(result.standardError.utf8))
    guard result.status == 0 else {
      throw EndToEndVMError.commandFailed(
        command: "guest workflow \(mode.rawValue)",
        status: result.status,
        error: "see \(guestLogURL.path)"
      )
    }
  }

  private func cleanup() {
    if let instanceProcess, instanceProcess.isRunning {
      instanceProcess.terminate()
    }
    guard instanceCreated else {
      return
    }
    let stopResult = provider.stop(runtime: EndToEndVMRuntime(), instanceName: instanceName)
    writeStandardError(
      "e2e-vm: cleanup=stop instance=\(instanceName) status=\(stopResult?.status ?? -1)"
    )
    if keepInstance {
      writeStandardError("e2e-vm: cleanup=preserve instance=\(instanceName) reason=E2E_VM_KEEP")
      return
    }
    let deleteResult = provider.delete(runtime: EndToEndVMRuntime(), instanceName: instanceName)
    if deleteResult?.status == 0 {
      writeStandardError("e2e-vm: cleanup=delete instance=\(instanceName) status=completed")
    } else {
      let error = deleteResult?.standardError ?? "provider delete did not run"
      writeStandardError("e2e-vm: cleanup=delete instance=\(instanceName) status=failed error=\(error)")
    }
  }
}

private func installSignalHandlers(runtime: EndToEndVMRuntime) -> [DispatchSourceSignal] {
  var sources: [DispatchSourceSignal] = []
  for signalNumber in [SIGINT, SIGTERM] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(
      signal: signalNumber,
      queue: .global(qos: .userInitiated)
    )
    source.setEventHandler {
      runtime.requestInterruption(signal: signalNumber)
    }
    source.resume()
    sources.append(source)
  }
  return sources
}

private func runMain() throws {
  let arguments = Array(CommandLine.arguments.dropFirst())
  if arguments.first == "validate-instance-name" {
    guard arguments.count == 2 else {
      throw EndToEndVMError.invalidArguments
    }
    let prefix =
      ProcessInfo.processInfo.environment["E2E_VM_INSTANCE_PREFIX"] ?? defaultInstancePrefix
    try validateInstanceName(arguments[1], prefix: prefix)
    print("instance_name_valid=\(arguments[1])")
    return
  }
  guard arguments.count == 1, let mode = EndToEndVMMode(rawValue: arguments[0]) else {
    throw EndToEndVMError.invalidArguments
  }
  let runtime = EndToEndVMRuntime()
  let signalSources = installSignalHandlers(runtime: runtime)
  withExtendedLifetime(signalSources) {
    do {
      try EndToEndVMOrchestrator(runtime: runtime, mode: mode).run()
    } catch {
      if case EndToEndVMError.interrupted = error {
        exit(130)
      }
      writeStandardError("e2e-vm: status=failed error=\(error.localizedDescription)")
      exit(1)
    }
  }
}

do {
  try runMain()
} catch {
  writeStandardError(error.localizedDescription)
  exit(1)
}
