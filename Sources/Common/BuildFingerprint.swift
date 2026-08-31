//
//  BuildFingerprint.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-28.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import CryptoKit
import Foundation

private let buildFingerprintLog = AppLog.make(category: "BuildFingerprint")

private enum BuildFingerprintConstants {
  static let shortHashHexLength: Int = 12
}

// MARK: - BuildFingerprintError

enum BuildFingerprintError: LocalizedError {
  case executableUnreadable(String)
}

// MARK: - BuildFingerprint

enum BuildFingerprint {
  static var runningExecutableHash: String {
    shortHash(of: Bundle.main.executableURL)
  }

  static var bundledAgentHash: String {
    shortHash(
      of: Bundle.main.bundleURL
        .appendingPathComponent("Contents/MacOS/\(generatedAgentExecutableName)"))
  }

  static func hash(of url: URL) throws -> String {
    let bytes: Data
    do {
      bytes = try Data(contentsOf: url)
    } catch {
      buildFingerprintLog.notice(
        "fingerprint.read_failed executable=\(url.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=throw"
      )
      throw BuildFingerprintError.executableUnreadable(error.localizedDescription)
    }
    return SHA256.hash(data: bytes)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  static func presented(_ hash: String) -> String {
    String(hash.prefix(BuildFingerprintConstants.shortHashHexLength))
  }

  static func shortHash(of url: URL?) -> String {
    guard let url else { return "n/a" }
    do {
      return presented(try hash(of: url))
    } catch {
      return "n/a"
    }
  }
}
