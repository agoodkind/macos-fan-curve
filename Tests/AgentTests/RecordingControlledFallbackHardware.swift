//
//  RecordingControlledFallbackHardware.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - RecordingManagedService

final class RecordingManagedService:
  BackgroundAgentServiceManaging,
  HelperServiceManaging
{
  var status: ManagedServiceStatus {
    .enabled
  }

  func register() {
    _ = status
  }

  func unregister() {
    _ = status
  }

  func openSystemSettings() {
    _ = status
  }
}

// MARK: - RecordingControlledFallbackHardware

final class RecordingControlledFallbackHardware:
  FanHardware,
  @unchecked Sendable
{
  func shutdown() {
    _ = Self.self
  }

  func readAndApply(
    fanCount _: UInt,
    tempKeys _: [String],
    setFans _: [(index: UInt, rpm: Float)],
    autoFans _: [UInt],
    priority _: Int?
  ) -> FanHardwareBatchRead {
    FanHardwareBatchRead(fans: [], temps: [:])
  }

  func enumerateKeys() -> [String] {
    []
  }

  func getOwnership() -> [AgentOwnershipEntry] {
    []
  }

  func setFanRPM(
    _: UInt,
    rpm _: Float,
    priority _: Int?
  ) {
    _ = Self.self
  }

  func setFanAuto(
    _: UInt,
    priority _: Int?
  ) {
    _ = Self.self
  }
}
