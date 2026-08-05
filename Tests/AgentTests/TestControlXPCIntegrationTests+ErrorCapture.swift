//
//  TestControlXPCIntegrationTests+ErrorCapture.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - Error capture

@MainActor
extension TestControlXPCIntegrationTests {
  func captureError(
    _ operation: () async throws -> Void
  ) async -> Error? {
    do {
      try await operation()
      return nil
    } catch {
      return error
    }
  }
}
