#!/usr/bin/env swift

import Darwin
import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

struct CommandResult {
    let status: Int32
    let standardError: String
}

enum VerifierMode: String {
    case failCleanup
    case failRollback
    case largeStandardError
}

let verifierModeKey = "DEPLOY_APP_TEST_VERIFIER_MODE"
let verifierStatePathKey = "DEPLOY_APP_TEST_VERIFIER_STATE_PATH"
let realSwiftMkPathKey = "DEPLOY_APP_TEST_REAL_SWIFT_MK_PATH"

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

func run(
    _ executable: String,
    arguments: [String],
    environment: [String: String] = [:]
) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(
        environment
    ) { _, newValue in newValue }
    let standardError = Pipe()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = standardError
    try process.run()
    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(
        status: process.terminationStatus,
        standardError: String(decoding: errorData, as: UTF8.self)
    )
}

func nextVerifierInvocation(at stateURL: URL) throws -> Int {
    let previousInvocation: Int
    if FileManager.default.fileExists(atPath: stateURL.path) {
        let storedValue = try String(contentsOf: stateURL, encoding: .utf8)
        previousInvocation = Int(storedValue) ?? 0
    } else {
        previousInvocation = 0
    }
    let invocation = previousInvocation + 1
    try Data(String(invocation).utf8).write(to: stateURL, options: .atomic)
    return invocation
}

func runVerifierProxyIfRequested() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.first == "verify-signing" else { return }
    let environment = ProcessInfo.processInfo.environment
    guard let modeValue = environment[verifierModeKey],
        let mode = VerifierMode(rawValue: modeValue),
        let statePath = environment[verifierStatePathKey],
        let realSwiftMkPath = environment[realSwiftMkPathKey]
    else {
        try fail("DeployAppTests verifier proxy is missing its environment")
    }

    let verification = try run(realSwiftMkPath, arguments: arguments)
    guard verification.status == 0 else {
        FileHandle.standardError.write(Data(verification.standardError.utf8))
        exit(verification.status)
    }

    let invocation = try nextVerifierInvocation(
        at: URL(fileURLWithPath: statePath)
    )
    switch mode {
    case .failCleanup:
        if invocation == 3, let appPath = arguments.last {
            let parentURL = URL(fileURLWithPath: appPath).deletingLastPathComponent()
            guard chmod(parentURL.path, S_IRUSR | S_IXUSR) == 0 else {
                try fail("DeployAppTests verifier proxy could not restrict cleanup")
            }
            FileHandle.standardError.write(Data("reject installed app\n".utf8))
            exit(1)
        }
    case .failRollback:
        if invocation == 3, let appPath = arguments.last {
            let appURL = URL(fileURLWithPath: appPath)
            let rejectedURL = appURL.deletingLastPathComponent()
                .appendingPathComponent("\(appURL.lastPathComponent).rejected")
            try FileManager.default.moveItem(at: appURL, to: rejectedURL)
            FileHandle.standardError.write(Data("reject installed app\n".utf8))
            exit(1)
        }
    case .largeStandardError:
        FileHandle.standardError.write(Data(repeating: 120, count: 1_000_000))
    }
    exit(0)
}

func requireSuccess(_ result: CommandResult, operation: String) throws {
    guard result.status == 0 else {
        try fail("DeployAppTests failed: \(operation): \(result.standardError)")
    }
}

