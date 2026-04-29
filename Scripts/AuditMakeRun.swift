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
    guard args.count == 1 else {
        try fail("usage: AuditMakeRun.swift MAKEFILE")
    }

    let makefile = args[args.startIndex]
    let contents = try String(contentsOfFile: makefile, encoding: .utf8)
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    var runBody: [String] = []
    var inRun = false
    for line in lines {
        if line.hasPrefix("run:") {
            inRun = true
            runBody.append(line)
            continue
        }
        if inRun, line.first?.isWhitespace == false, line.contains(":") {
            break
        }
        if inRun {
            runBody.append(line)
        }
    }

    guard let declaration = runBody.first, declaration.range(of: #"^run:\s+app(\s|$)"#, options: .regularExpression) != nil
    else {
        try fail("run-audit failed: make run must depend on app and launch Products/FanCurve.app")
    }

    let forbiddenTokens = ["install-app", "restart-agent", "sync-agent-plist", "launchctl", "/Applications"]
    let body = runBody.joined(separator: "\n")
    for token in forbiddenTokens where body.contains(token) {
        try fail("run-audit failed: make run must not reference '\(token)'")
    }

    print("run-audit: ok")
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("run-audit failed: \(error)\n").utf8))
    exit(1)
}
