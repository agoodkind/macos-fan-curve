//
//  BuildFingerprint.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-28.
//  Copyright © 2026
//

import CryptoKit
import AppLog
import Foundation

private let buildFingerprintLog = AppLog.make(category: "BuildFingerprint")

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
        guard let url else { return "n/a" }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            buildFingerprintLog.notice(
                "fingerprint.read_failed path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=unavailable"
            )
            return "n/a"
        }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }
}