func makeSignedApp(at appURL: URL, marker: String, swiftMkURL: URL) throws {
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let executableDirectory = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
    let resourcesDirectory = contentsURL.appendingPathComponent("Resources", isDirectory: true)
    try FileManager.default.createDirectory(
        at: executableDirectory,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: resourcesDirectory,
        withIntermediateDirectories: true
    )
    let executableURL = executableDirectory.appendingPathComponent("DeployFixture")
    try FileManager.default.copyItem(
        at: URL(fileURLWithPath: "/usr/bin/true"),
        to: executableURL
    )
    let info: [String: String] = [
        "CFBundleExecutable": "DeployFixture",
        "CFBundleIdentifier": "io.goodkind.deploy-fixture",
        "CFBundlePackageType": "APPL",
    ]
    let infoData = try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    )
    try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))
    try Data(marker.utf8).write(
        to: resourcesDirectory.appendingPathComponent("marker.txt")
    )
    try requireSuccess(
        run(
            swiftMkURL.path,
            arguments: ["codesign-run", "--mode", "binary", appURL.path],
            environment: ["SWIFT_MK_SIGN_IDENTITY": "-"]
        ),
        operation: "sign fixture"
    )
}

func marker(in appURL: URL) throws -> String {
    let markerURL = appURL.appendingPathComponent("Contents/Resources/marker.txt")
    return try String(contentsOf: markerURL, encoding: .utf8)
}

func deploy(
    scriptURL: URL,
    sourceURL: URL,
    destinationURL: URL,
    swiftMkURL: URL,
    environment: [String: String] = [:]
) throws -> CommandResult {
    try run(
        scriptURL.path,
        arguments: [
            sourceURL.path,
            destinationURL.path,
            swiftMkURL.path,
            "-",
            "",
        ],
        environment: environment
    )
}

func verifierEnvironment(
    mode: VerifierMode,
    realSwiftMkURL: URL,
    stateURL: URL
) -> [String: String] {
    [
        verifierModeKey: mode.rawValue,
        verifierStatePathKey: stateURL.path,
        realSwiftMkPathKey: realSwiftMkURL.path,
    ]
}

func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("deploy-app-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

func testValidReplacement(scriptURL: URL, swiftMkURL: URL) throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("Source.app", isDirectory: true)
        let destinationURL = directory.appendingPathComponent("Fan Curve.app", isDirectory: true)
        try makeSignedApp(at: sourceURL, marker: "new", swiftMkURL: swiftMkURL)
        try makeSignedApp(at: destinationURL, marker: "old", swiftMkURL: swiftMkURL)

        try requireSuccess(
            deploy(
                scriptURL: scriptURL,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                swiftMkURL: swiftMkURL
            ),
            operation: "replace valid app"
        )
        guard try marker(in: destinationURL) == "new" else {
            try fail("DeployAppTests failed: valid replacement kept the old app")
        }
        try requireSuccess(
            run(
                swiftMkURL.path,
                arguments: ["verify-signing", "artifacts", destinationURL.path],
                environment: [
                    "CODE_SIGN_IDENTITY": "-",
                    "DEVELOPMENT_TEAM": "",
                ]
            ),
            operation: "verify installed app"
        )
    }
}

func testInvalidSourcePreservesDestination(scriptURL: URL, swiftMkURL: URL) throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("Source.app", isDirectory: true)
        let destinationURL = directory.appendingPathComponent("Fan Curve.app", isDirectory: true)
        try makeSignedApp(at: sourceURL, marker: "new", swiftMkURL: swiftMkURL)
        try makeSignedApp(at: destinationURL, marker: "old", swiftMkURL: swiftMkURL)
        try FileManager.default.removeItem(
            at: sourceURL.appendingPathComponent("Contents/_CodeSignature", isDirectory: true)
        )

        let result = try deploy(
            scriptURL: scriptURL,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            swiftMkURL: swiftMkURL
        )
        guard result.status != 0 else {
            try fail("DeployAppTests failed: invalid source was deployed")
        }
        guard try marker(in: destinationURL) == "old" else {
            try fail("DeployAppTests failed: invalid source replaced the installed app")
        }
    }
}

