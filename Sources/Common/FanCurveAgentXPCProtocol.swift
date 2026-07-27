//
//  FanCurveAgentXPCProtocol.swift
//  FanCurve
//
//  Copyright © 2026, all rights reserved.
//

import Foundation

enum FanCurveAgentXPC {
  static let serviceName = generatedAgentBundleID
}

struct AgentFanRPMRequest: Codable, Sendable, Equatable {
  let fanIndex: UInt
  let rpm: Float
}

struct AgentCurveUpdate: Codable, Sendable, Equatable {
  let points: [CurvePoint]
  let interpolationMode: InterpolationMode
}

enum AgentCommand: Codable, Sendable, Equatable {
  case installOrRepairHelper
  case openSystemSettings
  case requestFanAuto(fanIndex: UInt)
  case requestFanRPM(AgentFanRPMRequest)
  case setApplyInBackground(Bool)
  case setBoostEnabled(Bool)
  case setCurve(AgentCurveUpdate)
  case setFanControlEnabled(Bool)

  var logName: String {
    switch self {
    case .installOrRepairHelper:
      return "install_or_repair_helper"
    case .openSystemSettings:
      return "open_system_settings"
    case .requestFanAuto:
      return "request_fan_auto"
    case .requestFanRPM:
      return "request_fan_rpm"
    case .setApplyInBackground:
      return "set_apply_in_background"
    case .setBoostEnabled:
      return "set_boost_enabled"
    case .setCurve:
      return "set_curve"
    case .setFanControlEnabled:
      return "set_fan_control_enabled"
    }
  }

}

struct AgentCommandResponse: Codable, Sendable, Equatable {
  let accepted: Bool
  let message: String?
}

struct AgentOwnershipEntry: Codable, Sendable, Equatable, Identifiable {
  let id: UInt
  let fanIndex: UInt
  let clientName: String
  let priority: Int
  let ageSeconds: TimeInterval
}

/// App-exported event protocol used by FanCurveAgent to push live runtime state.
/// Payloads remain `Data` so the Objective-C XPC boundary stays bridgeable.
@objc public protocol FanCurveAgentXPCEventProtocol: NSObjectProtocol {
  func agentRuntimeStateDidUpdate(_ stateData: Data)
}

/// App-facing XPC protocol exported by FanCurveAgent.
/// Payloads are kept Objective-C bridgeable so the protocol can be used by NSXPCConnection.
@objc public protocol FanCurveAgentXPCProtocol {
  /// Returns an encoded `RuntimeState`.
  func getCurrentState(reply: @escaping @Sendable (Bool, Data?, String?) -> Void)

  /// Registers the app's exported event sink for pushed runtime-state updates.
  func registerForEvents(reply: @escaping @Sendable (Bool, String?) -> Void)

  /// Requests an immediate agent tick without waiting for the polling interval.
  func requestRefresh(reply: @escaping @Sendable (Bool, String?) -> Void)

  /// Sends an encoded `AgentCommand`.
  func sendCommand(
    _ commandData: Data,
    reply: @escaping @Sendable (Bool, Data?, String?) -> Void
  )

  /// Returns encoded `[AgentOwnershipEntry]` rows from the helper through the agent.
  func getOwnership(reply: @escaping @Sendable (Bool, Data?, String?) -> Void)

  /// Updates whether the agent should apply fan control.
  func setFanControlEnabled(
    _ enabled: Bool,
    reply: @escaping @Sendable (Bool, String?) -> Void
  )

  /// Updates whether user boost is enabled.
  func setBoostEnabled(
    _ enabled: Bool,
    reply: @escaping @Sendable (Bool, String?) -> Void
  )

  /// Stores an encoded curve payload. The concrete curve/runtime payload type is owned
  /// by the RuntimeState worker and should replace this opaque data boundary later.
  func setCurve(
    _ curveData: Data,
    reply: @escaping @Sendable (Bool, String?) -> Void
  )
}
