#!/usr/bin/env swift

import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

do {
    let args = CommandLine.arguments.dropFirst()
    guard args.count == 4 else {
        try fail("usage: AuditLaunchAgent.swift APP_PATH PLIST_NAME BUNDLE_PROGRAM AGENT_LABEL")
    }

    let appPath = args[args.startIndex]
    let plistName = args[args.index(args.startIndex, offsetBy: 1)]
    let expectedBundleProgram = args[args.index(args.startIndex, offsetBy: 2)]
    let expectedLabel = args[args.index(args.startIndex, offsetBy: 3)]

    let fileManager = FileManager.default
    let plistPath = "\(appPath)/Contents/Library/LaunchAgents/\(plistName)"
    let agentPath = "\(appPath)/\(expectedBundleProgram)"

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: appPath, isDirectory: &isDirectory), isDirectory.boolValue else {
        try fail("launch-agent-audit failed: app bundle does not exist: \(appPath)")
    }

    guard fileManager.fileExists(atPath: plistPath) else {
        try fail("launch-agent-audit failed: bundled launch agent plist missing: \(plistPath)")
    }

    guard fileManager.isExecutableFile(atPath: agentPath) else {
        try fail("launch-agent-audit failed: bundled agent executable missing or not executable: \(agentPath)")
    }

    let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
    guard
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
        let actualLabel = plist["Label"] as? String,
        let actualBundleProgram = plist["BundleProgram"] as? String
    else {
        try fail("launch-agent-audit failed: could not read Label and BundleProgram from \(plistPath)")
    }

    guard actualLabel == expectedLabel else {
        try fail("launch-agent-audit failed: Label is '\(actualLabel)', expected '\(expectedLabel)'")
    }

    guard actualBundleProgram == expectedBundleProgram else {
        try fail(
            "launch-agent-audit failed: BundleProgram is '\(actualBundleProgram)', expected '\(expectedBundleProgram)'"
        )
    }

    guard actualBundleProgram == "Contents/MacOS/FanCurveAgent" else {
        try fail("launch-agent-audit failed: BundleProgram must preserve exact executable casing")
    }

    // launchd derives the agent's default quality of service from ProcessType,
    // and Swift concurrency inherits it, so a Background job runs its tick work
    // on the throttled background pool. Measured on Mac17,7 at load average
    // 161: the tick ran for 148 seconds with the fans unchanged throughout,
    // against 1.4 seconds once the job was no longer Background. Fan control
    // has to run when the machine is busy, which is when Background loses the
    // CPU, so the classification is required and cannot be Background.
    let forbiddenProcessTypes: Set<String> = ["Background"]
    guard let actualProcessType = plist["ProcessType"] as? String else {
        try fail(
            "launch-agent-audit failed: ProcessType missing from \(plistPath); set it explicitly so the agent cannot inherit a throttled class"
        )
    }
    guard !forbiddenProcessTypes.contains(actualProcessType) else {
        try fail(
            "launch-agent-audit failed: ProcessType is '\(actualProcessType)', which launchd throttles under CPU contention and which stalled the tick loop for minutes"
        )
    }

    print("launch-agent-audit: ok")
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("launch-agent-audit failed: \(error)\n").utf8))
    exit(1)
}
