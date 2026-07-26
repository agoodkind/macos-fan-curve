//
//  ManagedServiceTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class ManagedServiceTests: XCTestCase {
  func testEnabledHelperRepairUnregistersBeforeRegistering() {
    let service = RecordingHelperService(status: .enabled)

    let result = HelperServiceRegistration.installOrRepair(service: service)

    expect(service.operations) == [.unregister, .register]
    expect(result.statusBefore) == .enabled
    expect(result.statusAfterUnregister) == .notRegistered
    expect(result.statusAfterRegister) == .enabled
    expect(result.errorDescription) == nil
  }

  func testMissingHelperInstallRegistersWithoutUnregistering() {
    let service = RecordingHelperService(status: .notRegistered)

    let result = HelperServiceRegistration.installOrRepair(service: service)

    expect(service.operations) == [.register]
    expect(result.statusBefore) == .notRegistered
    expect(result.statusAfterUnregister) == nil
    expect(result.statusAfterRegister) == .enabled
    expect(result.errorDescription) == nil
  }
}

// MARK: - RecordingHelperService

private final class RecordingHelperService: HelperServiceManaging {
  enum Operation: Equatable {
    case register
    case unregister
    case openSystemSettings
  }

  private(set) var status: ManagedServiceStatus
  private(set) var operations: [Operation] = []

  init(status: ManagedServiceStatus) {
    self.status = status
  }

  func register() {
    operations.append(.register)
    status = .enabled
  }

  func unregister() {
    operations.append(.unregister)
    status = .notRegistered
  }

  func openSystemSettings() {
    operations.append(.openSystemSettings)
  }
}
