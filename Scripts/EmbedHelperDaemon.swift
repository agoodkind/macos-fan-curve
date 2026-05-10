#!/usr/bin/env swift

import Foundation

struct EmbedFailure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw EmbedFailure(description: "EmbedHelperDaemon failed: \(message)")
}

func requiredEnv(_ key: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
        try fail("missing required environment variable \(key)")
    }
    return value
}

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        try fail("\(executable) \(arguments.joined(separator: " ")) exited \(process.terminationStatus)")
    }
}

func removeIfPresent(_ path: String) throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    try FileManager.default.removeItem(atPath: path)
}

do {
    let sourceApp = try requiredEnv("SMC_FAN_HELPER_APP")
    let helperBundleID = try requiredEnv("HELPER_BUNDLE_ID")
    let sourceExecutable = "\(sourceApp)/Contents/MacOS/\(helperBundleID)"
    let sourcePlist = try requiredEnv("SRCROOT") + "/Derived/Generated/FanCurve/helper-daemon.plist"

    let builtProductsDir = try requiredEnv("BUILT_PRODUCTS_DIR")
    let productName = try requiredEnv("PRODUCT_NAME")
    let appBundle = "\(builtProductsDir)/\(productName).app"
    let destinationExecutable = "\(appBundle)/Contents/MacOS/\(helperBundleID)"
    let daemonDirectory = "\(appBundle)/Contents/Library/LaunchDaemons"
    let destinationPlist = "\(daemonDirectory)/\(helperBundleID).plist"

    guard FileManager.default.isExecutableFile(atPath: sourceExecutable) else {
        try fail("missing helper executable: \(sourceExecutable)")
    }
    guard FileManager.default.fileExists(atPath: sourcePlist) else {
        try fail("missing generated daemon plist: \(sourcePlist)")
    }

    try FileManager.default.createDirectory(atPath: daemonDirectory, withIntermediateDirectories: true)
    try removeIfPresent(destinationExecutable)
    try removeIfPresent(destinationPlist)
    try FileManager.default.copyItem(atPath: sourceExecutable, toPath: destinationExecutable)
    try FileManager.default.copyItem(atPath: sourcePlist, toPath: destinationPlist)

    let signingIdentity = ProcessInfo.processInfo.environment["EXPANDED_CODE_SIGN_IDENTITY"] ?? ""
    if !signingIdentity.isEmpty, signingIdentity != "-" {
        try run("/usr/bin/codesign", [
            "--force",
            "--sign",
            signingIdentity,
            "--options",
            "runtime",
            "--timestamp",
            destinationExecutable,
        ])
    }
} catch let failure as EmbedFailure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("EmbedHelperDaemon failed: \(error)\n").utf8))
    exit(1)
}
