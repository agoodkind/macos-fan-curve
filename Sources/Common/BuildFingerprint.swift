//
//  BuildFingerprint.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-28.
//  Copyright © 2026
//

import CryptoKit
import Foundation

enum BuildFingerprint {
    static var runningExecutableHash: String {
        shortHash(of: Bundle.main.executableURL)
    }

    static var bundledAgentHash: String {
        shortHash(
            of: Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/\(generatedAgentExecutableName)"))
    }

    static func shortHash(of url: URL?) -> String {
        guard let url, let data = try? Data(contentsOf: url) else { return "n/a" }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }
}
