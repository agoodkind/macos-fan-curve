#!/usr/bin/env swift

import Darwin
import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

/// The background agent is a bare launchd job (`BundleProgram`), not a
/// registered Launch Services app, so `NSRunningApplication` cannot see it the
/// way `TerminateAppInstances.swift` sees the main app. `launchctl print` is a
/// read-only introspection call; it does not bootstrap, boot out, kickstart,
/// or touch the job's registration, so it stays inside the guardrail that
/// only SMAppService may register or reconfigure the agent's launchd job.
func currentPID(forLabel label: String) throws -> pid_t? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["print", "gui/\(getuid())/\(label)"]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    try process.run()
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        return nil
    }

    let output = String(decoding: outputData, as: UTF8.self)
    for line in output.split(separator: "\n") {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix("pid = ") else { continue }
        let pidText = trimmedLine.dropFirst("pid = ".count)
        if let pidValue = Int32(pidText) {
            return pid_t(pidValue)
        }
    }
    return nil
}

func processIsAlive(_ processID: pid_t) -> Bool {
    kill(processID, 0) == 0
}

func waitUntil(deadline: Date, condition: () throws -> Bool) rethrows {
    while Date() < deadline, try !condition() {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
}

do {
    let args = CommandLine.arguments.dropFirst()
    guard args.count == 1 else {
        try fail("usage: TerminateAgentInstances.swift LAUNCHD_LABEL")
    }
    let label = args[args.startIndex]

    guard let originalPID = try currentPID(forLabel: label) else {
        print("terminate-agent-instances: no running job for \(label)")
        exit(0)
    }

    // SIGTERM lets the agent's own signal handler reset fans to auto before it
    // exits. The job's `KeepAlive` (confirmed via `launchctl print`) then
    // respawns it under launchd's own supervision, from whatever binary is
    // currently on disk at BundleProgram, with no re-registration here.
    guard kill(originalPID, SIGTERM) == 0 else {
        try fail("terminate-agent-instances: failed to signal pid \(originalPID) for \(label)")
    }

    try waitUntil(deadline: Date().addingTimeInterval(10)) {
        !processIsAlive(originalPID)
    }
    guard !processIsAlive(originalPID) else {
        try fail(
            "terminate-agent-instances: pid \(originalPID) for \(label) did not exit after SIGTERM"
        )
    }

    var respawnedPID: pid_t?
    try waitUntil(deadline: Date().addingTimeInterval(10)) {
        if let candidate = try currentPID(forLabel: label), candidate != originalPID {
            respawnedPID = candidate
            return true
        }
        return false
    }
    guard let respawnedPID else {
        try fail(
            "terminate-agent-instances: launchd did not respawn \(label) after terminating pid \(originalPID)"
        )
    }

    print("terminate-agent-instances: terminated=\(originalPID) respawned=\(respawnedPID)")
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("terminate-agent-instances failed: \(error)\n").utf8))
    exit(1)
}
