#!/usr/bin/env swift

import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

func firstShellCommandTokens(_ command: Substring) -> [String] {
    let doubleQuoteEscapableCharacters: Set<Character> = ["$", "`", "\"", "\\", "\n"]
    var tokens: [String] = []
    var currentToken = ""
    var isEscaped = false
    var isInDoubleQuotes = false
    var isInSingleQuotes = false

    func appendCurrentToken() {
        guard !currentToken.isEmpty else {
            return
        }
        tokens.append(currentToken)
        currentToken = ""
    }

    for character in command {
        if isEscaped {
            if isInDoubleQuotes, !doubleQuoteEscapableCharacters.contains(character) {
                currentToken.append("\\")
            }
            if character != "\n" {
                currentToken.append(character)
            }
            isEscaped = false
            continue
        }
        if character == "\\", !isInSingleQuotes {
            isEscaped = true
            continue
        }
        if character == "'", !isInDoubleQuotes {
            isInSingleQuotes.toggle()
            continue
        }
        if character == "\"", !isInSingleQuotes {
            isInDoubleQuotes.toggle()
            continue
        }
        if !isInSingleQuotes, !isInDoubleQuotes {
            if ";&|".contains(character) {
                appendCurrentToken()
                tokens.append("<control-operator>")
                break
            }
            if character == "#", currentToken.isEmpty {
                break
            }
            if character.isWhitespace {
                appendCurrentToken()
                continue
            }
        }
        currentToken.append(character)
    }

    appendCurrentToken()
    return tokens
}

func hasTrailingLineContinuation(_ line: String) -> Bool {
    var backslashCount = 0
    for character in line.reversed() {
        if character != "\\" {
            break
        }
        backslashCount += 1
    }
    return backslashCount.isMultiple(of: 2) == false
}

func logicalRecipeCommands(from lines: [String]) -> [String] {
    var commands: [String] = []
    var continuedCommand: String?

    for line in lines {
        if var command = continuedCommand {
            let continuation = line.first == "\t" ? line.dropFirst() : line[...]
            command += "\n" + continuation
            continuedCommand = command
        } else if line.first == "\t" {
            continuedCommand = line
        } else {
            continue
        }

        guard let command = continuedCommand else {
            continue
        }
        if hasTrailingLineContinuation(command) {
            continuedCommand = command
            continue
        }

        commands.append(command)
        continuedCommand = nil
    }

    if let continuedCommand {
        commands.append(continuedCommand)
    }
    return commands
}

func recipeCommandTokens(from recipeLine: String) -> [String]? {
    guard recipeLine.first == "\t" else {
        return nil
    }

    var command = recipeLine.drop(while: { $0.isWhitespace })
    while let first = command.first, "@-+".contains(first) {
        command = command.dropFirst()
    }

    return firstShellCommandTokens(command)
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

    let recipeCommands = logicalRecipeCommands(from: runBody)
    let recipeTokenLists = recipeCommands.compactMap(recipeCommandTokens).filter { !$0.isEmpty }
    guard !recipeTokenLists.contains(where: { $0.contains("app-local") }) else {
        try fail("run-audit failed: make run must not compile through app-local directly")
    }

    let requiredDebugBuildTokens = [
        "env",
        "-u",
        "SWIFT_BUILD_CMD",
        "-u",
        "SWIFT_MK_FRESH_CONFIG_KEY",
        "$(MAKE)",
        "CONFIGURATION=Debug",
        "build",
    ]
    guard recipeTokenLists.first == requiredDebugBuildTokens else {
        try fail(
            "run-audit failed: make run must clear inherited build and freshness state before the Debug build"
        )
    }

    // Each step gets its own check first, so a missing one reports what that
    // step is for. The recipe comparison below then catches what a per-step
    // check cannot: wrong order, or an extra step nobody asked for.
    let runAppSourceDefinition = lines.first {
        $0.range(
            of: #"^RUN_APP_SOURCE\s*=\s*\$\(BUILD_DIR\)/Build/Products/Debug/\$\(APP_BUNDLE_NAME\)\.app\s*$"#,
            options: .regularExpression
        ) != nil
    }
    guard runAppSourceDefinition != nil,
        body.contains(#"cp -R "$(RUN_APP_SOURCE)" "$(INSTALL_APP_DEST)""#)
    else {
        try fail("run-audit failed: make run must deploy the Debug build artifact directly")
    }

    guard body.contains(#"Scripts/TerminateAgentInstances.swift "$(AGENT_LABEL)""#) else {
        try fail(
            "run-audit failed: make run must restart the background agent by launchd label so KeepAlive respawns it from the redeployed binary"
        )
    }

    guard body.contains(#"Scripts/TerminateAppInstances.swift "$(APP_BUNDLE_ID)""#) else {
        try fail("run-audit failed: make run must terminate existing app UI processes by bundle identifier")
    }

    guard body.contains(#"open "$(INSTALL_APP_DEST)""#) else {
        try fail(#"run-audit failed: make run must launch the canonical app with open "$(INSTALL_APP_DEST)""#)
    }

    let requiredRecipeTokenLists = [
        requiredDebugBuildTokens,
        ["rm", "-rf", "$(INSTALL_APP_DEST)"],
        ["cp", "-R", "$(RUN_APP_SOURCE)", "$(INSTALL_APP_DEST)"],
        ["Scripts/TerminateAgentInstances.swift", "$(AGENT_LABEL)"],
        ["Scripts/TerminateAppInstances.swift", "$(APP_BUNDLE_ID)"],
        ["open", "$(INSTALL_APP_DEST)"],
    ]
    guard recipeTokenLists == requiredRecipeTokenLists else {
        try fail(
            "run-audit failed: make run must preserve the canonical gated build and deployment recipe"
        )
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
