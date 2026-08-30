#!/usr/bin/env swift

import Darwin
import Foundation
import Security

private struct Failure: Error, CustomStringConvertible {
    let description: String
}

private func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

private func writeLog(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func acquireDeploymentLock(for destinationURL: URL) throws -> Int32 {
    let lockURL = destinationURL.deletingLastPathComponent()
        .appendingPathComponent(".\(destinationURL.lastPathComponent).deploy.lock")
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
        try fail(
            "deploy_app.lock.open_failed path=\(lockURL.path) reason=\(String(cString: strerror(errno))) recovery=check-destination-permissions"
        )
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        close(descriptor)
        try fail(
            "deploy_app.lock.busy path=\(lockURL.path) reason=another-deployment-is-active recovery=wait-for-current-deployment"
        )
    }
    writeLog("deploy_app.lock.acquired path=\(lockURL.path)")
    return descriptor
}

private struct SigningContext {
    let identity: String
    let swiftMkURL: URL
    let team: String
}

private func verifyStaticCode(at appURL: URL) throws {
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(
        appURL as CFURL,
        SecCSFlags(),
        &staticCode
    )
    guard createStatus == errSecSuccess, let staticCode else {
        let reason = SecCopyErrorMessageString(createStatus, nil) as String?
            ?? "Security could not read the code signature"
        try fail(
            "deploy_app.signature.open_failed path=\(appURL.path) reason=\(reason) recovery=preserve-installed-app"
        )
    }
    let validationFlags = SecCSFlags(
        rawValue:
            kSecCSCheckAllArchitectures
            | kSecCSCheckNestedCode
            | kSecCSStrictValidate
    )
    let validationStatus = SecStaticCodeCheckValidity(
        staticCode,
        validationFlags,
        nil
    )
    guard validationStatus == errSecSuccess else {
        let reason = SecCopyErrorMessageString(validationStatus, nil) as String?
            ?? "Security rejected the code signature"
        try fail(
            "deploy_app.signature.invalid path=\(appURL.path) reason=\(reason) recovery=preserve-installed-app"
        )
    }
}

