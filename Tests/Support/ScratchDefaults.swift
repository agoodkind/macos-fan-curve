//
//  ScratchDefaults.swift
//  FanCurveTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-10-26.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Darwin
import Foundation
import XCTest

private let scratchDefaultsLog = AppLog.make(category: "ScratchDefaults")

// MARK: - ScratchDefaults

/// `ScratchDefaults` uses an absolute suite path to store test preferences in a
/// unique temporary directory.
/// For suite names without an absolute path, `cfprefsd` retains the plist after
/// `removePersistentDomain(forName:)` clears its keys.
final class ScratchDefaults {
  private static let defaultsFileName = "defaults"
  private static let rootDirectoryName = "FanCurveScratchDefaults"
  private static let directoryLock = NSLock()

  static var rootDirectory: URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(rootDirectoryName, isDirectory: true)
  }

  private static var processDirectory: URL {
    rootDirectory.appendingPathComponent(String(getpid()), isDirectory: true)
  }

  let suiteName: String
  let defaults: UserDefaults
  let directory: URL

  init(label: String) throws {
    try Self.removeStaleProcessDirectories()
    let scratchDirectory = Self.processDirectory
      .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    try Self.directoryLock.withLock {
      try FileManager.default.createDirectory(
        at: scratchDirectory,
        withIntermediateDirectories: true
      )
    }
    directory = scratchDirectory
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

  /// `remove()` clears the suite's keys, then deletes the test's temporary folder.
  /// It then deletes the process folder only when that folder is empty.
  func remove() {
    defaults.removePersistentDomain(forName: suiteName)
    if let cleanupFailure = Self.removeDirectory(directory) {
      XCTFail("ScratchDefaults could not delete \(directory.path): \(cleanupFailure)")
      return
    }
    let processFolder = Self.processDirectory
    if let cleanupFailure = Self.removeDirectoryIfEmpty(processFolder) {
      XCTFail("ScratchDefaults could not delete \(processFolder.path): \(cleanupFailure)")
    }
  }

  /// `removeStaleProcessDirectories()` deletes preferences folders left by processes
  /// that ended before cleanup, including after `SIGKILL`, an abort, or an Objective-C
  /// exception. It deletes a folder only when `kill(pid, 0)` reports `ESRCH`, meaning
  /// the process no longer exists. It skips the current process and folder names that
  /// do not parse as process IDs.
  ///
  /// Each deletion logs the path through `AppLog`. If deletion fails and the folder
  /// still exists, the method logs the error and throws
  /// `ScratchDefaultsError.staleDirectoryRemovalFailed` with the path and error.
  /// If another process deleted the folder first, the method logs that and continues.
  static func removeStaleProcessDirectories() throws {
    let root = rootDirectory
    guard FileManager.default.fileExists(atPath: root.path) else {
      return
    }
    let entries: [URL]
    do {
      entries = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
      )
    } catch {
      scratchDefaultsLog.error(
        "scratch_defaults.sweep.list_failed path=\(root.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=fail-test"
      )
      throw ScratchDefaultsError.staleDirectoryListFailed(
        path: root.path,
        reason: error.localizedDescription
      )
    }
    for entry in entries {
      guard let processID = pid_t(entry.lastPathComponent),
        processID != getpid(),
        !processIsRunning(processID)
      else {
        continue
      }
      try removeStaleProcessDirectory(entry, processID: processID)
    }
  }

  private static func removeStaleProcessDirectory(_ directory: URL, processID: pid_t) throws {
    do {
      try FileManager.default.removeItem(at: directory)
    } catch {
      guard FileManager.default.fileExists(atPath: directory.path) else {
        scratchDefaultsLog.notice(
          "scratch_defaults.sweep.already_removed path=\(directory.path, privacy: .public) pid=\(Int(processID), privacy: .public) recovery=continue"
        )
        return
      }
      scratchDefaultsLog.error(
        "scratch_defaults.sweep.remove_failed path=\(directory.path, privacy: .public) pid=\(Int(processID), privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=fail-test"
      )
      throw ScratchDefaultsError.staleDirectoryRemovalFailed(
        path: directory.path,
        reason: error.localizedDescription
      )
    }
    scratchDefaultsLog.notice(
      "scratch_defaults.sweep.removed path=\(directory.path, privacy: .public) pid=\(Int(processID), privacy: .public)"
    )
  }

  private static func processIsRunning(_ processID: pid_t) -> Bool {
    if kill(processID, 0) == 0 {
      return true
    }
    return errno != ESRCH
  }

  private static func removeDirectoryIfEmpty(_ directory: URL) -> String? {
    let result = directoryLock.withLock {
      (status: rmdir(directory.path), code: errno)
    }
    guard result.status != 0 else {
      return nil
    }
    switch result.code {
    case ENOENT, ENOTEMPTY:
      return nil
    default:
      return String(cString: strerror(result.code))
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
  case staleDirectoryListFailed(path: String, reason: String)
  case staleDirectoryRemovalFailed(path: String, reason: String)
  case suiteUnavailable(suiteName: String, cleanupFailure: String?)
}
