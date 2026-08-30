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
    process.waitUntilExit()
    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
    return CommandResult(
        status: process.terminationStatus,
        standardError: String(decoding: errorData, as: UTF8.self)
    )
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
    swiftMkURL: URL
) throws -> CommandResult {
    try run(
        scriptURL.path,
        arguments: [
            sourceURL.path,
            destinationURL.path,
            swiftMkURL.path,
            "-",
            "",
        ]
    )
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

do {
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
    try testValidReplacement(scriptURL: scriptURL, swiftMkURL: swiftMkURL)
    try testInvalidSourcePreservesDestination(
        scriptURL: scriptURL,
        swiftMkURL: swiftMkURL
    )
    try testDeploymentLockPreservesDestination(
        scriptURL: scriptURL,
        swiftMkURL: swiftMkURL
    )
    FileHandle.standardOutput.write(Data("DeployAppTests: ok\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
