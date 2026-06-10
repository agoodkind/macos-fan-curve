#!/usr/bin/env swift

import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

func optionalEnv(_ key: String, default defaultValue: String = "") -> String {
    ProcessInfo.processInfo.environment[key] ?? defaultValue
}

func requiredEnv(_ key: String) throws -> String {
    let value = optionalEnv(key)
    guard !value.isEmpty else {
        try fail("SignSparkle failed: missing required environment variable \(key)")
    }
    return value
}

func fileExists(atPath path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "no output"
        try fail("SignSparkle failed: codesign exited with status \(process.terminationStatus): \(output)")
    }
}

func shouldAddTimestamp() -> Bool {
    let configuration = optionalEnv("CONFIGURATION")
    guard configuration == "Release" else { return false }

    let identityName = optionalEnv("EXPANDED_CODE_SIGN_IDENTITY_NAME")
    return identityName.isEmpty || identityName.contains("Developer ID")
}

func codesignArguments(
    identity: String,
    path: String,
    preserveEntitlements: Bool,
    addTimestamp: Bool
) -> [String] {
    var arguments = ["--force", "--sign", identity, "--options", "runtime"]
    if preserveEntitlements {
        arguments.append("--preserve-metadata=entitlements")
    }
    if addTimestamp {
        arguments.append("--timestamp")
    }
    arguments.append(path)
    return arguments
}

do {
    guard optionalEnv("CODE_SIGNING_ALLOWED", default: "NO") == "YES" else {
        exit(0)
    }

    let identity = optionalEnv("EXPANDED_CODE_SIGN_IDENTITY")
    guard !identity.isEmpty else {
        exit(0)
    }

    let builtProductsDir = try requiredEnv("BUILT_PRODUCTS_DIR")
    let productName = try requiredEnv("PRODUCT_NAME")
    let frameworkPath = "\(builtProductsDir)/\(productName).app/Contents/Frameworks/Sparkle.framework"
    let currentVersionPath = "\(frameworkPath)/Versions/Current"
    let addTimestamp = shouldAddTimestamp()

    let signingPlan: [(path: String, preserveEntitlements: Bool)] = [
        ("\(currentVersionPath)/XPCServices/Installer.xpc", false),
        ("\(currentVersionPath)/XPCServices/Downloader.xpc", true),
        ("\(currentVersionPath)/Autoupdate", false),
        ("\(currentVersionPath)/Updater.app", false),
        (frameworkPath, false),
    ]

    // swift-mk's codesign-run owns the canonical Sparkle re-sign flags; the
    // resolved identity rides in through SWIFT_MK_SIGN_IDENTITY. The direct
    // codesign loop survives only for a build without the swift-mk binary
    // (for example a raw Xcode GUI build before any make run).
    let srcroot = optionalEnv("SRCROOT")
    let swiftMkPath = "\(srcroot)/.make/swift-mk"
    if !srcroot.isEmpty, fileExists(atPath: swiftMkPath) {
        for entry in signingPlan where fileExists(atPath: entry.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: swiftMkPath)
            process.arguments = ["codesign-run", "--mode", "sparkle", entry.path]
            var environment = ProcessInfo.processInfo.environment
            environment["SWIFT_MK_SIGN_IDENTITY"] = identity
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                try fail("SignSparkle failed: swift-mk codesign-run failed for \(entry.path)")
            }
        }
    } else {
        for entry in signingPlan where fileExists(atPath: entry.path) {
            try run(
                "/usr/bin/codesign",
                codesignArguments(
                    identity: identity,
                    path: entry.path,
                    preserveEntitlements: entry.preserveEntitlements,
                    addTimestamp: addTimestamp
                )
            )
        }
    }
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("SignSparkle failed: \(error)\n").utf8))
    exit(1)
}
