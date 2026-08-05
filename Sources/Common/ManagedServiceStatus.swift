//
//  ManagedServiceStatus.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - ManagedServiceStatus

enum ManagedServiceStatus: Sendable, Equatable, CustomStringConvertible {
  case enabled
  case notFound
  case notRegistered
  case requiresApproval
  case unknown(rawValue: Int)

  var description: String {
    switch self {
    case .enabled:
      return "enabled"
    case .notFound:
      return "notFound"
    case .notRegistered:
      return "notRegistered"
    case .requiresApproval:
      return "requiresApproval"
    case .unknown(let rawValue):
      return "unknown(\(rawValue))"
    }
  }
}

// MARK: - BackgroundAgentServiceManaging

protocol BackgroundAgentServiceManaging {
  var status: ManagedServiceStatus { get }

  func register() throws
  func unregister() throws
  func openSystemSettings() throws
}

// MARK: - HelperServiceManaging

protocol HelperServiceManaging: Sendable {
  var status: ManagedServiceStatus { get }

  func register() async throws
  func unregister() async throws
  func openSystemSettings() throws
}
