#!/usr/bin/env swift

import CryptoKit
import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

func runIgnoringFailure(_ executable: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

func sha1Hex(of url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let digest = Insecure.SHA1.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 2 else {
        try fail("usage: RefreshIconCache.swift <app-bundle-path> <hash-stamp-path>")
    }

    let appBundle = args[0]
    let stampPath = args[1]
    let iconPath = "\(appBundle)/Contents/Resources/AppIcon.icns"
    let fileManager = FileManager.default

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: appBundle, isDirectory: &isDirectory), isDirectory.boolValue else {
        try fail("missing app bundle: \(appBundle)")
    }

    guard fileManager.fileExists(atPath: iconPath) else {
        try fail("missing app icon: \(iconPath)")
    }

    try fileManager.createDirectory(
        at: URL(fileURLWithPath: stampPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let currentHash = try sha1Hex(of: URL(fileURLWithPath: iconPath))
    let previousHash = (try? String(contentsOfFile: stampPath, encoding: .utf8))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

    guard currentHash != previousHash else {
        print("app icon unchanged; skipping icon cache refresh")
        exit(0)
    }

    try (currentHash + "\n").write(toFile: stampPath, atomically: true, encoding: .utf8)
    print("app icon changed; refreshing macOS icon caches")

    runIgnoringFailure("/usr/bin/qlmanage", ["-r", "cache"])
    runIgnoringFailure("/usr/bin/killall", ["Dock", "Finder", "iconservicesagent", "iconservicesd"])

    let cachesURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
    if let entries = try? fileManager.contentsOfDirectory(atPath: cachesURL.path) {
        for entry in entries
        where entry.hasPrefix("com.apple.iconservices") || entry == "com.apple.dock.iconcache" {
            try? fileManager.removeItem(at: cachesURL.appendingPathComponent(entry))
        }
    }

    try fileManager.setAttributes(
        [.modificationDate: Date()],
        ofItemAtPath: appBundle
    )
    runIgnoringFailure(
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
        ["-f", appBundle]
    )
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("RefreshIconCache failed: \(error)\n").utf8))
    exit(1)
}