func testDeploymentLockPreservesDestination(scriptURL: URL, swiftMkURL: URL) throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("Source.app", isDirectory: true)
        let destinationURL = directory.appendingPathComponent("Fan Curve.app", isDirectory: true)
        try makeSignedApp(at: sourceURL, marker: "new", swiftMkURL: swiftMkURL)
        try makeSignedApp(at: destinationURL, marker: "old", swiftMkURL: swiftMkURL)
        let lockURL = directory.appendingPathComponent(".Fan Curve.app.deploy.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            try fail("DeployAppTests failed: could not create deployment lock")
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            try fail("DeployAppTests failed: could not acquire deployment lock")
        }

        let result = try deploy(
            scriptURL: scriptURL,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            swiftMkURL: swiftMkURL
        )
        guard result.status != 0 else {
            try fail("DeployAppTests failed: concurrent deployment was accepted")
        }
        guard try marker(in: destinationURL) == "old" else {
            try fail("DeployAppTests failed: concurrent deployment replaced the installed app")
        }
    }
}

func testDeploymentLockAllowsDestinationGroup(
    scriptURL: URL,
    swiftMkURL: URL
) throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("Source.app", isDirectory: true)
        let destinationURL = directory.appendingPathComponent("Fan Curve.app", isDirectory: true)
        try makeSignedApp(at: sourceURL, marker: "new", swiftMkURL: swiftMkURL)

        try requireSuccess(
            deploy(
                scriptURL: scriptURL,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                swiftMkURL: swiftMkURL
            ),
            operation: "create deployment lock"
        )
        let lockURL = directory.appendingPathComponent(".Fan Curve.app.deploy.lock")
        let attributes = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
            mode_t(permissions.uint16Value) & S_IWGRP != 0
        else {
            try fail("DeployAppTests failed: destination group cannot open deployment lock")
        }
    }
}

func testLargeVerifierErrorDoesNotDeadlock(
    scriptURL: URL,
    realSwiftMkURL: URL,
    verifierURL: URL
) throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("Source.app", isDirectory: true)
        let destinationURL = directory.appendingPathComponent("Fan Curve.app", isDirectory: true)
        let stateURL = directory.appendingPathComponent("verifier-state")
        try makeSignedApp(at: sourceURL, marker: "new", swiftMkURL: realSwiftMkURL)

        try requireSuccess(
            deploy(
                scriptURL: scriptURL,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                swiftMkURL: verifierURL,
                environment: verifierEnvironment(
                    mode: .largeStandardError,
                    realSwiftMkURL: realSwiftMkURL,
                    stateURL: stateURL
                )
            ),
            operation: "drain verbose verifier error"
        )
    }
}

func testRollbackFailurePreservesPreviousApp(
    scriptURL: URL,
    realSwiftMkURL: URL,
    verifierURL: URL
) throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("Source.app", isDirectory: true)
        let destinationURL = directory.appendingPathComponent("Fan Curve.app", isDirectory: true)
        let stateURL = directory.appendingPathComponent("verifier-state")
        try makeSignedApp(at: sourceURL, marker: "new", swiftMkURL: realSwiftMkURL)
        try makeSignedApp(at: destinationURL, marker: "old", swiftMkURL: realSwiftMkURL)

        let result = try deploy(
            scriptURL: scriptURL,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            swiftMkURL: verifierURL,
            environment: verifierEnvironment(
                mode: .failRollback,
                realSwiftMkURL: realSwiftMkURL,
                stateURL: stateURL
            )
        )
        guard result.status != 0,
            result.standardError.contains("deploy_app.rollback.failed")
        else {
            try fail("DeployAppTests failed: rollback failure was not reported")
        }
        let recoveryApps = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".Fan Curve.app.deploy-") }
            .map { $0.appendingPathComponent("Fan Curve.app", isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard recoveryApps.count == 1,
            try marker(in: recoveryApps[0]) == "old"
        else {
            try fail("DeployAppTests failed: rollback failure lost the previous app")
        }
    }
}

