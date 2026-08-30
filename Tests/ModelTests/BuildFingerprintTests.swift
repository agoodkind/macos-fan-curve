//
//  BuildFingerprintTests.swift
//  ModelTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@testable import FanCurveModels

final class BuildFingerprintTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func setUpWithError() throws {
    try super.setUpWithError()
    temporaryDirectories.removeAll()
  }

  override func tearDownWithError() throws {
    for directory in temporaryDirectories {
      try FileManager.default.removeItem(at: directory)
    }
    try super.tearDownWithError()
  }

  func testHashReturnsFullSHA256Digest() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    temporaryDirectories.append(directory)
    let executableURL = directory.appendingPathComponent("helper")
    try Data("Fan Curve helper identity\n".utf8).write(to: executableURL)

    let digest = try BuildFingerprint.hash(of: executableURL)

    expect(digest)
      == "b4bd6754f37de13597e5c5955eb2a7c8756263aae3b18f26b696a814c0e2b226"
  }

  func testHashRejectsMissingExecutable() {
    let missingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    expect { try BuildFingerprint.hash(of: missingURL) }
      .to(
        throwError { error in
          guard case let BuildFingerprintError.executableUnreadable(reason) = error else {
            fail("Expected executableUnreadable, got \(error)")
            return
          }
          expect(reason).toNot(beEmpty())
        })
  }
}
