//
//  ControlledXPCHarness+Cleanup.swift
//  FanCurveAgentTests
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-28.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation
import XCTest

private let controlledXPCCleanupLog = AppLog.make(
  category: "ControlledXPCIntegrationTests"
)

// MARK: - ControlledXPCHarness

extension ControlledXPCHarness {
  /// Deletes the session directory by renaming it out of the way first.
  ///
  /// `NSXPCListener.invalidate()` and `invalidateConnections()` are
  /// asynchronous, so a connection teardown can still be writing evidence
  /// while cleanup runs. The previous cleanup held exclusive locks and deleted
  /// in place, but `withExclusiveLock` opens lock files with `O_CREAT`, so a
  /// straggler writer could recreate one inside a directory that removal had
  /// already partly emptied, and the removal then failed with a permission
  /// error. That is what made every test in this suite intermittently fail.
  ///
  /// `rename(2)` is atomic. Once the session directory is moved, a straggler
  /// resolving the original path finds nothing there and fails harmlessly, and
  /// the tree being deleted has no writer that can reach it by path. That
  /// removes the race rather than retrying through it.
  func removeSessionDirectory() {
    let directory = store.directory
    let disposalDirectory =
      directory
      .deletingLastPathComponent()
      .appendingPathComponent(
        "\(directory.lastPathComponent)-disposing-\(UUID().uuidString)",
        isDirectory: true
      )
    controlledXPCCleanupLog.debug(
      "test_control.xpc.cleanup.started path=\(directory.path, privacy: .public)"
    )
    do {
      try FileManager.default.moveItem(at: directory, to: disposalDirectory)
    } catch {
      controlledXPCCleanupLog.error(
        "test_control.xpc.cleanup.rename_failed path=\(directory.path, privacy: .public) disposalPath=\(disposalDirectory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=report-test-failure"
      )
      XCTFail("Controlled XPC cleanup failed to rename: \(error.localizedDescription)")
      return
    }
    controlledXPCCleanupLog.debug(
      "test_control.xpc.cleanup.renamed disposalPath=\(disposalDirectory.path, privacy: .public)"
    )
    do {
      try FileManager.default.removeItem(at: disposalDirectory)
    } catch {
      // The rename succeeded, so the session directory is already unreachable
      // by its original path and no writer can resurrect it. What is left is an
      // orphaned disposal directory in the temporary directory, which the name
      // identifies.
      controlledXPCCleanupLog.error(
        "test_control.xpc.cleanup.remove_failed disposalPath=\(disposalDirectory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=report-test-failure"
      )
      XCTFail("Controlled XPC cleanup failed to remove: \(error.localizedDescription)")
      return
    }
    controlledXPCCleanupLog.debug(
      "test_control.xpc.cleanup.completed path=\(directory.path, privacy: .public)"
    )
  }
}
