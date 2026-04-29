#!/usr/bin/env swift

import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

func matchesSparkleTool(path: String, toolName: String) -> Bool {
    let suffixes = [
        "/SourcePackages/artifacts/",
        "/SourcePackages/checkouts/Sparkle/bin/\(toolName)",
        "/artifacts/",
        "/checkouts/Sparkle/bin/\(toolName)",
    ]

    if path.hasSuffix("/Sparkle/bin/\(toolName)") {
        return suffixes.contains { suffix in path.contains(suffix) }
    }
    return false
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    let buildDir = args.first ?? "build"
    guard args.count >= 2 else {
        try fail("usage: FindSparkleTool.swift [build-dir] tool-name")
    }
    let toolName = args[1]
    let searchRoots = [
        buildDir,
        "Tuist/.build/artifacts",
        "Tuist/.build/checkouts",
        "Tuist/.build",
    ]

    let fileManager = FileManager.default
    var matches: [String] = []
    for root in searchRoots where fileManager.fileExists(atPath: root) {
        guard let enumerator = fileManager.enumerator(atPath: root) else { continue }
        for case let path as String in enumerator {
            let fullPath = "\(root)/\(path)"
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            if matchesSparkleTool(path: fullPath, toolName: toolName) {
                matches.append(fullPath)
            }
        }
    }

    guard let firstMatch = matches.sorted().first else {
        try fail("Could not locate Sparkle tool \(toolName)")
    }
    print(firstMatch)
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("FindSparkleTool failed: \(error)\n").utf8))
    exit(1)
}
