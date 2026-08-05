//
//  BuildHashes.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

enum BuildHashes {
  static let appHash: String = BuildFingerprint.runningExecutableHash
  static let agentHash: String = BuildFingerprint.bundledAgentHash

  static func systemHelperHash(from state: SystemHelperRuntimeState) -> String {
    SystemHelperPresentation.activeHash(for: state)
  }
}
