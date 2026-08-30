#!/usr/bin/env swift

import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

struct AuditResult {
    let status: Int32
    let standardError: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

func fixture(
    runCommand: String,
    runAppSource: String = "$(BUILD_DIR)/Build/Products/Debug/$(APP_BUNDLE_NAME).app",
    deploySource: String = "$(RUN_APP_SOURCE)",
    terminateAgentLine: String = "\t@Scripts/TerminateAgentInstances.swift \"$(AGENT_LABEL)\""
) -> String {
    let continuation = "\\"
    return """
    INSTALL_APP_DEST ?= /Applications/Fan Curve.app
    RUN_APP_SOURCE = \(runAppSource)

    run:
    \(runCommand)
    \t@Scripts/DeployApp.swift \(continuation)
    \t\t"\(deploySource)" \(continuation)
    \t\t"$(INSTALL_APP_DEST)" \(continuation)
    \t\t"$(SWIFT_MK_BIN)" \(continuation)
    \t\t"$(CODE_SIGN_IDENTITY)" \(continuation)
    \t\t"$(DEVELOPMENT_TEAM)"
    \(terminateAgentLine)
    \t@Scripts/TerminateAppInstances.swift "$(APP_BUNDLE_ID)"
    \t@open "$(INSTALL_APP_DEST)"

    next-target:
    \t@true
    """
}

func runAudit(scriptPath: String, makefile: String) throws -> AuditResult {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("audit-make-run-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    let makefileURL = temporaryDirectory.appendingPathComponent("Makefile")
    try makefile.write(to: makefileURL, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", scriptPath, makefileURL.path]

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
    let errorText = String(decoding: errorData, as: UTF8.self)
    return AuditResult(status: process.terminationStatus, standardError: errorText)
}

func requireRejection(
    _ name: String,
    scriptPath: String,
    makefile: String,
    expectedError: String
) throws {
    let result = try runAudit(scriptPath: scriptPath, makefile: makefile)
    guard result.status != 0 else {
        try fail("AuditMakeRunTests failed: \(name) was accepted")
    }
    guard result.standardError.contains(expectedError) else {
        try fail("AuditMakeRunTests failed: \(name) returned unexpected error: \(result.standardError)")
    }
}

func requireAcceptance(_ name: String, scriptPath: String, makefile: String) throws {
    let result = try runAudit(scriptPath: scriptPath, makefile: makefile)
    guard result.status == 0 else {
        try fail("AuditMakeRunTests failed: \(name) was rejected: \(result.standardError)")
    }
}

do {
    let arguments = CommandLine.arguments.dropFirst()
    guard arguments.count == 1 else {
        try fail("usage: AuditMakeRunTests.swift AUDIT_SCRIPT")
    }

    let scriptPath = URL(fileURLWithPath: arguments[arguments.startIndex]).standardizedFileURL.path
    let gatedBuildError =
        "make run must clear inherited build and freshness state before the Debug build"
    let debugBuildCommand =
        "\tenv -u SWIFT_BUILD_CMD -u SWIFT_MK_FRESH_CONFIG_KEY $(MAKE) CONFIGURATION=Debug build"
    let debugAppSourceError =
        "make run must deploy and verify the Debug build artifact atomically"
    let recipeError =
        "make run must preserve the canonical gated build and deployment recipe"
    /// A recipe missing the agent restart reports this rather than the generic
    /// recipe error, because the per-step checks run before the recipe
    /// comparison so the message names what the missing step is for.
    let agentRestartError =
        "make run must restart the background agent by launchd label"
    let lineContinuation = "\\"

    try requireRejection(
        "inherited Release build and freshness state",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build",
            deploySource: "$(APP_DEST)"
        ),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "inherited freshness state",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\tenv -u SWIFT_BUILD_CMD $(MAKE) CONFIGURATION=Debug build"
        ),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "inherited build command",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\tenv -u SWIFT_MK_FRESH_CONFIG_KEY $(MAKE) CONFIGURATION=Debug build"
        ),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "generic Products staging",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: debugBuildCommand, deploySource: "$(APP_DEST)"),
        expectedError: debugAppSourceError
    )
    try requireRejection(
        "Release run app source",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: debugBuildCommand,
            runAppSource: "$(BUILD_DIR)/Build/Products/Release/$(APP_BUNDLE_NAME).app"
        ),
        expectedError: debugAppSourceError
    )
    try requireRejection(
        "comment-only gated build",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: "\t# $(MAKE) CONFIGURATION=Debug build\n\t@true"),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "echo-only gated build",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: "\t@echo \"$(MAKE) CONFIGURATION=Debug build\""),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "inline-comment-only gated build",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: "\t$(MAKE) noop # CONFIGURATION=Debug build"),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "later-command-only gated build",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: "\t$(MAKE) noop; echo CONFIGURATION=Debug build"),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "semicolon-comment-only gated build",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: "\t$(MAKE) noop;# CONFIGURATION=Debug build"),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "second recursive Make command",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build; $(MAKE) CONFIGURATION=Debug app-local"
        ),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "wrapped second recursive Make command",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\tenv $(MAKE) CONFIGURATION=Debug app-local"
        ),
        expectedError: "make run must not compile through app-local directly"
    )
    try requireRejection(
        "literal make second recursive command",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\tmake CONFIGURATION=Debug app''-local"
        ),
        expectedError: "make run must not compile through app-local directly"
    )
    try requireRejection(
        "path make second recursive command",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\t/usr/bin/make CONFIGURATION=Debug app-local"
        ),
        expectedError: "make run must not compile through app-local directly"
    )
    try requireRejection(
        "environment Make second recursive command",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\t$MAKE CONFIGURATION=Debug app-local>/dev/null"
        ),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "nested shell second recursive Make command",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\tsh -c 'make CONFIGURATION=Debug app-local'"
        ),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "echo-wrapped second recursive Make command",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\t@echo harmless; $(MAKE) CONFIGURATION=Debug app-local"
        ),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "double-quoted nonspecial escape in Debug assignment",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) \"CONFIGURATION=De\(lineContinuation)bug\" build"
        ),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "redirected direct app-local build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\t$(MAKE) CONFIGURATION=Debug app-local>/dev/null"
        ),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "makefile option operand resembling Debug assignment",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: "\t$(MAKE) -f CONFIGURATION=Debug build"),
        expectedError: gatedBuildError
    )
    try requireRejection(
        "direct app-local build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\t$(MAKE) CONFIGURATION=Debug app-local"
        ),
        expectedError: "make run must not compile through app-local directly"
    )
    try requireRejection(
        "quoted direct app-local build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\t$(MAKE) CONFIGURATION=Debug \"app-local\""
        ),
        expectedError: "make run must not compile through app-local directly"
    )
    try requireRejection(
        "control-operator direct app-local build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\t$(MAKE) CONFIGURATION=Debug app-local; true"
        ),
        expectedError: "make run must not compile through app-local directly"
    )
    try requireRejection(
        "continued direct app-local build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build \(lineContinuation)\n    CONFIGURATION=Debug app-local"
        ),
        expectedError: "make run must not compile through app-local directly"
    )
    try requireRejection(
        "split-word direct app-local build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\t$(MAKE) CONFIGURATION=Debug app-\(lineContinuation)\nlocal"
        ),
        expectedError: "make run must not compile through app-local directly"
    )
    try requireRejection(
        "recipe-prefixed split-word direct app-local build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug build\n\t$(MAKE) CONFIGURATION=Debug app-\(lineContinuation)\n\tlocal"
        ),
        expectedError: "make run must not compile through app-local directly"
    )
    try requireRejection(
        "spaced split-word gated Debug build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\t$(MAKE) CONFIGURATION=Debug bu\(lineContinuation)\n    ild"
        ),
        expectedError: gatedBuildError
    )
    try requireAcceptance(
        "fresh gated Debug build",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: debugBuildCommand)
    )
    try requireRejection(
        "extra run step",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: "\(debugBuildCommand)\n\t@true"),
        expectedError: recipeError
    )
    try requireAcceptance(
        "fresh gated Debug build with commented app-local text",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\(debugBuildCommand) # CONFIGURATION=Debug app-local"
        )
    )
    try requireAcceptance(
        "quoted fresh gated Debug build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\tenv -u SWIFT_BUILD_CMD -u SWIFT_MK_FRESH_CONFIG_KEY $(MAKE) CONFIGURATION=\"Debug\" \"build\""
        )
    )
    try requireAcceptance(
        "continued fresh gated Debug build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\tenv -u SWIFT_BUILD_CMD -u SWIFT_MK_FRESH_CONFIG_KEY $(MAKE) CONFIGURATION=Debug \(lineContinuation)\n    build"
        )
    )
    try requireAcceptance(
        "split-word fresh gated Debug build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\tenv -u SWIFT_BUILD_CMD -u SWIFT_MK_FRESH_CONFIG_KEY $(MAKE) CONFIGURATION=Debug bu\(lineContinuation)\nild"
        )
    )
    try requireAcceptance(
        "recipe-prefixed split-word fresh gated Debug build",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: "\tenv -u SWIFT_BUILD_CMD -u SWIFT_MK_FRESH_CONFIG_KEY $(MAKE) CONFIGURATION=Debug bu\(lineContinuation)\n\tild"
        )
    )
    try requireAcceptance(
        "agent restart step present",
        scriptPath: scriptPath,
        makefile: fixture(runCommand: debugBuildCommand)
    )
    try requireRejection(
        "missing agent restart step",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: debugBuildCommand,
            terminateAgentLine: "\t@true"
        ),
        expectedError: agentRestartError
    )
    try requireRejection(
        "dropped agent restart step",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: debugBuildCommand,
            terminateAgentLine: ""
        ),
        expectedError: agentRestartError
    )
    try requireRejection(
        "manual launchctl kickstart instead of agent restart step",
        scriptPath: scriptPath,
        makefile: fixture(
            runCommand: debugBuildCommand,
            terminateAgentLine: "\t@launchctl kickstart -k gui/501/$(AGENT_LABEL)"
        ),
        expectedError: "make run must not reference 'launchctl'"
    )
    print("AuditMakeRunTests: ok")
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("AuditMakeRunTests failed: \(error)\n").utf8))
    exit(1)
}
