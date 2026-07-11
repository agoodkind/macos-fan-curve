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

    // `make run` builds the Debug app, which deploys to /Applications, and launches
    // that one canonical copy. It must not register login items by hand.
    let forbiddenTokens = ["install-app", "restart-agent", "sync-agent-plist", "launchctl", "pkill"]

    var runBody: [String] = []
    var inRun = false
    for line in lines {
        if line.hasPrefix("run:") {
            inRun = true
            runBody.append(line)
            continue
        }
        if inRun, let first = line.first, first.isWhitespace == false, line.contains(":") {
            break
        }
        if inRun {
            runBody.append(line)
        }
    }

    guard let declaration = runBody.first,
        declaration.range(of: #"^run:"#, options: .regularExpression) != nil
    else {
        try fail("run-audit failed: Makefile must define a 'run' target")
    }
    let body = runBody.joined(separator: "\n")

    for token in forbiddenTokens where body.contains(token) {
        try fail("run-audit failed: make run must not reference '\(token)'")
    }

    guard body.contains("CONFIGURATION=Debug build") else {
        try fail(
            "run-audit failed: make run must build the Debug configuration through the gated build target"
        )
    }

    guard !body.contains("CONFIGURATION=Debug app-local") else {
        try fail("run-audit failed: make run must not compile through app-local directly")
    }

    guard body.contains(#"cp -R "$(APP_DEST)" "$(INSTALL_APP_DEST)""#) else {
        try fail(#"run-audit failed: make run must deploy the build to /Applications with cp -R "$(APP_DEST)" "$(INSTALL_APP_DEST)""#)
    }

    guard body.contains(#"Scripts/TerminateAppInstances.swift "$(APP_BUNDLE_ID)""#) else {
        try fail("run-audit failed: make run must terminate existing app UI processes by bundle identifier")
    }

    guard body.contains(#"open "$(INSTALL_APP_DEST)""#) else {
        try fail(#"run-audit failed: make run must launch the canonical app with open "$(INSTALL_APP_DEST)""#)
    }

    let installDestDefinition = lines.first {
        $0.range(of: #"^INSTALL_APP_DEST\s*[?:]?=.*"#, options: .regularExpression) != nil
    }
    guard let installDest = installDestDefinition, installDest.contains("/Applications/") else {
        try fail("run-audit failed: INSTALL_APP_DEST must resolve under /Applications")
    }

    print("run-audit: ok")
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("run-audit failed: \(error)\n").utf8))
    exit(1)
}
