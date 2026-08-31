//
//  TestControlActivation.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Foundation

  private let testControlActivationLog = AppLog.make(category: "TestControlActivation")

  enum TestControlActivation: Equatable, Sendable {
    static let environmentKey = "FANCURVE_TEST_CONTROL_PATH"

    case controlled(sessionID: UUID, directory: URL)
    case production
    case refused(path: String)

    static func resolve(
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TestControlActivation {
      guard let path = environment[environmentKey] else {
        testControlActivationLog.info(
          "test_control.activation.production reason=environment-absent"
        )
        return .production
      }
      guard !path.isEmpty else {
        testControlActivationLog.error(
          "test_control.activation.refused path=empty reason=invalid-session recovery=refuse-test-operations"
        )
        return .refused(path: path)
      }
      let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
      do {
        let store = try TestControlSessionStore.open(at: directory)
        let state = try store.loadState()
        testControlActivationLog.info(
          "test_control.activation.controlled path=\(directory.path, privacy: .public) session=\(state.sessionID.uuidString, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return .controlled(sessionID: state.sessionID, directory: directory)
      } catch {
        testControlActivationLog.error(
          "test_control.activation.refused path=\(directory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=refuse-test-operations"
        )
        return .refused(path: path)
      }
    }
  }
#endif