func testCleanupFailureReportsRejectedInstall(
    scriptURL: URL,
    realSwiftMkURL: URL,
    verifierURL: URL
) throws {
    try withTemporaryDirectory { directory in
        let sourceURL = directory.appendingPathComponent("Source.app", isDirectory: true)
        let destinationURL = directory.appendingPathComponent("Fan Curve.app", isDirectory: true)
        let stateURL = directory.appendingPathComponent("verifier-state")
        try makeSignedApp(at: sourceURL, marker: "new", swiftMkURL: realSwiftMkURL)

        defer { _ = chmod(directory.path, S_IRWXU) }
        let result = try deploy(
            scriptURL: scriptURL,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            swiftMkURL: verifierURL,
            environment: verifierEnvironment(
                mode: .failCleanup,
                realSwiftMkURL: realSwiftMkURL,
                stateURL: stateURL
            )
        )
        guard chmod(directory.path, S_IRWXU) == 0 else {
            try fail("DeployAppTests failed: could not restore temporary directory permissions")
        }
        guard result.status != 0,
            result.standardError.contains("deploy_app.cleanup.failed"),
            FileManager.default.fileExists(atPath: destinationURL.path)
        else {
            try fail("DeployAppTests failed: rejected install cleanup failure was hidden")
        }
    }
}

func testSymlinkSourceCreatesIndependentApp(
    scriptURL: URL,
    swiftMkURL: URL
) throws {
    try withTemporaryDirectory { directory in
        let targetURL = directory.appendingPathComponent("Target.app", isDirectory: true)
        let sourceURL = directory.appendingPathComponent("Source.app", isDirectory: true)
        let destinationURL = directory.appendingPathComponent("Fan Curve.app", isDirectory: true)
        try makeSignedApp(at: targetURL, marker: "new", swiftMkURL: swiftMkURL)
        try FileManager.default.createSymbolicLink(
            at: sourceURL,
            withDestinationURL: targetURL
        )

        try requireSuccess(
            deploy(
                scriptURL: scriptURL,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                swiftMkURL: swiftMkURL
            ),
            operation: "deploy symlinked source"
        )
        try FileManager.default.removeItem(at: targetURL)
        guard try marker(in: destinationURL) == "new" else {
            try fail("DeployAppTests failed: installed app depends on symlink target")
        }
    }
}

do {
    try runVerifierProxyIfRequested()
    let arguments = CommandLine.arguments.dropFirst()
    guard arguments.count == 2 else {
        try fail("usage: DeployAppTests.swift DEPLOY_SCRIPT SWIFT_MK_BIN")
    }
    let scriptURL = URL(
        fileURLWithPath: arguments[arguments.startIndex]
    ).standardizedFileURL
    let swiftMkURL = URL(
        fileURLWithPath: arguments[arguments.index(after: arguments.startIndex)]
    ).standardizedFileURL
    let verifierURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    try testValidReplacement(scriptURL: scriptURL, swiftMkURL: swiftMkURL)
    try testInvalidSourcePreservesDestination(
        scriptURL: scriptURL,
        swiftMkURL: swiftMkURL
    )
    try testDeploymentLockPreservesDestination(
        scriptURL: scriptURL,
        swiftMkURL: swiftMkURL
    )
    try testDeploymentLockAllowsDestinationGroup(
        scriptURL: scriptURL,
        swiftMkURL: swiftMkURL
    )
    try testLargeVerifierErrorDoesNotDeadlock(
        scriptURL: scriptURL,
        realSwiftMkURL: swiftMkURL,
        verifierURL: verifierURL
    )
    try testRollbackFailurePreservesPreviousApp(
        scriptURL: scriptURL,
        realSwiftMkURL: swiftMkURL,
        verifierURL: verifierURL
    )
    try testCleanupFailureReportsRejectedInstall(
        scriptURL: scriptURL,
        realSwiftMkURL: swiftMkURL,
        verifierURL: verifierURL
    )
    try testSymlinkSourceCreatesIndependentApp(
        scriptURL: scriptURL,
        swiftMkURL: swiftMkURL
    )
    FileHandle.standardOutput.write(Data("DeployAppTests: ok\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
