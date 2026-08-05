//
//  HashingArtifactValidator.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - HashingArtifactValidator

struct HashingArtifactValidator: SystemHelperArtifactValidating {
  func validate(at executableURL: URL) throws -> SystemHelperIdentity {
    SystemHelperIdentity(
      version: "2.0.0",
      build: "20",
      commit: "bundled-commit",
      executableHash: try BuildFingerprint.hash(of: executableURL),
      protocolVersion: 1
    )
  }
}

// MARK: - TestFailure

enum TestFailure: LocalizedError {
  case register
  case reset
  case unreachable
  case unregister

  var errorDescription: String? { String(describing: self) }
}
