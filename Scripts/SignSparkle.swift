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

    let signingPlan: [(path: String, preserveEntitlements: Bool)] = [
        ("\(currentVersionPath)/XPCServices/Installer.xpc", false),
        ("\(currentVersionPath)/XPCServices/Downloader.xpc", true),
        ("\(currentVersionPath)/Autoupdate", false),
        ("\(currentVersionPath)/Updater.app", false),
        (frameworkPath, false),
    ]

    // swift-mk's codesign-run owns the canonical Sparkle re-sign flags; the
    // resolved identity rides in through SWIFT_MK_SIGN_IDENTITY. There is no
    // direct-codesign fallback: a build without the swift-mk binary fails so
    // every signature comes from the one channel. Run make first.
    let srcroot = optionalEnv("SRCROOT")
    let swiftMkPath = "\(srcroot)/.make/swift-mk"
    guard !srcroot.isEmpty, fileExists(atPath: swiftMkPath) else {
        try fail("SignSparkle failed: \(swiftMkPath) not found; run make so swift-mk owns signing")
    }
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
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("SignSparkle failed: \(error)\n").utf8))
    exit(1)
}
