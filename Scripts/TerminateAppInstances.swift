#!/usr/bin/env swift

import AppKit
import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

do {
    let args = CommandLine.arguments.dropFirst()
    guard args.count == 1 else {
        try fail("usage: TerminateAppInstances.swift BUNDLE_ID")
    }

    let bundleIdentifier = args[args.startIndex]
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    guard !applications.isEmpty else {
        print("terminate-app-instances: no running app for \(bundleIdentifier)")
        exit(0)
    }

    for application in applications {
        _ = application.terminate()
    }

    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline, applications.contains(where: { !$0.isTerminated }) {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }

    let remainingApplications = applications.filter { !$0.isTerminated }
    for application in remainingApplications {
        _ = application.forceTerminate()
    }

    print(
        "terminate-app-instances: terminated=\(applications.count - remainingApplications.count) forced=\(remainingApplications.count)"
    )
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("terminate-app-instances failed: \(error)\n").utf8))
    exit(1)
}
