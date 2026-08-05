//
//  AsyncErrorCapture.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

func captureError(
  _ operation: @Sendable () async throws -> Void
) async -> Error? {
  do {
    try await operation()
    return nil
  } catch {
    return error
  }
}
