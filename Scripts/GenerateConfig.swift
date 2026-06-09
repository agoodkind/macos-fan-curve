#!/usr/bin/env swift

import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

@discardableResult
func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}

func requiredEnv(_ key: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[key] else {
        try fail("GenerateConfig failed: missing required environment variable \(key)")
    }
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        try fail("GenerateConfig failed: required environment variable \(key) is empty")
    }
    return value
}

func optionalEnv(_ key: String, default defaultValue: String = "") -> String {
    ProcessInfo.processInfo.environment[key] ?? defaultValue
}

func pacificBuildDate() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
    formatter.dateFormat = "yyyy-MM-dd HH:mm z"
    return formatter.string(from: Date())
}

do {
    let srcRoot = try requiredEnv("SRCROOT")
    let targetName = try requiredEnv("TARGET_NAME")
    let generatedDir = "\(srcRoot)/Generated/\(targetName)"
    let templatesDir = "\(srcRoot)/Templates"

    try FileManager.default.createDirectory(
        atPath: generatedDir,
        withIntermediateDirectories: true
    )

    let replacements: [String: String] = [
        "@@HELPER_BUNDLE_ID@@": try requiredEnv("HELPER_BUNDLE_ID"),
        "@@HELPER_DISPLAY_NAME@@": optionalEnv("HELPER_DISPLAY_NAME", default: "Fan Curve Hardware Helper"),
        "@@APP_BUNDLE_ID@@": try requiredEnv("APP_BUNDLE_ID"),
        "@@APP_DISPLAY_NAME@@": optionalEnv("APP_DISPLAY_NAME", default: "Fan Curve"),
        "@@AGENT_BUNDLE_ID@@": try requiredEnv("AGENT_BUNDLE_ID"),
        "@@AGENT_DISPLAY_NAME@@": optionalEnv("AGENT_DISPLAY_NAME", default: "Fan Curve Background Control"),
        "@@AGENT_EXECUTABLE_NAME@@": optionalEnv("AGENT_EXECUTABLE_NAME", default: "FanCurveAgent"),
        "@@SHARED_SUITE_ID@@": try requiredEnv("SHARED_SUITE_ID"),
        "@@DEVELOPMENT_TEAM@@": try requiredEnv("DEVELOPMENT_TEAM"),
        "@@BUNDLE_ID_PREFIX@@": try requiredEnv("BUNDLE_ID_PREFIX"),
        "@@GIT_COMMIT@@": run("/usr/bin/git", ["-C", srcRoot, "rev-parse", "--short", "HEAD"]) ?? "unknown",
        "@@GIT_VERSION@@": run("/usr/bin/git", ["-C", srcRoot, "describe", "--tags", "--always", "--dirty"]) ?? "dev",
        "@@GIT_DIRTY@@": run("/usr/bin/git", ["-C", srcRoot, "diff", "--quiet"]) == nil ? "true" : "false",
        "@@GIT_DATE@@": run(
            "/usr/bin/git",
            ["-C", srcRoot, "log", "-1", "--format=%cd", "--date=format:%Y-%m-%d %H:%M %Z"],
            environment: ["TZ": "America/Los_Angeles"]
        ) ?? "unknown",
        "@@GIT_BRANCH@@": run("/usr/bin/git", ["-C", srcRoot, "rev-parse", "--abbrev-ref", "HEAD"]) ?? "unknown",
        "@@BUILD_DATE@@": pacificBuildDate(),
        "@@SPARKLE_FEED_URL@@": optionalEnv("SPARKLE_FEED_URL"),
        "@@SPARKLE_PUBLIC_ED_KEY@@": optionalEnv("SPARKLE_PUBLIC_ED_KEY"),
    ]

    guard let enumerator = FileManager.default.enumerator(atPath: templatesDir) else {
        try fail("GenerateConfig failed: templates directory not found: \(templatesDir)")
    }

    for case let relativePath as String in enumerator where relativePath.hasSuffix(".template") {
        let templateURL = URL(fileURLWithPath: templatesDir).appendingPathComponent(relativePath)
        let outputName = templateURL.deletingPathExtension().lastPathComponent
        let outputURL = URL(fileURLWithPath: generatedDir).appendingPathComponent(outputName)

        var contents = try String(contentsOf: templateURL, encoding: .utf8)
        for (token, value) in replacements {
            contents = contents.replacingOccurrences(of: token, with: value)
        }
        try contents.write(to: outputURL, atomically: true, encoding: .utf8)
    }
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("GenerateConfig failed: \(error)\n").utf8))
    exit(1)
}
