//
//  ScratchDefaults.swift
//  FanCurveTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-10-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import XCTest

// MARK: - ScratchDefaults

/// `ScratchDefaults` uses an absolute suite path to store test preferences in a
/// unique temporary directory.
/// For suite names without an absolute path, `cfprefsd` retains the plist after
/// `removePersistentDomain(forName:)` clears its keys.
final class ScratchDefaults {
  private static let defaultsFileName = "defaults"

  let suiteName: String
  let defaults: UserDefaults
  private let directory: URL

  init(label: String) throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    suiteName = directory.appendingPathComponent(Self.defaultsFileName).path
    guard let scratchDefaults = UserDefaults(suiteName: suiteName) else {
      let cleanupFailure = Self.removeDirectory(directory)
      throw ScratchDefaultsError.suiteUnavailable(
        suiteName: suiteName,
        cleanupFailure: cleanupFailure
      )
    }
    defaults = scratchDefaults
  }

  /// `remove()` clears the suite's keys, then deletes its temporary directory.
  func remove() {
    defaults.removePersistentDomain(forName: suiteName)
    if let cleanupFailure = Self.removeDirectory(directory) {
      XCTFail("ScratchDefaults could not delete \(directory.path): \(cleanupFailure)")
    }
  }

  private static func removeDirectory(_ directory: URL) -> String? {
    guard FileManager.default.fileExists(atPath: directory.path) else {
      return nil
    }
    do {
      try FileManager.default.removeItem(at: directory)
    } catch {
      return error.localizedDescription
    }
    return nil
  }
}

// MARK: - ScratchDefaultsError

enum ScratchDefaultsError: Error {
  case suiteUnavailable(suiteName: String, cleanupFailure: String?)
}
