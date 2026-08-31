//
//  ManagedServiceStatus.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Darwin
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

// MARK: - ManagedServiceFailureReason

enum ManagedServiceFailureReason: String, Sendable {
  case operationNotPermitted
  case other

  init(error: Error) {
    let serviceError = error as NSError
    let isPOSIXDenial =
      serviceError.domain == NSPOSIXErrorDomain
      && serviceError.code == Int(EPERM)
    let isServiceManagementDenial =
      serviceError.domain == "SMAppServiceErrorDomain"
      && serviceError.code == 1
    if isPOSIXDenial || isServiceManagementDenial {
      self = .operationNotPermitted
      return
    }
    self = .other
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