private func verifySignature(
    at appURL: URL,
    stage: String,
    signing: SigningContext
) throws {
    writeLog("deploy_app.signature.started stage=\(stage) path=\(appURL.path)")
    try verifyStaticCode(at: appURL)
    let process = Process()
    process.executableURL = signing.swiftMkURL
    process.arguments = [
        "verify-signing",
        "artifacts",
        appURL.path,
    ]
    var environment = ProcessInfo.processInfo.environment
    environment["CODE_SIGN_IDENTITY"] = signing.identity
    environment["DEVELOPMENT_TEAM"] = signing.team
    process.environment = environment
    let standardError = Pipe()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = standardError
    try process.run()
    process.waitUntilExit()
    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
    let errorMessage = String(decoding: errorData, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0 else {
        try fail(
            "deploy_app.signature.failed stage=\(stage) path=\(appURL.path) reason=\(errorMessage) recovery=preserve-installed-app"
        )
    }
    writeLog("deploy_app.signature.finished stage=\(stage) path=\(appURL.path)")
}

private func renameItem(from sourceURL: URL, to destinationURL: URL) throws {
    guard rename(sourceURL.path, destinationURL.path) == 0 else {
        try fail(
            "deploy_app.rename.failed source=\(sourceURL.path) destination=\(destinationURL.path) reason=\(String(cString: strerror(errno))) recovery=preserve-installed-app"
        )
    }
}

private func swapItems(_ firstURL: URL, _ secondURL: URL) throws {
    let result = firstURL.path.withCString { firstPath in
        secondURL.path.withCString { secondPath in
            renameatx_np(
                AT_FDCWD,
                firstPath,
                AT_FDCWD,
                secondPath,
                UInt32(RENAME_SWAP)
            )
        }
    }
    guard result == 0 else {
        try fail(
            "deploy_app.swap.failed staged=\(firstURL.path) destination=\(secondURL.path) reason=\(String(cString: strerror(errno))) recovery=preserve-installed-app"
        )
    }
}

private func installStagedApp(
    stagedURL: URL,
    destinationURL: URL,
    destinationExists: Bool,
    signing: SigningContext
) throws {
    if destinationExists {
        try swapItems(stagedURL, destinationURL)
        writeLog(
            "deploy_app.swap.finished staged=\(stagedURL.path) destination=\(destinationURL.path)"
        )
        do {
            try verifySignature(
                at: destinationURL,
                stage: "installed",
                signing: signing
            )
        } catch {
            try swapItems(stagedURL, destinationURL)
            writeLog(
                "deploy_app.rollback.finished destination=\(destinationURL.path) recovery=restored-previous-app"
            )
            throw error
        }
        return
    }

    try renameItem(from: stagedURL, to: destinationURL)
    writeLog("deploy_app.rename.finished destination=\(destinationURL.path)")
    do {
        try verifySignature(
            at: destinationURL,
            stage: "installed",
            signing: signing
        )
    } catch {
        try? FileManager.default.removeItem(at: destinationURL)
        throw error
    }
}

private func deploy(
    sourceURL: URL,
    destinationURL: URL,
    signing: SigningContext
) throws {
    let fileManager = FileManager.default
    var sourceIsDirectory: ObjCBool = false
    guard fileManager.fileExists(
        atPath: sourceURL.path,
        isDirectory: &sourceIsDirectory
    ), sourceIsDirectory.boolValue else {
        try fail(
            "deploy_app.source.missing path=\(sourceURL.path) recovery=build-debug-app"
        )
    }

    let destinationDirectory = destinationURL.deletingLastPathComponent()
    try fileManager.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true
    )
    let lockDescriptor = try acquireDeploymentLock(for: destinationURL)
    defer {
        flock(lockDescriptor, LOCK_UN)
        close(lockDescriptor)
        writeLog("deploy_app.lock.released destination=\(destinationURL.path)")
    }

    writeLog(
        "deploy_app.started source=\(sourceURL.path) destination=\(destinationURL.path)"
    )
    try verifySignature(at: sourceURL, stage: "source", signing: signing)

    let stagingDirectory = destinationDirectory.appendingPathComponent(
        ".\(destinationURL.lastPathComponent).deploy-\(UUID().uuidString)",
        isDirectory: true
    )
    let stagedURL = stagingDirectory.appendingPathComponent(
        destinationURL.lastPathComponent,
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: stagingDirectory,
        withIntermediateDirectories: false
    )
    defer {
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try? fileManager.removeItem(at: stagingDirectory)
        }
    }

    writeLog("deploy_app.copy.started staged=\(stagedURL.path)")
    try fileManager.copyItem(at: sourceURL, to: stagedURL)
    writeLog("deploy_app.copy.finished staged=\(stagedURL.path)")
    try verifySignature(at: stagedURL, stage: "staged", signing: signing)

    let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
    try installStagedApp(
        stagedURL: stagedURL,
        destinationURL: destinationURL,
        destinationExists: destinationExists,
        signing: signing
    )
    writeLog("deploy_app.finished destination=\(destinationURL.path)")
}

do {
    let arguments = CommandLine.arguments.dropFirst()
    guard arguments.count == 5 else {
        try fail(
            "usage: DeployApp.swift SOURCE_APP DESTINATION_APP SWIFT_MK_BIN CODE_SIGN_IDENTITY DEVELOPMENT_TEAM"
        )
    }
    let sourceURL = URL(
        fileURLWithPath: arguments[arguments.startIndex]
    ).standardizedFileURL
    let destinationURL = URL(
        fileURLWithPath: arguments[arguments.index(after: arguments.startIndex)]
    ).standardizedFileURL
    let swiftMkIndex = arguments.index(arguments.startIndex, offsetBy: 2)
    let identityIndex = arguments.index(arguments.startIndex, offsetBy: 3)
    let teamIndex = arguments.index(arguments.startIndex, offsetBy: 4)
    let signing = SigningContext(
        identity: arguments[identityIndex],
        swiftMkURL: URL(fileURLWithPath: arguments[swiftMkIndex]).standardizedFileURL,
        team: arguments[teamIndex]
    )
    try deploy(
        sourceURL: sourceURL,
        destinationURL: destinationURL,
        signing: signing
    )
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
