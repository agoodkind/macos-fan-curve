//
//  SystemHelperArtifactFixture.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import XCTest

// MARK: - SystemHelperArtifactFixture

struct SystemHelperArtifactFixture {
  let executableURL: URL
  let identity: SystemHelperIdentity
  let validator: HashingArtifactValidator

  static func make(testCase: XCTestCase) throws -> SystemHelperArtifactFixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    testCase.addTeardownBlock {
      try FileManager.default.removeItem(at: directory)
    }
    let artifactURL = directory.appendingPathComponent("SystemHelper")
    try Data("bundled-system-helper".utf8).write(to: artifactURL)
    let artifactValidator = HashingArtifactValidator()
    return SystemHelperArtifactFixture(
      executableURL: artifactURL,
      identity: try artifactValidator.validate(at: artifactURL),
      validator: artifactValidator
    )
  }
}
